// lib/providers/sensor_data_provider.dart
import 'package:flutter/material.dart';

class SensorDataProvider with ChangeNotifier {
  int _heartRate = 78;
  double _temperature = 36.8;
  int _stressLevel = 32;
  bool _dangerAlert = false;

  int get heartRate => _heartRate;
  double get temperature => _temperature;
  int get stressLevel => _stressLevel;
  bool get dangerAlert => _dangerAlert;

  bool _isRideRisky = false; // new field
  String _rideSafetyStatus = "SAFE"; // human-readable

  bool get isRideRisky => _isRideRisky;
  String get rideSafetyStatus => _rideSafetyStatus;

  void updateRideSafety(bool isRisky) {
    if (isRisky != _isRideRisky) {
      _isRideRisky = isRisky;
      _rideSafetyStatus = isRisky ? "RISKY" : "SAFE";
      notifyListeners();
    }
  }

  void updateHeartRate(int value) {
    if (value != _heartRate) {
      _heartRate = value.clamp(40, 220);
      notifyListeners();
    }
  }

  void updateTemperature(double value) {
    if ((value - _temperature).abs() > 0.05) {
      // small change filter
      _temperature = value.clamp(30.0, 42.0);
      notifyListeners();
    }
  }

  void updateStressLevel(int value) {
    if (value != _stressLevel) {
      _stressLevel = value.clamp(0, 100);
      notifyListeners();
    }
  }

  void updateDangerAlert(bool value) {
    if (value != _dangerAlert) {
      _dangerAlert = value;
      notifyListeners();
    }
  }

  void reset() {
    _heartRate = 78;
    _temperature = 36.8;
    _stressLevel = 32;
    _dangerAlert = false;
    notifyListeners();
  }

  // Optional: reset when journey ends
  void resetRideSafety() {
    _isRideRisky = false;
    _rideSafetyStatus = "SAFE";
    notifyListeners();
  }
}
