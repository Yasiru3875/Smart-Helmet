// lib/providers/alert_engine.dart
// Monitors real-time sensor data and triggers emergency alerts
// when HIGH risk is sustained continuously for 30 seconds.
// Sends automated WhatsApp messages via Twilio (NO hardware modules required).

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import 'sensor_data_provider.dart';
import 'user_profile_provider.dart';
import '../services/bluetooth_manager.dart';
import '../services/whatsapp_alert_service.dart';
import '../services/background_emergency_service.dart';

enum AlertState {
  idle,
  monitoring, // risk detected, waiting to see if it's sustained
  alerting, // 30s sustained — showing cancel window
  sent, // WhatsApp alert sent
}

class AlertEngine with ChangeNotifier {
  // ── Dependencies ──────────────────────────────────────────────────────────
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final WhatsAppAlertService _whatsappService = WhatsAppAlertService();
  final FlutterTts _tts = FlutterTts();
  bool _backgroundServiceInitialized = false;
  String _cloudFunctionUrl = '';

  // ── State ─────────────────────────────────────────────────────────────────
  AlertState _state = AlertState.idle;
  int _cancelCountdown = 10; // seconds user has to cancel after 30s sustained
  DateTime? _riskStartTime; // when current sustained high-risk started
  int _sustainedSeconds = 0; // how many continuous seconds of high risk
  String _currentRiskType = '';
  int _currentRiskPercent = 0;
  String _lastAlertId = '';
  bool _alertCooldown = false; // prevents re-triggering immediately after send

  // ── Monitoring ────────────────────────────────────────────────────────────
  Timer? _sustainedCheckTimer; // fires every 1s to update sustained counter
  Timer? _cancelTimer; // counts down the 10s cancel window
  StreamSubscription? _sensorSub;

  // Thresholds for high risk
  static const int _hrThreshold = 120; // BPM
  static const double _tempThreshold = 38.0; // °C
  static const double _riskPercentThreshold = 75.0; // % from TFLite model
  static const int _sustainedSeconds30 = 30; // seconds required
  static const int _cancelWindowSeconds = 10; // cancel window

  // ── Getters ───────────────────────────────────────────────────────────────
  AlertState get alertState => _state;
  int get cancelCountdown => _cancelCountdown;
  int get sustainedSeconds => _sustainedSeconds;
  bool get isMonitoring => _state == AlertState.monitoring;
  bool get isAlerting => _state == AlertState.alerting;
  bool get isSent => _state == AlertState.sent;

  // ── External API ──────────────────────────────────────────────────────────

  /// Configure WhatsApp service (call this during app initialization)
  void configureWhatsApp({required String cloudFunctionUrl}) {
    _cloudFunctionUrl = cloudFunctionUrl;
    _whatsappService.configure(cloudFunctionUrl: cloudFunctionUrl);
    debugPrint('✅ AlertEngine: WhatsApp service configured');
  }

  /// Check if WhatsApp is configured
  bool get isWhatsAppConfigured => _whatsappService.isConfigured;

  /// Initialize background service for emergency monitoring
  Future<void> initializeBackgroundService() async {
    if (_backgroundServiceInitialized) return;
    
    try {
      await BackgroundEmergencyService.requestPermissions();
      await BackgroundEmergencyService.initializeService();
      _backgroundServiceInitialized = true;
      debugPrint('✅ Background emergency service initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize background service: $e');
    }
  }

  /// Called from member1_page after every TFLite inference.
  /// [riskPercent] is 0-100 from the model.
  /// [hr] and [temp] are raw sensor values.
  void onNewRiskReading({
    required int riskPercent,
    required double hr,
    required double temp,
    required UserProfileProvider profile,
    required BluetoothManager btManager,
  }) async {
    // Initialize background service on first risk reading
    if (!_backgroundServiceInitialized) {
      await initializeBackgroundService();
    }

    // Update background service with latest sensor data
    await BackgroundEmergencyService.updateSensorData(
      heartRate: hr.toInt(),
      temperature: temp,
      riskPercent: riskPercent,
    );

    if (_alertCooldown) return;
    if (_state == AlertState.alerting || _state == AlertState.sent) return;

    final bool isHighRisk = _evaluateHighRisk(
      riskPercent: riskPercent,
      hr: hr,
      temp: temp,
    );

    if (isHighRisk) {
      _riskStartTime ??= DateTime.now();
      _currentRiskPercent = riskPercent;
      _currentRiskType = _describeRisk(riskPercent: riskPercent, hr: hr, temp: temp);

      // Start timer if not already running
      _startSustainedTimer(profile: profile, btManager: btManager);
    } else {
      // Risk dropped — reset everything
      _resetMonitoring();
    }
  }

  void cancelAlert() {
    debugPrint('🚫 Alert cancelled by user');
    _cancelTimer?.cancel();
    _state = AlertState.idle;
    _sustainedSeconds = 0;
    _riskStartTime = null;
    _alertCooldown = true;

    _tts.speak('Alert cancelled. Stay safe.');

    // Resume normal monitoring after 60s cooldown
    Future.delayed(const Duration(seconds: 60), () {
      _alertCooldown = false;
      notifyListeners();
    });

    notifyListeners();
  }

  // ── Internal logic ────────────────────────────────────────────────────────

  bool _evaluateHighRisk({
    required int riskPercent,
    required double hr,
    required double temp,
  }) {
    if (riskPercent >= _riskPercentThreshold) return true;
    if (hr > _hrThreshold) return true;
    if (hr > 110 && temp > _tempThreshold) return true;
    return false;
  }

  String _describeRisk({
    required int riskPercent,
    required double hr,
    required double temp,
  }) {
    if (riskPercent >= _riskPercentThreshold) {
      return 'CRITICAL cardiac risk ($riskPercent%)';
    }
    if (hr > _hrThreshold && temp > _tempThreshold) {
      return 'High heart rate (${hr.toInt()} BPM) + elevated temperature (${temp.toStringAsFixed(1)}°C)';
    }
    if (hr > _hrThreshold) {
      return 'Dangerously high heart rate (${hr.toInt()} BPM)';
    }
    return 'High cardiac risk ($riskPercent%)';
  }

  void _startSustainedTimer({
    required UserProfileProvider profile,
    required BluetoothManager btManager,
  }) {
    if (_sustainedCheckTimer != null) return; // already running

    _state = AlertState.monitoring;
    notifyListeners();

    _sustainedCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_riskStartTime == null) {
        timer.cancel();
        _sustainedCheckTimer = null;
        return;
      }

      _sustainedSeconds =
          DateTime.now().difference(_riskStartTime!).inSeconds;
      notifyListeners();

      if (_sustainedSeconds >= _sustainedSeconds30) {
        timer.cancel();
        _sustainedCheckTimer = null;
        _triggerAlert(profile: profile, btManager: btManager);
      }
    });
  }

  void _resetMonitoring() {
    _sustainedCheckTimer?.cancel();
    _sustainedCheckTimer = null;
    _riskStartTime = null;
    _sustainedSeconds = 0;

    if (_state == AlertState.monitoring) {
      _state = AlertState.idle;
      notifyListeners();
    }
  }

  Future<void> _triggerAlert({
    required UserProfileProvider profile,
    required BluetoothManager btManager,
  }) async {
    _state = AlertState.alerting;
    _cancelCountdown = _cancelWindowSeconds;
    notifyListeners();

    // Vibrate
    try {
      if (await Vibration.hasVibrator() == true) {
        Vibration.vibrate(pattern: [0, 500, 300, 500, 300, 1000]);
      }
    } catch (_) {}

    // Voice alert
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.speak(
      'Warning! High risk health condition detected. '
      'Emergency alert will be sent in 10 seconds. '
      'Press cancel to stop.',
    );

    // 10-second cancel countdown
    _cancelTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _cancelCountdown--;
      notifyListeners();

      if (_cancelCountdown <= 0) {
        timer.cancel();
        await _sendAlertAndLog(profile: profile, btManager: btManager);
      }
    });
  }

  Future<void> _sendAlertAndLog({
    required UserProfileProvider profile,
    required BluetoothManager btManager,
  }) async {
    // Get current GPS
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (_) {}

    final contacts = profile.emergencyPhoneNumbers;
    final riderName = profile.userName;

    // 🆕 Send via WhatsApp automatically (NO user interaction required)
    // This replaces the old GSM/SIM800L hardware module approach
    if (_whatsappService.isConfigured) {
      final result = await _whatsappService.sendEmergencyAlert(
        contacts: contacts,
        riderName: riderName,
        riskType: _currentRiskType,
        riskPercent: _currentRiskPercent,
      );

      if (result['success'] == true) {
        debugPrint('✅ WhatsApp emergency alert sent successfully');
        await _tts.speak('WhatsApp emergency alert sent successfully.');
      } else {
        debugPrint('⚠️ WhatsApp alert failed: ${result['error']}');
        await _tts.speak('Emergency alert sending failed. Please seek help manually.');
      }
    } else {
      debugPrint('❌ WhatsApp service not configured - alert not sent');
      await _tts.speak('Emergency alert not sent. WhatsApp service not configured.');
    }

    // Log to Firestore
    try {
      final docRef = await _firestore.collection('alert_history').add({
        'userId': profile.userName, // will be UID in prod — passed in
        'alertType': 'HEART_ATTACK_RISK',
        'riskLevel': _currentRiskPercent >= 75 ? 'CRITICAL' : 'HIGH',
        'riskPercentage': _currentRiskPercent,
        'riskType': _currentRiskType,
        'location': pos != null
            ? GeoPoint(pos.latitude, pos.longitude)
            : null,
        'googleMapsLink': pos != null
            ? 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}'
            : null,
        'riderName': riderName,
        'contactsNotified': contacts,
        'alertMethod': 'WHATSAPP_AUTOMATED',
        'wasCancelled': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _lastAlertId = docRef.id;
    } catch (e) {
      debugPrint('⚠️ Failed to log alert: $e');
    }

    _state = AlertState.sent;
    _alertCooldown = true;
    _sustainedSeconds = 0;
    _riskStartTime = null;
    notifyListeners();

    await _tts.speak('Emergency alert sent. Help is on the way.');

    // Resume monitoring after 3-minute cooldown
    Future.delayed(const Duration(minutes: 3), () {
      _alertCooldown = false;
      _state = AlertState.idle;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sustainedCheckTimer?.cancel();
    _cancelTimer?.cancel();
    _sensorSub?.cancel();
    _tts.stop();
    super.dispose();
  }
}
