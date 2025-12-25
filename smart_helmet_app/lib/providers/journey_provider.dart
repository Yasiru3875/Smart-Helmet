import 'package:flutter/foundation.dart';
import '../models/journey_model.dart';

class JourneyProvider with ChangeNotifier {
  JourneyData? _currentJourney;
  List<TurnEvent> _currentTurnEvents = [];
  List<SensorReading> _currentSensorReadings = [];
  
  double _totalDistance = 0.0;
  List<double> _speedReadings = [];
  
  JourneyData? get currentJourney => _currentJourney;
  List<TurnEvent> get currentTurnEvents => _currentTurnEvents;
  List<SensorReading> get currentSensorReadings => _currentSensorReadings;
  
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
    _totalDistance = 0.0;
    _speedReadings = [];
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
  void addSensorReading({
    required int heartRate,
    required double temperature,
    required int stressLevel,
  }) {
    if (_currentJourney == null) return;
    
    _currentSensorReadings.add(SensorReading(
      timestamp: DateTime.now(),
      heartRate: heartRate,
      temperature: temperature,
      stressLevel: stressLevel,
    ));
    notifyListeners();
  }
  
  // Update distance and speed
  void updateDistanceAndSpeed(double distance, double speed) {
    _totalDistance = distance;
    _speedReadings.add(speed);
    notifyListeners();
  }
  
  // End journey and prepare final data
  JourneyData? endJourney() {
    if (_currentJourney == null) return null;
    
    int sharpTurns = _currentTurnEvents.where((e) => e.severity == 'sharp').length;
    int riskyTurns = _currentTurnEvents.where((e) => e.severity == 'risky').length;
    
    double averageSpeed = _speedReadings.isNotEmpty
        ? _speedReadings.reduce((a, b) => a + b) / _speedReadings.length
        : 0.0;
    
    final completedJourney = JourneyData(
      id: _currentJourney!.id,
      startTime: _currentJourney!.startTime,
      endTime: DateTime.now(),
      startLocation: _currentJourney!.startLocation,
      destination: _currentJourney!.destination,
      sharpTurns: sharpTurns,
      riskyTurns: riskyTurns,
      averageSpeed: averageSpeed,
      totalDistance: _totalDistance,
      turnEvents: List.from(_currentTurnEvents),
      sensorReadings: List.from(_currentSensorReadings),
    );
    
    _currentJourney = null;
    _currentTurnEvents = [];
    _currentSensorReadings = [];
    _totalDistance = 0.0;
    _speedReadings = [];
    
    notifyListeners();
    return completedJourney;
  }
  
  // Get turn counts
  int get sharpTurnCount => _currentTurnEvents.where((e) => e.severity == 'sharp').length;
  int get riskyTurnCount => _currentTurnEvents.where((e) => e.severity == 'risky').length;
  
  // Check if journey is active
  bool get isJourneyActive => _currentJourney != null;
}