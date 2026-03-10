import 'package:cloud_firestore/cloud_firestore.dart';

class JourneyData {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final String? startLocation;
  final String? destination;
  final int sharpTurns;
  final int riskyTurns;
  final int totalBrakingEvents;
  final double averageSpeed;
  final double maxSpeed;
  final double maxTurnRate;
  final double totalDistance;
  final String? dangerPrediction; // ML Result
  final List<TurnEvent> turnEvents;
  final List<BrakingEvent> brakingEvents;
  final List<LeanEvent> leanEvents;
  final List<SensorReading> sensorReadings;
  final List<GpsPoint> gpsTrack;

  JourneyData({
    required this.id,
    required this.startTime,
    this.endTime,
    this.startLocation,
    this.destination,
    this.sharpTurns = 0,
    this.riskyTurns = 0,
    this.totalBrakingEvents = 0,
    this.averageSpeed = 0.0,
    this.maxSpeed = 0.0,
    this.maxTurnRate = 0.0,
    this.totalDistance = 0.0,
    this.dangerPrediction,
    this.turnEvents = const [],
    this.brakingEvents = const [],
    this.leanEvents = const [],
    this.sensorReadings = const [],
    this.gpsTrack = const [],
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
      'totalBrakingEvents': totalBrakingEvents,
      'averageSpeed': averageSpeed,
      'maxSpeed': maxSpeed,
      'maxTurnRate': maxTurnRate,
      'totalDistance': totalDistance,
      'dangerPrediction': dangerPrediction,
      'turnEvents': turnEvents.map((e) => e.toMap()).toList(),
      'brakingEvents': brakingEvents.map((e) => e.toMap()).toList(),
      'leanEvents': leanEvents.map((e) => e.toMap()).toList(),
      // 'sensorReadings' and 'gpsTrack' are explicitly removed to prevent
      // uploading thousands of normal datapoints to Firebase, saving bandwidth.
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
      totalBrakingEvents: map['totalBrakingEvents'] ?? 0,
      averageSpeed: (map['averageSpeed'] ?? 0.0).toDouble(),
      maxSpeed: (map['maxSpeed'] ?? 0.0).toDouble(),
      maxTurnRate: (map['maxTurnRate'] ?? 0.0).toDouble(),
      totalDistance: (map['totalDistance'] ?? 0.0).toDouble(),
      dangerPrediction: map['dangerPrediction'],
      turnEvents: (map['turnEvents'] as List?)
              ?.map((e) => TurnEvent.fromMap(e))
              .toList() ??
          [],
      brakingEvents: (map['brakingEvents'] as List?)
              ?.map((e) => BrakingEvent.fromMap(e))
              .toList() ??
          [],
      leanEvents: (map['leanEvents'] as List?)
              ?.map((e) => LeanEvent.fromMap(e))
              .toList() ??
          [],
      sensorReadings: (map['sensorReadings'] as List?)
              ?.map((e) => SensorReading.fromMap(e))
              .toList() ??
          [],
      gpsTrack: (map['gpsTrack'] as List?)
              ?.map((e) => GpsPoint.fromMap(e))
              .toList() ??
          [],
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

  // Danger prediction sensor extensions
  final double accelX;
  final double accelY;
  final double accelZ;
  final double gyroX;
  final double gyroY;
  final double gyroZ;

  SensorReading({
    required this.timestamp,
    required this.heartRate,
    required this.temperature,
    required this.stressLevel,
    this.accelX = 0.0,
    this.accelY = 0.0,
    this.accelZ = 0.0,
    this.gyroX = 0.0,
    this.gyroY = 0.0,
    this.gyroZ = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'heartRate': heartRate,
      'temperature': temperature,
      'stressLevel': stressLevel,
      'accelX': accelX,
      'accelY': accelY,
      'accelZ': accelZ,
      'gyroX': gyroX,
      'gyroY': gyroY,
      'gyroZ': gyroZ,
    };
  }

  factory SensorReading.fromMap(Map<String, dynamic> map) {
    return SensorReading(
      timestamp: DateTime.parse(map['timestamp']),
      heartRate: map['heartRate'] ?? 0,
      temperature: (map['temperature'] ?? 0.0).toDouble(),
      stressLevel: map['stressLevel'] ?? 0,
      accelX: (map['accelX'] ?? 0.0).toDouble(),
      accelY: (map['accelY'] ?? 0.0).toDouble(),
      accelZ: (map['accelZ'] ?? 0.0).toDouble(),
      gyroX: (map['gyroX'] ?? 0.0).toDouble(),
      gyroY: (map['gyroY'] ?? 0.0).toDouble(),
      gyroZ: (map['gyroZ'] ?? 0.0).toDouble(),
    );
  }
}

class GpsPoint {
  final double latitude;
  final double longitude;
  final DateTime? timestamp;
  final double speedKmh; // Speed at this GPS point

  GpsPoint({
    required this.latitude,
    required this.longitude,
    this.timestamp,
    this.speedKmh = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp?.toIso8601String(),
      'speedKmh': speedKmh,
    };
  }

  factory GpsPoint.fromMap(Map<String, dynamic> map) {
    return GpsPoint(
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      timestamp:
          map['timestamp'] != null ? DateTime.parse(map['timestamp']) : null,
      speedKmh: (map['speedKmh'] ?? 0.0).toDouble(),
    );
  }
}

/// A hard braking event detected during the ride
class BrakingEvent {
  final DateTime timestamp;
  final double deceleration; // in m/s² (negative = braking)
  final double latitude;
  final double longitude;
  final double speedBefore; // km/h before braking
  final String severity; // 'hard' or 'emergency'

  BrakingEvent({
    required this.timestamp,
    required this.deceleration,
    required this.latitude,
    required this.longitude,
    required this.speedBefore,
    required this.severity,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'deceleration': deceleration,
      'latitude': latitude,
      'longitude': longitude,
      'speedBefore': speedBefore,
      'severity': severity,
    };
  }

  factory BrakingEvent.fromMap(Map<String, dynamic> map) {
    return BrakingEvent(
      timestamp: DateTime.parse(map['timestamp']),
      deceleration: (map['deceleration'] ?? 0.0).toDouble(),
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      speedBefore: (map['speedBefore'] ?? 0.0).toDouble(),
      severity: map['severity'] ?? 'hard',
    );
  }
}

/// A dangerous lean angle event detected during the ride
class LeanEvent {
  final DateTime timestamp;
  final double leanAngle; // in degrees (positive = right, negative = left)
  final String severity; // 'risky' (35°-45°) or 'critical' (>45°)
  final double latitude;
  final double longitude;

  LeanEvent({
    required this.timestamp,
    required this.leanAngle,
    required this.severity,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'leanAngle': leanAngle,
      'severity': severity,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory LeanEvent.fromMap(Map<String, dynamic> map) {
    return LeanEvent(
      timestamp: DateTime.parse(map['timestamp']),
      leanAngle: (map['leanAngle'] ?? 0.0).toDouble(),
      severity: map['severity'] ?? 'risky',
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
    );
  }
}
