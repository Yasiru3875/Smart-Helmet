import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CombinedStressService extends ChangeNotifier {
  // Input data
  double _heartRate = 0.0;
  double _temperature = 0.0;
  int _attention = 0;
  int _meditation = 0;
  Map<String, double> _eegBands = {
    'Delta': 0.0,
    'Theta': 0.0,
    'Alpha': 0.0,
    'Beta': 0.0,
    'Gamma': 0.0,
  };
  int _poorSignalLevel = 200;

  // Output data
  double _combinedStressScore = 0.0;
  String _stressLevel = "No Signal";
  String _stressEmoji = "📡";
  Color _stressColor = Colors.grey;
  bool _eegAvailable = false;
  String _dataSource = "None";

  // Buffers for smoothing
  final List<double> _stressBuffer = [];
  final int _bufferSize = 10;

  // Getters
  double get combinedStressScore => _combinedStressScore;
  String get stressLevel => _stressLevel;
  String get stressEmoji => _stressEmoji;
  Color get stressColor => _stressColor;
  bool get eegAvailable => _eegAvailable;
  String get dataSource => _dataSource;

  // Alias methods for compatibility
  String getStressLevelText() => _stressLevel;
  String getStressEmoji() => _stressEmoji;
  Color getStressColor() => _stressColor;

  // Update methods
  void updateHeartRate(double hr) {
    _heartRate = hr;
    _calculateCombinedStress();
  }

  void updateTemperature(double temp) {
    _temperature = temp;
    _calculateCombinedStress();
  }

  void updateEEGData({
    int? attention,
    int? meditation,
    Map<String, double>? bands,
    int? poorSignalLevel,
  }) {
    if (attention != null) _attention = attention;
    if (meditation != null) _meditation = meditation;
    if (bands != null) _eegBands = bands;
    if (poorSignalLevel != null) _poorSignalLevel = poorSignalLevel;

    _eegAvailable = _poorSignalLevel <= 50;
    _calculateCombinedStress();
  }

  void _calculateCombinedStress() {
    double stressScore;

    if (_eegAvailable && _hasValidEEGData()) {
      // Use combined EEG + physiological data
      stressScore = _calculateEEGBasedStress();
      _dataSource = "EEG + HR + Temp";
    } else if (_hasValidPhysiologicalData()) {
      // Fallback to physiological data only
      stressScore = _calculatePhysiologicalStress();
      _dataSource = "HR + Temp (EEG Unavailable)";
    } else {
      // No valid data
      _setNoSignal();
      return;
    }

    // Smooth the stress score
    _stressBuffer.add(stressScore);
    if (_stressBuffer.length > _bufferSize) {
      _stressBuffer.removeAt(0);
    }

    final smoothedStress = _stressBuffer.isEmpty
        ? stressScore
        : _stressBuffer.reduce((a, b) => a + b) / _stressBuffer.length;

    _updateStressState(smoothedStress);
  }

  bool _hasValidEEGData() {
    return _attention > 0 ||
        _meditation > 0 ||
        _eegBands.values.any((v) => v > 0);
  }

  bool _hasValidPhysiologicalData() {
    return _heartRate > 0 && _temperature > 0;
  }

  double _calculateEEGBasedStress() {
    // EEG-based stress calculation
    double alpha = _eegBands['Alpha']! + 1e-6;
    double beta = _eegBands['Beta']!;
    double gamma = _eegBands['Gamma']!;
    double rawRatio = (beta + gamma) / alpha;
    double bandStress = rawRatio / (rawRatio + 2.0);
    bandStress = bandStress.clamp(0.0, 5.0) / 5.0;

    double medStress = 1.0 - (_meditation / 100.0).clamp(0.0, 1.0);

    double signalQuality = (200 - _poorSignalLevel).clamp(0, 200) / 200.0;
    signalQuality = math.pow(signalQuality, 1.5).toDouble();

    double eegStress = (bandStress + medStress) / 2.0 * signalQuality;

    // Physiological stress
    double physioStress = _calculatePhysiologicalStress();

    // Weighted combination (EEG has higher weight when available)
    return (eegStress * 0.7) + (physioStress * 0.3);
  }

  double _calculatePhysiologicalStress() {
    if (_heartRate <= 0 || _temperature <= 0) return 0.0;

    // Heart rate stress component
    double hrStress = 0.0;
    if (_heartRate > 120) {
      hrStress = 1.0;
    } else if (_heartRate > 100) {
      hrStress = 0.7 + ((_heartRate - 100) / 20) * 0.3;
    } else if (_heartRate < 50) {
      hrStress = 0.8;
    } else if (_heartRate >= 60 && _heartRate <= 90) {
      hrStress = 0.1; // Normal range
    } else {
      // 50-59 or 91-100
      hrStress = 0.3;
    }

    // Temperature stress component
    double tempStress = 0.0;
    if (_temperature > 38.5) {
      tempStress = 1.0;
    } else if (_temperature > 38.0) {
      tempStress = 0.6 + ((_temperature - 38.0) / 0.5) * 0.4;
    } else if (_temperature < 36.0) {
      tempStress = 0.7;
    } else if (_temperature >= 36.5 && _temperature <= 37.2) {
      tempStress = 0.1; // Normal range
    } else {
      // 36.0-36.4 or 37.3-38.0
      tempStress = 0.3;
    }

    // Heart rate variability simulation (based on HR)
    double hrvFactor = 1.0;
    if (_heartRate > 100 || _heartRate < 60) {
      hrvFactor = 0.7; // Lower HRV
    }

    // Combined physiological stress
    double physioStress = (hrStress * 0.6) + (tempStress * 0.3) + ((1.0 - hrvFactor) * 0.1);

    return physioStress.clamp(0.0, 1.0);
  }

  void _updateStressState(double stressScore) {
    _combinedStressScore = stressScore;

    String newLevel;
    String newEmoji;
    Color newColor;

    if (stressScore <= 0.20) {
      newLevel = "Very Relaxed";
      newEmoji = "😌";
      newColor = Colors.green[800]!;
    } else if (stressScore <= 0.40) {
      newLevel = "Relaxed";
      newEmoji = "🙂";
      newColor = Colors.green[400]!;
    } else if (stressScore <= 0.60) {
      newLevel = "Neutral";
      newEmoji = "😐";
      newColor = Colors.yellow[800]!;
    } else if (stressScore <= 0.75) {
      newLevel = "Elevated";
      newEmoji = "😟";
      newColor = Colors.orange[700]!;
    } else {
      newLevel = "High Stress";
      newEmoji = "😰";
      newColor = Colors.red[700]!;
    }

    if (_stressLevel != newLevel) {
      _stressLevel = newLevel;
      _stressEmoji = newEmoji;
      _stressColor = newColor;
      notifyListeners();
    }
  }

  void _setNoSignal() {
    _combinedStressScore = 0.0;
    _stressLevel = "No Signal";
    _stressEmoji = "📡";
    _stressColor = Colors.grey;
    _dataSource = "None";
    _stressBuffer.clear();
    notifyListeners();
  }

  void reset() {
    _heartRate = 0.0;
    _temperature = 0.0;
    _attention = 0;
    _meditation = 0;
    _eegBands.updateAll((key, value) => 0.0);
    _poorSignalLevel = 200;
    _eegAvailable = false;
    _stressBuffer.clear();
    _setNoSignal();
  }

  // Get detailed stress breakdown for UI
  Map<String, dynamic> getStressBreakdown() {
    return {
      'combinedScore': _combinedStressScore,
      'heartRate': _heartRate,
      'temperature': _temperature,
      'attention': _attention,
      'meditation': _meditation,
      'eegBands': Map.from(_eegBands),
      'eegAvailable': _eegAvailable,
      'dataSource': _dataSource,
      'hrStress': _heartRate > 0 ? _calculateHRStress() : 0.0,
      'tempStress': _temperature > 0 ? _calculateTempStress() : 0.0,
    };
  }

  double _calculateHRStress() {
    if (_heartRate <= 0) return 0.0;
    if (_heartRate > 120) return 1.0;
    if (_heartRate > 100) return 0.7 + ((_heartRate - 100) / 20) * 0.3;
    if (_heartRate < 50) return 0.8;
    if (_heartRate >= 60 && _heartRate <= 90) return 0.1;
    return 0.3;
  }

  double _calculateTempStress() {
    if (_temperature <= 0) return 0.0;
    if (_temperature > 38.5) return 1.0;
    if (_temperature > 38.0) return 0.6 + ((_temperature - 38.0) / 0.5) * 0.4;
    if (_temperature < 36.0) return 0.7;
    if (_temperature >= 36.5 && _temperature <= 37.2) return 0.1;
    return 0.3;
  }
}
