import 'package:cloud_firestore/cloud_firestore.dart';

class JourneyData {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final String? startLocation;
  final String? destination;
  final int sharpTurns;
  final int riskyTurns;
  final double averageSpeed;
  final double totalDistance;
  final List<TurnEvent> turnEvents;
  final List<SensorReading> sensorReadings;
  
  JourneyData({
    required this.id,
    required this.startTime,
    this.endTime,
    this.startLocation,
    this.destination,
    this.sharpTurns = 0,
    this.riskyTurns = 0,
    this.averageSpeed = 0.0,
    this.totalDistance = 0.0,
    this.turnEvents = const [],
    this.sensorReadings = const [],
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'startLocation': startLocation,
      'destination': destination,
      'sharpTurns': sharpTurns,
      'riskyTurns': riskyTurns,
      'averageSpeed': averageSpeed,
      'totalDistance': totalDistance,
      'turnEvents': turnEvents.map((e) => e.toMap()).toList(),
      'sensorReadings': sensorReadings.map((e) => e.toMap()).toList(),
    };
  }
  
  factory JourneyData.fromMap(Map<String, dynamic> map, String id) {
    return JourneyData(
      id: id,
      startTime: DateTime.parse(map['startTime']),
      endTime: map['endTime'] != null ? DateTime.parse(map['endTime']) : null,
      startLocation: map['startLocation'],
      destination: map['destination'],
      sharpTurns: map['sharpTurns'] ?? 0,
      riskyTurns: map['riskyTurns'] ?? 0,
      averageSpeed: (map['averageSpeed'] ?? 0.0).toDouble(),
      totalDistance: (map['totalDistance'] ?? 0.0).toDouble(),
      turnEvents: (map['turnEvents'] as List?)
          ?.map((e) => TurnEvent.fromMap(e))
          .toList() ?? [],
      sensorReadings: (map['sensorReadings'] as List?)
          ?.map((e) => SensorReading.fromMap(e))
          .toList() ?? [],
    );
  }
}

class TurnEvent {
  final DateTime timestamp;
  final String severity; // "sharp" or "risky"
  final double turnRate;
  final double latitude;
  final double longitude;
  
  TurnEvent({
    required this.timestamp,
    required this.severity,
    required this.turnRate,
    required this.latitude,
    required this.longitude,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'severity': severity,
      'turnRate': turnRate,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
  
  factory TurnEvent.fromMap(Map<String, dynamic> map) {
    return TurnEvent(
      timestamp: DateTime.parse(map['timestamp']),
      severity: map['severity'],
      turnRate: (map['turnRate'] ?? 0.0).toDouble(),
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
    );
  }
}

class SensorReading {
  final DateTime timestamp;
  final int heartRate;
  final double temperature;
  final int stressLevel;
  
  SensorReading({
    required this.timestamp,
    required this.heartRate,
    required this.temperature,
    required this.stressLevel,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'heartRate': heartRate,
      'temperature': temperature,
      'stressLevel': stressLevel,
    };
  }
  
  factory SensorReading.fromMap(Map<String, dynamic> map) {
    return SensorReading(
      timestamp: DateTime.parse(map['timestamp']),
      heartRate: map['heartRate'] ?? 0,
      temperature: (map['temperature'] ?? 0.0).toDouble(),
      stressLevel: map['stressLevel'] ?? 0,
    );
  }
}