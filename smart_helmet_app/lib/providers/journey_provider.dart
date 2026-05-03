import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/journey_model.dart';

class JourneyProvider with ChangeNotifier {
  JourneyData? _currentJourney;
  List<TurnEvent> _currentTurnEvents = [];
  List<SensorReading> _currentSensorReadings = [];
  List<GpsPoint> _gpsTrack = [];
  List<BrakingEvent> _brakingEvents = [];
  List<LeanEvent> _leanEvents = [];
  DateTime? _lastLeanEventTime; // 2-second debounce for lean events

  double _totalDistance = 0.0;
  List<double> _speedReadings = [];
  double _maxSpeed = 0.0;
  double _maxTurnRate = 0.0;

  // For braking detection: compare previous accelX/Y with current
  double? _prevAccelX;
  double? _prevAccelY;
  // Threshold: sudden deceleration > 0.5 g (approx 4.9 m/s²) triggers a braking event
  static const double _brakingThreshold = 0.5;

  // Lean angle thresholds (degrees)
  static const double _riskyLeanThreshold = 35.0;
  static const double _criticalLeanThreshold = 45.0;

  JourneyData? get currentJourney => _currentJourney;
  List<TurnEvent> get currentTurnEvents => _currentTurnEvents;
  List<SensorReading> get currentSensorReadings => _currentSensorReadings;
  List<LeanEvent> get currentLeanEvents => _leanEvents;

  // Start a new journey
  void startJourney(String? startLocation, String? destination) {
    _currentJourney = JourneyData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: DateTime.now(),
      startLocation: startLocation,
      destination: destination,
    );
    _currentTurnEvents = [];
    _currentSensorReadings = [];
    _gpsTrack = [];
    _brakingEvents = [];
    _leanEvents = [];
    _lastLeanEventTime = null;
    _totalDistance = 0.0;
    _speedReadings = [];
    _maxSpeed = 0.0;
    _maxTurnRate = 0.0;
    _prevAccelX = null;
    _prevAccelY = null;
    notifyListeners();
  }

  // Add GPS point to the live track
  void addGpsPoint({
    required double latitude,
    required double longitude,
    required double speedKmh,
    DateTime? timestamp,
  }) {
    if (_currentJourney == null) return;
    // Only record if we have a real GPS fix
    if (latitude == 0.0 && longitude == 0.0) return;
    _gpsTrack.add(GpsPoint(
      latitude: latitude,
      longitude: longitude,
      speedKmh: speedKmh,
      timestamp: timestamp ?? DateTime.now(),
    ));
    notifyListeners();
  }

  // Add turn event
  void addTurnEvent({
    required String severity,
    required double turnRate,
    required double latitude,
    required double longitude,
  }) {
    if (_currentJourney == null) return;

    if (turnRate > _maxTurnRate) _maxTurnRate = turnRate;

    _currentTurnEvents.add(TurnEvent(
      timestamp: DateTime.now(),
      severity: severity,
      turnRate: turnRate,
      latitude: latitude,
      longitude: longitude,
    ));
    notifyListeners();
  }

  // Add sensor reading
  void addBrakingEvent({
    required double deceleration,
    required double latitude,
    required double longitude,
    required double speedBefore,
    required String severity,
  }) {
    if (_currentJourney == null) return;

    _brakingEvents.add(
      BrakingEvent(
        timestamp: DateTime.now(),
        deceleration: deceleration,
        latitude: latitude,
        longitude: longitude,
        speedBefore: speedBefore,
        severity: severity,
      ),
    );

    notifyListeners();
  }

  // Add a lean event (called from member3_page when lean angle exceeds thresholds)
  void addLeanEvent({
    required double leanAngle,
    required String severity,
    required double latitude,
    required double longitude,
  }) {
    if (_currentJourney == null) return;

    // 2-second debounce: skip if last lean event was less than 2 seconds ago
    final now = DateTime.now();
    if (_lastLeanEventTime != null &&
        now.difference(_lastLeanEventTime!).inMilliseconds < 2000) {
      return;
    }
    _lastLeanEventTime = now;

    _leanEvents.add(LeanEvent(
      timestamp: now,
      leanAngle: leanAngle,
      severity: severity,
      latitude: latitude,
      longitude: longitude,
    ));
    notifyListeners();
  }

  // Add sensor reading (braking is detected in member3_page with correct thresholds)
  void addSensorReading({
    required int heartRate,
    required double temperature,
    required int stressLevel,
    double accelX = 0.0,
    double accelY = 0.0,
    double accelZ = 0.0,
    double gyroX = 0.0,
    double gyroY = 0.0,
    double gyroZ = 0.0,
    double latitude = 0.0,
    double longitude = 0.0,
    double speedKmh = 0.0,
  }) {
    if (_currentJourney == null) return;

    _currentSensorReadings.add(SensorReading(
      timestamp: DateTime.now(),
      heartRate: heartRate,
      temperature: temperature,
      stressLevel: stressLevel,
      accelX: accelX,
      accelY: accelY,
      accelZ: accelZ,
      gyroX: gyroX,
      gyroY: gyroY,
      gyroZ: gyroZ,
    ));

    // ── Lean angle detection ─────────────────────────────
    // Formula: atan2(lateral accel, vertical accel) → degrees
    final double computedLeanAngle = atan2(accelY, accelX) * (180.0 / pi);
    final double absLean = computedLeanAngle.abs();

    if (absLean > _criticalLeanThreshold) {
      addLeanEvent(
        leanAngle: computedLeanAngle,
        severity: 'critical',
        latitude: latitude,
        longitude: longitude,
      );
    } else if (absLean > _riskyLeanThreshold) {
      addLeanEvent(
        leanAngle: computedLeanAngle,
        severity: 'risky',
        latitude: latitude,
        longitude: longitude,
      );
    }

    notifyListeners();
  }

  // Update distance and speed
  void updateDistanceAndSpeed(double distance, double speed) {
    _totalDistance = distance;
    _speedReadings.add(speed);
    if (speed > _maxSpeed) _maxSpeed = speed;
    notifyListeners();
  }

  // End journey and prepare final data
  JourneyData? endJourney() {
    if (_currentJourney == null) return null;

    final int sharpTurns =
        _currentTurnEvents.where((e) => e.severity == 'sharp').length;
    final int riskyTurns =
        _currentTurnEvents.where((e) => e.severity == 'risky').length;
    final int criticalLeans =
        _leanEvents.where((e) => e.severity == 'critical').length;

    final double averageSpeed = _speedReadings.isNotEmpty
        ? _speedReadings.reduce((a, b) => a + b) / _speedReadings.length
        : 0.0;

    // ─── Danger Prediction (rule-based, matches real sensor ranges) ─
    String dangerPrediction;
    if (_currentSensorReadings.length > 5) {
      if (riskyTurns > 2 ||
          _brakingEvents.where((b) => b.severity == 'emergency').length > 1 ||
          criticalLeans > 1 ||
          _maxSpeed > 100.0) {
        dangerPrediction = 'DANGEROUS';
      } else if (riskyTurns > 0 ||
          _brakingEvents.isNotEmpty ||
          _leanEvents.isNotEmpty ||
          sharpTurns > 3 ||
          _maxSpeed > 80.0) {
        dangerPrediction = 'MODERATE RISK';
      } else {
        dangerPrediction = 'SAFE';
      }
    } else {
      dangerPrediction = 'SAFE';
    }

    final completedJourney = JourneyData(
      id: _currentJourney!.id,
      startTime: _currentJourney!.startTime,
      endTime: DateTime.now(),
      startLocation: _currentJourney!.startLocation,
      destination: _currentJourney!.destination,
      sharpTurns: sharpTurns,
      riskyTurns: riskyTurns,
      totalBrakingEvents: _brakingEvents.length,
      averageSpeed: averageSpeed,
      maxSpeed: _maxSpeed,
      maxTurnRate: _maxTurnRate,
      totalDistance: _totalDistance,
      dangerPrediction: dangerPrediction,
      turnEvents: List.from(_currentTurnEvents),
      brakingEvents: List.from(_brakingEvents),
      leanEvents: List.from(_leanEvents),
      sensorReadings: List.from(_currentSensorReadings),
      gpsTrack: List.from(_gpsTrack),
    );

    _currentJourney = null;
    _currentTurnEvents = [];
    _currentSensorReadings = [];
    _gpsTrack = [];
    _brakingEvents = [];
    _leanEvents = [];
    _lastLeanEventTime = null;
    _totalDistance = 0.0;
    _speedReadings = [];
    _maxSpeed = 0.0;
    _maxTurnRate = 0.0;
    _prevAccelX = null;
    _prevAccelY = null;

    notifyListeners();
    return completedJourney;
  }

  // Get turn counts
  int get sharpTurnCount =>
      _currentTurnEvents.where((e) => e.severity == 'sharp').length;
  int get riskyTurnCount =>
      _currentTurnEvents.where((e) => e.severity == 'risky').length;

  // Get real-time tracked distance for home_dashboard to read before endJourney()
  double get trackedDistanceKm => _totalDistance;

  // Check if journey is active
  bool get isJourneyActive => _currentJourney != null;
}
