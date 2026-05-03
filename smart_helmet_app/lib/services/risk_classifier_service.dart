import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class RiskClassifierService {
  Interpreter? _interpreter;
  List<double> _scalerMean = [];
  List<double> _scalerScale = [];
  bool _isReady = false;

  Future<void> init() async {
    try {
      // Load scaler params from JSON
      final jsonStr =
          await rootBundle.loadString('assets/risk_thresholds.json');
      final json = jsonDecode(jsonStr);
      _scalerMean = List<double>.from(json['scaler']['mean']);
      _scalerScale = List<double>.from(json['scaler']['scale']);
      
      // Load TFLite model - Using post_journey_risk_model.tflite as per existing assets
      _interpreter =
          await Interpreter.fromAsset('assets/post_journey_risk_model.tflite');
      _isReady = true;
    } catch (e) {
      print("Error initializing RiskClassifierService: $e");
      _isReady = false;
    }
  }

  // Compute roll angle from raw accel (MPU6050 has no fusion)
  double computeRoll(double ax, double ay, double az) =>
      math.atan2(ay, math.sqrt(ax * ax + az * az)) * (180 / math.pi);

  // Standardise feature vector using scaler params from JSON
  List<double> _standardise(List<double> raw) => List.generate(
      raw.length, (i) => (raw[i] - _scalerMean[i]) / _scalerScale[i]);

  // Build 12-feature vector — same order as FEATURE_COLS in notebook
  List<double> buildFeatures({
    required double accelX,
    required double accelY,
    required double accelZ,
    required double gyroX,
    required double gyroY,
    required double gyroZ,
  }) {
    final roll = computeRoll(accelX, accelY, accelZ);
    final raw = [
      accelX,
      accelY,
      accelZ,
      gyroX,
      gyroY,
      gyroZ,
      roll,
      roll.abs(),
      gyroZ.abs(),
      accelX.abs(),
      math.sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ),
      math.sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ),
    ];
    return _standardise(raw);
  }

  // Returns probability 0.0=Safe … 1.0=Risky
  double classify({
    required double accelX,
    required double accelY,
    required double accelZ,
    required double gyroX,
    required double gyroY,
    required double gyroZ,
  }) {
    if (!_isReady || _interpreter == null) return 0.0;
    final features = buildFeatures(
      accelX: accelX,
      accelY: accelY,
      accelZ: accelZ,
      gyroX: gyroX,
      gyroY: gyroY,
      gyroZ: gyroZ,
    );
    final input = [features.map((v) => v.toDouble()).toList()];
    final output = List.generate(1, (_) => List<double>.filled(1, 0.0));
    _interpreter!.run(input, output);
    return output[0][0].clamp(0.0, 1.0);
  }

  void dispose() => _interpreter?.close();
}
