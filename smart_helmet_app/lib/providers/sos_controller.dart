import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/sos_state.dart';
import '../services/sos_alert_service.dart';
import '../services/sos_bluetooth_service.dart';

class SOSController extends ChangeNotifier {
  SOSState _state = SOSState.initial();
  Timer? _countdownTimer;
  
  final SOSAlertService _alertService = SOSAlertService();
  final SOSBluetoothService _bluetoothService = SOSBluetoothService();
  final FlutterTts _flutterTts = FlutterTts();

  // Emergency contact numbers
  final List<String> _emergencyContacts = [
    '+94771234567', // Example emergency contact 1
    '+94771234568', // Example emergency contact 2
  ];

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
    _sendSMSToEmergencyContacts();
    _alertService.sendEmergencyAlert();
  }

  Future<void> _sendSMSToEmergencyContacts() async {
    final message = 'EMERGENCY SOS! Rider in distress. Location: https://maps.google.com/?q=0,0';
    
    for (String contact in _emergencyContacts) {
      final uri = Uri.parse('sms:$contact?body=${Uri.encodeComponent(message)}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _bluetoothService.dispose();
    _flutterTts.stop();
    super.dispose();
  }
}
