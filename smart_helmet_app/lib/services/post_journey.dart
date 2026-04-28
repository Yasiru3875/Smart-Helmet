// lib/services/post_journey.dart
//
// Runs the post_journey_risk_model.tflite (v2.0) to classify each sensor
// reading as SAFE (0) or RISKY (1), then clusters risky GPS points into
// "danger zones" for rendering on the JourneyReportScreen map.
//
// Model features (12 total — matches risk_thresholds.json feature_order):
//   [0]  Acc_X
//   [1]  Acc_Y
//   [2]  Acc_Z
//   [3]  Gyr_X
//   [4]  Gyr_Y
//   [5]  Gyr_Z
//   [6]  Roll             (lean angle in degrees)
//   [7]  lean_abs         = |Roll|
//   [8]  gyrZ_abs         = |Gyr_Z|
//   [9]  accelX_abs       = |Acc_X|
//   [10] resultant_accel  = sqrt(ax²+ay²+az²)
//   [11] resultant_gyro   = sqrt(gx²+gy²+gz²)
//
// z-score scaling: z = (x - mean) / scale  (applied before inference)

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/journey_model.dart';

/// A danger zone — a GPS location that the model flagged as risky.
class DangerZone {
  final LatLng center;
  final double radiusMeters;
  final double dangerScore;   // 0.0–1.0 (model confidence)
  final String label;         // e.g. "Sharp Turn", "Hard Brake"

  DangerZone({
    required this.center,
    required this.radiusMeters,
    required this.dangerScore,
    required this.label,
  });
}

class DangerZoneService {
  Interpreter? _interpreter;
  bool _isLoaded = false;

  static const double _threshold = 0.5;

  // ─── StandardScaler parameters from risk_thresholds.json ────────────────
  // Feature order: Acc_X, Acc_Y, Acc_Z, Gyr_X, Gyr_Y, Gyr_Z,
  //                Roll, lean_abs, gyrZ_abs, accelX_abs,
  //                resultant_accel, resultant_gyro

  static const List<double> _scalerMean = [
    0.081575,   // Acc_X
    0.126298,   // Acc_Y
    9.840321,   // Acc_Z
    -0.015702,  // Gyr_X
    -1.110636,  // Gyr_Y
    -0.307245,  // Gyr_Z
    0.701306,   // Roll
    8.409398,   // lean_abs
    5.103149,   // gyrZ_abs
    1.769899,   // accelX_abs
    10.215316,  // resultant_accel
    16.397422,  // resultant_gyro
  ];

  static const List<double> _scalerScale = [
    2.447383,   // Acc_X
    1.170494,   // Acc_Y
    1.710779,   // Acc_Z
    16.230145,  // Gyr_X
    12.258078,  // Gyr_Y
    8.052585,   // Gyr_Z
    11.501457,  // Roll
    7.87765,    // lean_abs
    6.236698,   // gyrZ_abs
    1.692276,   // accelX_abs
    1.66984,    // resultant_accel
    14.524976,  // resultant_gyro
  ];

  // ─── Top-3 feature thresholds for rule-based labelling ──────────────────
  static const double _leanAbsBoundary      = 10.0327;   // degrees
  static const double _resultantGyroBoundary = 18.4073;  // °/s
  static const double _gyrZAbsBoundary       = 6.0325;   // °/s

  // ─── Load model from Flutter assets ──────────────────────────────────────

  Future<void> loadModel() async {
    if (_isLoaded) return;
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/post_journey_risk_model.tflite',
      );
      _isLoaded = true;
    } catch (e) {
      _isLoaded = false;
    }
  }

  bool get isLoaded => _isLoaded;

  // ─── Build & scale the 12-feature vector ────────────────────────────────

  List<double> _buildFeatures({
    required double accelX,
    required double accelY,
    required double accelZ,
    required double gyroX,
    required double gyroY,
    required double gyroZ,
    required double roll,
  }) {
    final leanAbs        = roll.abs();
    final gyrZAbs        = gyroZ.abs();
    final accelXAbs      = accelX.abs();
    final resultantAccel = sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);
    final resultantGyro  = sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ);

    final raw = <double>[
      accelX, accelY, accelZ,
      gyroX, gyroY, gyroZ,
      roll,
      leanAbs, gyrZAbs, accelXAbs,
      resultantAccel, resultantGyro,
    ];

    // Apply z-score scaling: z = (x - mean) / scale
    final scaled = List<double>.generate(raw.length, (i) {
      return (raw[i] - _scalerMean[i]) / _scalerScale[i];
    });

    return scaled;
  }

  /// Returns danger score 0.0–1.0, or null if model not ready.
  double? predict({
    required double accelX, required double accelY, required double accelZ,
    required double gyroX,  required double gyroY,  required double gyroZ,
    required double roll,
  }) {
    if (!_isLoaded || _interpreter == null) return null;

    final features = _buildFeatures(
      accelX: accelX, accelY: accelY, accelZ: accelZ,
      gyroX: gyroX, gyroY: gyroY, gyroZ: gyroZ,
      roll: roll,
    );

    final input  = [features];
    final output = List.generate(1, (_) => List<double>.filled(1, 0.0));
    _interpreter!.run(input, output);

    return output[0][0].clamp(0.0, 1.0);
  }

  // ─── Rule-based label using top-3 feature thresholds ────────────────────

  String _labelFromSensors({
    required double accelX,
    required double gyroX,
    required double gyroY,
    required double gyroZ,
    required double roll,
  }) {
    final leanAbs       = roll.abs();
    final gyrZAbs       = gyroZ.abs();
    final resultantGyro = sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ);

    // Use top-3 feature boundaries from risk_thresholds.json
    if (leanAbs > _leanAbsBoundary * 1.5)            return 'Dangerous Lean';
    if (gyrZAbs > _gyrZAbsBoundary * 2.5)             return 'Risky Turn';
    if (gyrZAbs > _gyrZAbsBoundary * 1.5)             return 'Sharp Turn';
    if (resultantGyro > _resultantGyroBoundary * 1.5) return 'Aggressive Riding';
    if (-accelX > 3.0)                                 return 'Emergency Brake';
    if (-accelX > 1.5)                                 return 'Hard Brake';
    if (leanAbs > _leanAbsBoundary)                   return 'Risky Lean';
    if (resultantGyro > _resultantGyroBoundary)       return 'Erratic Motion';
    if (gyrZAbs > _gyrZAbsBoundary)                   return 'Sharp Manoeuvre';
    return 'Danger Zone';
  }

  // ─── Analyse a full ride ──────────────────────────────────────────────────
  //
  // Iterates over every SensorReading that has a GPS fix and runs the model.
  // Returns a list of DangerZone objects to render as circles on the map.
  //
  // We also include TurnEvents and BrakingEvents as guaranteed danger points.

  Future<List<DangerZone>> analyseRide(JourneyData journey) async {
    await loadModel();

    final List<DangerZone> zones = [];

    // 1. Run model on all sensor readings that have a GPS fix
    for (final reading in journey.sensorReadings) {
      // SensorReadings only have lat/lng if they were added with GPS position
      // We check the GPS track for the nearest timestamp instead
      final gpsPoint = _nearestGpsPoint(journey.gpsTrack, reading.timestamp);
      if (gpsPoint == null) continue;
      if (gpsPoint.latitude == 0.0 && gpsPoint.longitude == 0.0) continue;

      // Calculate lean angle exactly like member3_page.dart computes it
      final double roll = atan2(reading.accelY, reading.accelX) * (180.0 / pi);

      final score = predict(
        accelX: reading.accelX, accelY: reading.accelY, accelZ: reading.accelZ,
        gyroX: reading.gyroX,  gyroY: reading.gyroY,  gyroZ: reading.gyroZ,
        roll: roll,
      );

      if (score != null && score >= _threshold) {
        zones.add(DangerZone(
          center: LatLng(gpsPoint.latitude, gpsPoint.longitude),
          radiusMeters: 25 + score * 35,   // 25–60 m based on confidence
          dangerScore: score,
          label: _labelFromSensors(
            accelX: reading.accelX,
            gyroX: reading.gyroX,
            gyroY: reading.gyroY,
            gyroZ: reading.gyroZ,
            roll: roll,
          ),
        ));
      }
    }

    // 2. Add turn events as guaranteed danger zones
    for (final event in journey.turnEvents) {
      if (event.latitude == 0.0 && event.longitude == 0.0) continue;
      final score = event.severity == 'risky' ? 0.92 : 0.72;
      zones.add(DangerZone(
        center: LatLng(event.latitude, event.longitude),
        radiusMeters: event.severity == 'risky' ? 40 : 30,
        dangerScore: score,
        label: event.severity == 'risky' ? 'Risky Turn' : 'Sharp Turn',
      ));
    }

    // 3. Add braking events as guaranteed danger zones
    for (final brake in journey.brakingEvents) {
      if (brake.latitude == 0.0 && brake.longitude == 0.0) continue;
      zones.add(DangerZone(
        center: LatLng(brake.latitude, brake.longitude),
        radiusMeters: brake.severity == 'emergency' ? 45 : 30,
        dangerScore: brake.severity == 'emergency' ? 0.95 : 0.75,
        label: brake.severity == 'emergency' ? 'Emergency Brake' : 'Hard Brake',
      ));
    }

    // 4. Merge overlapping zones (cluster within 30 m)
    return _clusterZones(zones, clusterRadiusM: 30);
  }

  // ─── Nearest GPS point by timestamp ──────────────────────────────────────

  GpsPoint? _nearestGpsPoint(List<GpsPoint> track, DateTime ts) {
    if (track.isEmpty) return null;
    GpsPoint? best;
    int bestDiff = 999999999;
    for (final p in track) {
      if (p.timestamp == null) continue;
      final diff = (p.timestamp!.difference(ts).inMilliseconds).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = p;
      }
    }
    return bestDiff < 10000 ? best : null; // only within 10 s
  }

  // ─── Cluster overlapping zones ────────────────────────────────────────────

  List<DangerZone> _clusterZones(List<DangerZone> zones, {double clusterRadiusM = 30}) {
    if (zones.isEmpty) return [];

    final List<DangerZone> merged = [];
    final List<bool> used = List.filled(zones.length, false);

    // Sort by danger score descending so higher-confidence zones absorb lower
    final sorted = List<DangerZone>.from(zones)
      ..sort((a, b) => b.dangerScore.compareTo(a.dangerScore));

    for (int i = 0; i < sorted.length; i++) {
      if (used[i]) continue;
      final anchor = sorted[i];
      double sumLat   = anchor.center.latitude;
      double sumLng   = anchor.center.longitude;
      double maxScore = anchor.dangerScore;
      double maxRadius = anchor.radiusMeters;
      int    count    = 1;

      for (int j = i + 1; j < sorted.length; j++) {
        if (used[j]) continue;
        final dist = _haversineM(
          anchor.center.latitude, anchor.center.longitude,
          sorted[j].center.latitude, sorted[j].center.longitude,
        );
        if (dist <= clusterRadiusM) {
          used[j] = true;
          sumLat  += sorted[j].center.latitude;
          sumLng  += sorted[j].center.longitude;
          count++;
          if (sorted[j].dangerScore  > maxScore)  maxScore  = sorted[j].dangerScore;
          if (sorted[j].radiusMeters > maxRadius) maxRadius = sorted[j].radiusMeters;
        }
      }

      merged.add(DangerZone(
        center: LatLng(sumLat / count, sumLng / count),
        radiusMeters: maxRadius,
        dangerScore: maxScore,
        label: anchor.label,
      ));
    }

    return merged;
  }

  // ─── Haversine distance in metres ────────────────────────────────────────

  double _haversineM(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double deg) => deg * pi / 180;

  // ─── Model Diagnostics (call from UI to verify model works) ───────────

  Future<String> runDiagnostics() async {
    final buf = StringBuffer();
    buf.writeln('═══════════════════════════════════════════');
    buf.writeln('  POST-JOURNEY RISK MODEL v2.0 DIAGNOSTICS');
    buf.writeln('═══════════════════════════════════════════');

    // 1. Load model
    await loadModel();
    buf.writeln('Model loaded: $_isLoaded');
    if (!_isLoaded) {
      buf.writeln('❌ FAILED — model could not be loaded from assets.');
      final result = buf.toString();
      debugPrint(result);
      return result;
    }
    buf.writeln('Interpreter: ${_interpreter != null ? "OK" : "NULL"}');

    // Print input/output tensor info
    try {
      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);
      buf.writeln('Input shape:  ${inputTensor.shape}  type: ${inputTensor.type}');
      buf.writeln('Output shape: ${outputTensor.shape}  type: ${outputTensor.type}');
    } catch (e) {
      buf.writeln('Tensor info error: $e');
    }

    buf.writeln('');

    // 2. Test cases: { label, accelX, accelY, accelZ, gyroX, gyroY, gyroZ }
    final testCases = <Map<String, dynamic>>[
      {
        'name': '🟢 Normal Cruise (expect SAFE / low score)',
        'accelX': 0.1, 'accelY': 0.1, 'accelZ': 9.81,
        'gyroX': 2.0, 'gyroY': 1.5, 'gyroZ': 8.0,
      },
      {
        'name': '🟠 Sharp Turn (gyroZ=110, expect moderate risk)',
        'accelX': 0.3, 'accelY': 1.2, 'accelZ': 9.80,
        'gyroX': 5.0, 'gyroY': 4.0, 'gyroZ': 110.0,
      },
      {
        'name': '🔴 Risky Turn (gyroZ=175, expect HIGH risk)',
        'accelX': 0.5, 'accelY': 2.5, 'accelZ': 9.78,
        'gyroX': 9.5, 'gyroY': 8.5, 'gyroZ': 175.0,
      },
      {
        'name': '🔴 Emergency Brake (accelZ=-7.5, expect HIGH risk)',
        'accelX': -7.5, 'accelY': 0.1, 'accelZ': 9.80,
        'gyroX': 3.0, 'gyroY': 2.0, 'gyroZ': 15.0,
      },
      {
        'name': '🔴 Dangerous Lean (roll~45°, expect HIGH risk)',
        'accelX': 0.2, 'accelY': 6.9, 'accelZ': 7.0,
        'gyroX': 12.0, 'gyroY': 10.0, 'gyroZ': 25.0,
      },
    ];

    for (final tc in testCases) {
      final aX = (tc['accelX'] as num).toDouble();
      final aY = (tc['accelY'] as num).toDouble();
      final aZ = (tc['accelZ'] as num).toDouble();
      final gX = (tc['gyroX'] as num).toDouble();
      final gY = (tc['gyroY'] as num).toDouble();
      final gZ = (tc['gyroZ'] as num).toDouble();

      // Compute roll same way as member3_page.dart
      final roll = atan2(aY, aX) * (180.0 / pi);

      final score = predict(
        accelX: aX, accelY: aY, accelZ: aZ,
        gyroX: gX, gyroY: gY, gyroZ: gZ,
        roll: roll,
      );

      final label = _labelFromSensors(
        accelX: aX, gyroX: gX, gyroY: gY, gyroZ: gZ, roll: roll,
      );

      // Also show the raw + scaled features for debugging
      final features = _buildFeatures(
        accelX: aX, accelY: aY, accelZ: aZ,
        gyroX: gX, gyroY: gY, gyroZ: gZ,
        roll: roll,
      );

      buf.writeln('─── ${tc['name']} ───');
      buf.writeln('  Inputs:  aX=$aX  aY=$aY  aZ=$aZ  gX=$gX  gY=$gY  gZ=$gZ');
      buf.writeln('  Roll:    ${roll.toStringAsFixed(2)}°');
      buf.writeln('  Scaled:  ${features.map((f) => f.toStringAsFixed(4)).join(", ")}');
      buf.writeln('  Score:   ${score?.toStringAsFixed(4) ?? "NULL"}');
      buf.writeln('  Risk:    ${score != null && score >= _threshold ? "⚠ RISKY" : "✓ SAFE"}');
      buf.writeln('  Label:   $label');
      buf.writeln('');
    }

    buf.writeln('═══════════════════════════════════════════');
    buf.writeln('  DIAGNOSTICS COMPLETE');
    buf.writeln('═══════════════════════════════════════════');

    final result = buf.toString();
    // Print each line separately so logcat doesn't truncate
    for (final line in result.split('\n')) {
      debugPrint(line);
    }
    return result;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}
