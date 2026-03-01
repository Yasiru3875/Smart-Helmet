// ============================================================
// journey_model.dart - Complete data models for Post-Journey
// ============================================================

class JourneyData {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final String? startLocation;
  final String? destination;

  // IMU-derived metrics
  final int sharpTurns;
  final int riskyTurns;
  final int suddenBrakes;
  final double averageSpeed;
  final double maxSpeed;
  final double totalDistance;

  // EEG-derived metrics
  final double averageStressLevel;
  final int stressPeakCount;
  final double maxStressLevel;

  // Overall risk score (0-100)
  final double riskScore;

  // Events
  final List<TurnEvent> turnEvents;
  final List<BrakeEvent> brakeEvents;
  final List<StressPeakEvent> stressPeaks;
  final List<CriticalEvent> criticalEvents;
  final List<SensorReading> sensorReadings;
  final List<GpsPoint> gpsTrack;

  // Context
  final WeatherContext? weatherContext;
  final String? trafficCondition;

  // Recommendations
  final List<String> recommendations;

  JourneyData({
    required this.id,
    required this.startTime,
    this.endTime,
    this.startLocation,
    this.destination,
    this.sharpTurns = 0,
    this.riskyTurns = 0,
    this.suddenBrakes = 0,
    this.averageSpeed = 0.0,
    this.maxSpeed = 0.0,
    this.totalDistance = 0.0,
    this.averageStressLevel = 0.0,
    this.stressPeakCount = 0,
    this.maxStressLevel = 0.0,
    this.riskScore = 75.0,
    this.turnEvents = const [],
    this.brakeEvents = const [],
    this.stressPeaks = const [],
    this.criticalEvents = const [],
    this.sensorReadings = const [],
    this.gpsTrack = const [],
    this.weatherContext,
    this.trafficCondition,
    this.recommendations = const [],
  });

  // Computed properties
  Duration get duration => endTime != null 
      ? endTime!.difference(startTime) 
      : Duration.zero;

  String get riskLabel {
    if (riskScore >= 80) return 'Safe';
    if (riskScore >= 60) return 'Moderate';
    if (riskScore >= 40) return 'Caution';
    return 'High Risk';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'startLocation': startLocation,
      'destination': destination,
      'sharpTurns': sharpTurns,
      'riskyTurns': riskyTurns,
      'suddenBrakes': suddenBrakes,
      'averageSpeed': averageSpeed,
      'maxSpeed': maxSpeed,
      'totalDistance': totalDistance,
      'averageStressLevel': averageStressLevel,
      'stressPeakCount': stressPeakCount,
      'maxStressLevel': maxStressLevel,
      'riskScore': riskScore,
      'turnEvents': turnEvents.map((e) => e.toMap()).toList(),
      'brakeEvents': brakeEvents.map((e) => e.toMap()).toList(),
      'stressPeaks': stressPeaks.map((e) => e.toMap()).toList(),
      'criticalEvents': criticalEvents.map((e) => e.toMap()).toList(),
      'sensorReadings': sensorReadings.map((e) => e.toMap()).toList(),
      'gpsTrack': gpsTrack.map((e) => e.toMap()).toList(),
      'weatherContext': weatherContext?.toMap(),
      'trafficCondition': trafficCondition,
      'recommendations': recommendations,
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
      suddenBrakes: map['suddenBrakes'] ?? 0,
      averageSpeed: (map['averageSpeed'] ?? 0.0).toDouble(),
      maxSpeed: (map['maxSpeed'] ?? 0.0).toDouble(),
      totalDistance: (map['totalDistance'] ?? 0.0).toDouble(),
      averageStressLevel: (map['averageStressLevel'] ?? 0.0).toDouble(),
      stressPeakCount: map['stressPeakCount'] ?? 0,
      maxStressLevel: (map['maxStressLevel'] ?? 0.0).toDouble(),
      riskScore: (map['riskScore'] ?? 75.0).toDouble(),
      turnEvents: (map['turnEvents'] as List?)
          ?.map((e) => TurnEvent.fromMap(e))
          .toList() ?? [],
      brakeEvents: (map['brakeEvents'] as List?)
          ?.map((e) => BrakeEvent.fromMap(e))
          .toList() ?? [],
      stressPeaks: (map['stressPeaks'] as List?)
          ?.map((e) => StressPeakEvent.fromMap(e))
          .toList() ?? [],
      criticalEvents: (map['criticalEvents'] as List?)
          ?.map((e) => CriticalEvent.fromMap(e))
          .toList() ?? [],
      sensorReadings: (map['sensorReadings'] as List?)
          ?.map((e) => SensorReading.fromMap(e))
          .toList() ?? [],
      gpsTrack: (map['gpsTrack'] as List?)
          ?.map((e) => GpsPoint.fromMap(e))
          .toList() ?? [],
      weatherContext: map['weatherContext'] != null
          ? WeatherContext.fromMap(map['weatherContext'])
          : null,
      trafficCondition: map['trafficCondition'],
      recommendations: List<String>.from(map['recommendations'] ?? []),
    );
  }
}

// ============================================================
// TurnEvent - Gyroscope detected turn
// ============================================================
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
      severity: map['severity'] ?? 'sharp',
      turnRate: (map['turnRate'] ?? 0.0).toDouble(),
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
    );
  }
}

// ============================================================
// BrakeEvent - Accelerometer detected sudden braking
// ============================================================
class BrakeEvent {
  final DateTime timestamp;
  final double deceleration; // m/s²
  final String severity; // 'moderate' | 'harsh'
  final double latitude;
  final double longitude;

  BrakeEvent({
    required this.timestamp,
    required this.deceleration,
    required this.severity,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'deceleration': deceleration,
    'severity': severity,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory BrakeEvent.fromMap(Map<String, dynamic> m) => BrakeEvent(
    timestamp: DateTime.parse(m['timestamp']),
    deceleration: (m['deceleration'] ?? 0.0).toDouble(),
    severity: m['severity'] ?? 'moderate',
    latitude: (m['latitude'] ?? 0.0).toDouble(),
    longitude: (m['longitude'] ?? 0.0).toDouble(),
  );
}

// ============================================================
// StressPeakEvent - EEG-based stress spike
// ============================================================
class StressPeakEvent {
  final DateTime timestamp;
  final int stressLevel; // 0-100
  final double latitude;
  final double longitude;

  StressPeakEvent({
    required this.timestamp,
    required this.stressLevel,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'stressLevel': stressLevel,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory StressPeakEvent.fromMap(Map<String, dynamic> m) => StressPeakEvent(
    timestamp: DateTime.parse(m['timestamp']),
    stressLevel: m['stressLevel'] ?? 0,
    latitude: (m['latitude'] ?? 0.0).toDouble(),
    longitude: (m['longitude'] ?? 0.0).toDouble(),
  );
}

// ============================================================
// CriticalEvent - Correlated multi-factor danger moment
// ============================================================
class CriticalEvent {
  final DateTime timestamp;
  final List<String> factors; // e.g. ['high_speed', 'stress_peak', 'rain']
  final int severity; // 1=moderate, 2=high, 3=critical
  final String description;
  final double latitude;
  final double longitude;

  CriticalEvent({
    required this.timestamp,
    required this.factors,
    required this.severity,
    required this.description,
    required this.latitude,
    required this.longitude,
  });

  String get severityLabel {
    if (severity >= 3) return 'Critical';
    if (severity == 2) return 'High';
    return 'Moderate';
  }

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'factors': factors,
    'severity': severity,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory CriticalEvent.fromMap(Map<String, dynamic> m) => CriticalEvent(
    timestamp: DateTime.parse(m['timestamp']),
    factors: List<String>.from(m['factors'] ?? []),
    severity: m['severity'] ?? 1,
    description: m['description'] ?? '',
    latitude: (m['latitude'] ?? 0.0).toDouble(),
    longitude: (m['longitude'] ?? 0.0).toDouble(),
  );
}

// ============================================================
// SensorReading - Heart rate, temperature, stress
// ============================================================
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

// ============================================================
// GpsPoint - GPS location with speed and heading
// ============================================================
class GpsPoint {
  final double latitude;
  final double longitude;
  final DateTime? timestamp;
  final double speed; // km/h
  final double heading; // degrees 0-360

  GpsPoint({
    required this.latitude,
    required this.longitude,
    this.timestamp,
    this.speed = 0.0,
    this.heading = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp?.toIso8601String(),
      'speed': speed,
      'heading': heading,
    };
  }

  factory GpsPoint.fromMap(Map<String, dynamic> map) {
    return GpsPoint(
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      timestamp: map['timestamp'] != null ? DateTime.parse(map['timestamp']) : null,
      speed: (map['speed'] ?? 0.0).toDouble(),
      heading: (map['heading'] ?? 0.0).toDouble(),
    );
  }
}

// ============================================================
// WeatherContext - Weather conditions during ride
// ============================================================
class WeatherContext {
  final String condition; // e.g. 'Rain', 'Clear', 'Cloudy'
  final String description;
  final double temperature; // °C
  final double humidity; // %
  final double windSpeed; // km/h
  final double visibility; // km
  final String icon;

  WeatherContext({
    required this.condition,
    required this.description,
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.visibility,
    this.icon = '',
  });

  bool get isAdverseWeather =>
      condition.toLowerCase().contains('rain') ||
      condition.toLowerCase().contains('storm') ||
      condition.toLowerCase().contains('fog') ||
      visibility < 5.0;

  Map<String, dynamic> toMap() => {
    'condition': condition,
    'description': description,
    'temperature': temperature,
    'humidity': humidity,
    'windSpeed': windSpeed,
    'visibility': visibility,
    'icon': icon,
  };

  factory WeatherContext.fromMap(Map<String, dynamic> m) => WeatherContext(
    condition: m['condition'] ?? 'Unknown',
    description: m['description'] ?? '',
    temperature: (m['temperature'] ?? 0.0).toDouble(),
    humidity: (m['humidity'] ?? 0.0).toDouble(),
    windSpeed: (m['windSpeed'] ?? 0.0).toDouble(),
    visibility: (m['visibility'] ?? 10.0).toDouble(),
    icon: m['icon'] ?? '',
  );

  factory WeatherContext.dummy() => WeatherContext(
    condition: 'Clear',
    description: 'clear sky',
    temperature: 29.5,
    humidity: 78,
    windSpeed: 12,
    visibility: 10,
    icon: '01d',
  );
}