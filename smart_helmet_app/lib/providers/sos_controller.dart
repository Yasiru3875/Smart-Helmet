import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/sos_state.dart';
import '../services/sos_alert_service.dart';
import '../services/sos_bluetooth_service.dart';
import '../services/whatsapp_alert_service.dart';

class SOSController extends ChangeNotifier {
  SOSState _state = SOSState.initial();
  Timer? _countdownTimer;
  
  final SOSAlertService _alertService = SOSAlertService();
  final SOSBluetoothService _bluetoothService = SOSBluetoothService();
  final WhatsAppAlertService _whatsappService = WhatsAppAlertService();
  final FlutterTts _flutterTts = FlutterTts();

  // 🆕 Emergency contacts — loaded from UserProfileProvider after login
  List<String> _emergencyContacts = [];
  String _riderName = 'Rider';

  /// Called from EntryPoint/HomeScreen after profile loads
  void setEmergencyContacts(List<String> contacts, {String riderName = 'Rider'}) {
    _emergencyContacts = contacts;
    _riderName = riderName;
    debugPrint('SOSController: contacts updated → $contacts');
  }

  /// Configure WhatsApp service with Cloud Function URL
  /// Call this during app initialization (e.g., in main.dart after Firebase init)
  void configureWhatsApp({required String cloudFunctionUrl}) {
    _whatsappService.configure(cloudFunctionUrl: cloudFunctionUrl);
    debugPrint('SOSController: WhatsApp service configured');
  }

  /// Check if WhatsApp service is properly configured
  bool get isWhatsAppConfigured => _whatsappService.isConfigured;

  /// Get WhatsApp configuration status for debugging
  Map<String, dynamic> get whatsAppStatus => _whatsappService.getConfigStatus();

  SOSState get state => _state;

  SOSController() {
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _alertService.initialize();
    await _bluetoothService.initialize();
    await _initTTS();

    // Listen for ESP32 triggers
    _bluetoothService.onEmergencyTriggered.listen((_) {
      startSOS();
    });
  }

  Future<void> _initTTS() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
  }

  void startSOS() {
    if (_state.isActive) return;

    _state = _state.copyWith(
      isActive: true,
      countdown: 60,
      status: 'Emergency Detected',
    );
    notifyListeners();

    _startCountdown();
    _triggerAlerts();
    _speakAlert('Emergency detected. SOS will be sent in 60 seconds. Press cancel to stop.');
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_state.countdown <= 0) {
        _sendSOS();
        timer.cancel();
      } else {
        _state = _state.copyWith(countdown: _state.countdown - 1);
        notifyListeners();

        // Voice alerts for first 5 and last 5 seconds
        if (_state.countdown == 55 || _state.countdown == 50 || 
            _state.countdown == 45 || _state.countdown == 40 || 
            _state.countdown == 35 || _state.countdown == 30 || 
            _state.countdown == 25 || _state.countdown == 20 || 
            _state.countdown == 15 || _state.countdown == 10) {
          _speakAlert('$_state.countdown seconds remaining');
        }
        if (_state.countdown == 5) {
          _speakAlert('5 seconds remaining. Press cancel now to stop SOS.');
        }
        if (_state.countdown == 4) {
          _speakAlert('4');
        }
        if (_state.countdown == 3) {
          _speakAlert('3');
        }
        if (_state.countdown == 2) {
          _speakAlert('2');
        }
        if (_state.countdown == 1) {
          _speakAlert('1');
        }
      }
    });
  }

  void _triggerAlerts() {
    _alertService.triggerVibration();
    _alertService.showNotification(
      title: 'Emergency Detected',
      body: 'Cancelling in ${_state.countdown} seconds...',
    );
  }

  Future<void> _speakAlert(String message) async {
    await _flutterTts.speak(message);
  }

  void cancelSOS() {
    if (!_state.isActive) return;

    _countdownTimer?.cancel();

    _state = _state.copyWith(
      isActive: false,
      countdown: 60,
      status: 'Cancelled',
    );
    notifyListeners();

    _bluetoothService.sendCommand('SOS_CANCEL');
    _alertService.cancelNotification();
    _speakAlert('SOS cancelled. You are safe.');
  }

  void _sendSOS() {
    _state = _state.copyWith(
      isActive: false,
      status: 'SOS Sent',
    );
    notifyListeners();

    _speakAlert('SOS sent. Help is on the way.');
    _sendWhatsAppToEmergencyContacts();
    _alertService.sendEmergencyAlert();
  }

  /// Send automated WhatsApp emergency alerts (NO user interaction required)
  /// This replaces the old SMS method that required user to press send
  Future<void> _sendWhatsAppToEmergencyContacts() async {
    if (!_whatsappService.isConfigured) {
      debugPrint('❌ WhatsApp service not configured. Call configureWhatsApp() first.');
      _speakAlert('Emergency alert not sent. WhatsApp not configured.');
      return;
    }

    final contacts = _emergencyContacts.isNotEmpty
        ? _emergencyContacts
        : ['+94771234567']; // fallback if not configured

    debugPrint('🚨 Sending automated WhatsApp SOS to ${contacts.length} contacts...');
    _speakAlert('Sending emergency alerts via WhatsApp.');

    try {
      final result = await _whatsappService.sendEmergencyAlert(
        contacts: contacts,
        riderName: _riderName,
        riskType: 'MANUAL SOS - Emergency Detected',
        riskPercent: 100,
        additionalInfo: 'Rider triggered SOS countdown and did not cancel. Immediate assistance required.',
      );

      if (result['success'] == true) {
        debugPrint('✅ WhatsApp SOS sent successfully to all contacts');
        _speakAlert('Emergency alerts sent successfully.');
      } else {
        debugPrint('⚠️ Some WhatsApp alerts failed: ${result['results']}');
        _speakAlert('Some emergency alerts may not have been delivered.');
      }
    } catch (e) {
      debugPrint('❌ Failed to send WhatsApp SOS: $e');
      _speakAlert('Failed to send emergency alert. Please call for help manually.');
    }
  }

  /// Send test WhatsApp message to verify setup
  Future<Map<String, dynamic>> sendTestWhatsApp(String phoneNumber) async {
    if (!_whatsappService.isConfigured) {
      return {'success': false, 'error': 'WhatsApp service not configured'};
    }
    return await _whatsappService.sendTestMessage(
      phoneNumber: phoneNumber,
      riderName: _riderName,
    );
  }

  /// Trigger health-based emergency (called from AlertEngine)
  /// Automatically sends WhatsApp when health risk is sustained
  Future<void> triggerHealthEmergency({
    required String riskType,
    required int riskPercent,
  }) async {
    if (_state.isActive) {
      debugPrint('SOS already active, skipping duplicate trigger');
      return;
    }

    debugPrint('🚨 Health emergency triggered: $riskType ($riskPercent%)');
    
    // Start the countdown - if user doesn't cancel, WhatsApp sends automatically
    startSOS();
    
    // Update state with health-specific info
    _state = _state.copyWith(
      status: 'Health Emergency: $riskType',
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _bluetoothService.dispose();
    _flutterTts.stop();
    super.dispose();
  }
}
