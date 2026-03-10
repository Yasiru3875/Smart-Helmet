import '../../../../models/journey_model.dart';

class DummyJourneyData {
  /// Generate a sample journey with realistic data for testing
  static JourneyData getSampleJourney() {
    final startTime = DateTime.now().subtract(const Duration(hours: 2));
    final endTime = startTime.add(const Duration(minutes: 45));

    return JourneyData(
      id: '1234567890',
      startTime: startTime,
      endTime: endTime,
      startLocation: 'Negombo Bus Stand',
      destination: 'Colombo Fort Railway Station',
      sharpTurns: 8,
      riskyTurns: 3,
      averageSpeed: 42.5,
      maxSpeed: 68.3,
      totalDistance: 28.7,
      turnEvents: _generateTurnEvents(startTime),
      gpsTrack: _generateGPSTrack(startTime),
      sensorReadings: _generateSensorReadings(startTime),
      leanEvents: _generateLeanEvents(startTime),
    );
  }

  /// Generate multiple sample journeys for history
  static List<JourneyData> getSampleJourneyHistory() {
    return [
      // Journey 1: High Risk
      JourneyData(
        id: '1001',
        startTime: DateTime.now().subtract(const Duration(days: 1)),
        endTime: DateTime.now().subtract(const Duration(days: 1)).add(const Duration(hours: 1)),
        startLocation: 'Galle Road, Colombo',
        destination: 'Mount Lavinia Beach',
        sharpTurns: 15,
        riskyTurns: 7,
        averageSpeed: 55.2,
        maxSpeed: 85.5,
        totalDistance: 18.5,
        turnEvents: _generateTurnEvents(DateTime.now().subtract(const Duration(days: 1))),
        gpsTrack: _generateGPSTrack(DateTime.now().subtract(const Duration(days: 1))),
        sensorReadings: _generateSensorReadings(DateTime.now().subtract(const Duration(days: 1))),
      ),

      // Journey 2: Safe Ride
      JourneyData(
        id: '1002',
        startTime: DateTime.now().subtract(const Duration(days: 2)),
        endTime: DateTime.now().subtract(const Duration(days: 2)).add(const Duration(hours: 3, minutes: 12)),
        startLocation: 'Colombo',
        destination: 'Kandy',
        sharpTurns: 5,
        riskyTurns: 1,
        averageSpeed: 35.8,
        maxSpeed: 52.0,
        totalDistance: 115.2,
        turnEvents: _generateSafeTurnEvents(DateTime.now().subtract(const Duration(days: 2))),
        gpsTrack: _generateLongGPSTrack(DateTime.now().subtract(const Duration(days: 2))),
        sensorReadings: _generateSensorReadings(DateTime.now().subtract(const Duration(days: 2))),
      ),

      // Journey 3: Moderate Risk
      JourneyData(
        id: '1003',
        startTime: DateTime.now().subtract(const Duration(days: 3)),
        endTime: DateTime.now().subtract(const Duration(days: 3)).add(const Duration(minutes: 32)),
        startLocation: 'Rajagiriya',
        destination: 'Kotte',
        sharpTurns: 10,
        riskyTurns: 3,
        averageSpeed: 38.5,
        maxSpeed: 62.8,
        totalDistance: 12.3,
        turnEvents: _generateModerateTurnEvents(DateTime.now().subtract(const Duration(days: 3))),
        gpsTrack: _generateShortGPSTrack(DateTime.now().subtract(const Duration(days: 3))),
        sensorReadings: _generateSensorReadings(DateTime.now().subtract(const Duration(days: 3))),
      ),

      // Journey 4: Main Test Journey
      getSampleJourney(),
    ];
  }

  /// Generate realistic turn events
  static List<TurnEvent> _generateTurnEvents(DateTime startTime) {
    return [
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 5)),
        severity: 'sharp',
        turnRate: 125.6,
        latitude: 7.2083,
        longitude: 79.8383,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 10)),
        severity: 'sharp',
        turnRate: 118.3,
        latitude: 7.2125,
        longitude: 79.8450,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 15)),
        severity: 'risky',
        turnRate: 167.3,
        latitude: 7.2210,
        longitude: 79.8520,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 22)),
        severity: 'sharp',
        turnRate: 132.5,
        latitude: 7.2275,
        longitude: 79.8590,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 28)),
        severity: 'sharp',
        turnRate: 128.7,
        latitude: 7.2350,
        longitude: 79.8660,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 32)),
        severity: 'risky',
        turnRate: 178.5,
        latitude: 7.2425,
        longitude: 79.8730,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 36)),
        severity: 'sharp',
        turnRate: 122.8,
        latitude: 7.2500,
        longitude: 79.8800,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 40)),
        severity: 'risky',
        turnRate: 172.3,
        latitude: 7.2575,
        longitude: 79.8870,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 42)),
        severity: 'sharp',
        turnRate: 130.5,
        latitude: 7.2650,
        longitude: 79.8940,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 44)),
        severity: 'sharp',
        turnRate: 126.3,
        latitude: 7.2725,
        longitude: 79.9010,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 45)),
        severity: 'sharp',
        turnRate: 120.5,
        latitude: 7.2800,
        longitude: 79.9080,
      ),
    ];
  }

  /// Generate GPS track with points every 10 seconds
  static List<GpsPoint> _generateGPSTrack(DateTime startTime) {
    List<GpsPoint> track = [];
    
    // Starting point (Negombo area)
    double lat = 7.2083;
    double lon = 79.8383;
    
    // Generate points for 45-minute journey (270 points, one every 10 seconds)
    for (int i = 0; i < 270; i++) {
      // Simulate movement (roughly southeast direction)
      lat += 0.0003;
      lon += 0.00025;
      
      // Add some variation to make route realistic
      if (i % 20 == 0) {
        lat += (i % 2 == 0 ? 0.0002 : -0.0002);
        lon += (i % 3 == 0 ? 0.0003 : -0.0001);
      }
      
      track.add(GpsPoint(
        timestamp: startTime.add(Duration(seconds: i * 10)),
        latitude: lat,
        longitude: lon,
      ));
    }
    
    return track;
  }

  /// Generate sensor readings throughout journey
  static List<SensorReading> _generateSensorReadings(DateTime startTime) {
    List<SensorReading> readings = [];
    
    for (int i = 0; i < 45; i++) {
      readings.add(SensorReading(
        timestamp: startTime.add(Duration(minutes: i)),
        heartRate: 72 + (i % 15),
        temperature: 36.5 + (i % 10) * 0.1,
        stressLevel: 20 + (i % 30),
      ));
    }
    
    return readings;
  }

  // Generate safe turn events (fewer risky turns)
  static List<TurnEvent> _generateSafeTurnEvents(DateTime startTime) {
    return [
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 15)),
        severity: 'sharp',
        turnRate: 108.5,
        latitude: 7.2100,
        longitude: 79.8400,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 45)),
        severity: 'sharp',
        turnRate: 112.3,
        latitude: 7.2500,
        longitude: 79.8800,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 90)),
        severity: 'risky',
        turnRate: 158.5,
        latitude: 7.2900,
        longitude: 80.6350,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 120)),
        severity: 'sharp',
        turnRate: 115.8,
        latitude: 7.2905,
        longitude: 80.6355,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 150)),
        severity: 'sharp',
        turnRate: 110.5,
        latitude: 7.2908,
        longitude: 80.6358,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 180)),
        severity: 'sharp',
        turnRate: 118.3,
        latitude: 7.2910,
        longitude: 80.6360,
      ),
    ];
  }

  // Generate moderate turn events
  static List<TurnEvent> _generateModerateTurnEvents(DateTime startTime) {
    return [
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 3)),
        severity: 'sharp',
        turnRate: 122.5,
        latitude: 6.9147,
        longitude: 79.9729,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 8)),
        severity: 'risky',
        turnRate: 165.8,
        latitude: 6.9200,
        longitude: 79.9800,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 12)),
        severity: 'sharp',
        turnRate: 128.3,
        latitude: 6.9250,
        longitude: 79.9850,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 16)),
        severity: 'sharp',
        turnRate: 132.5,
        latitude: 6.9300,
        longitude: 79.9900,
      ),
      TurnEvent(
        timestamp: startTime.add(const Duration(minutes: 20)),
        severity: 'risky',
        turnRate: 172.8,
        latitude: 6.9350,
        longitude: 79.9950,
      ),
    ];
  }

  // Generate long GPS track (for Colombo to Kandy)
  static List<GpsPoint> _generateLongGPSTrack(DateTime startTime) {
    List<GpsPoint> track = [];
    double lat = 6.9271; // Colombo
    double lon = 79.8612;
    
    // 3.2 hours = 1152 points (one every 10 seconds)
    for (int i = 0; i < 1152; i++) {
      lat += 0.0002;
      lon += 0.00015;
      
      track.add(GpsPoint(
        timestamp: startTime.add(Duration(seconds: i * 10)),
        latitude: lat,
        longitude: lon,
      ));
    }
    
    return track;
  }

  // Generate short GPS track
  static List<GpsPoint> _generateShortGPSTrack(DateTime startTime) {
    List<GpsPoint> track = [];
    double lat = 6.9147;
    double lon = 79.9729;
    
    // 32 minutes = 192 points
    for (int i = 0; i < 192; i++) {
      lat += 0.0002;
      lon += 0.00018;
      
      track.add(GpsPoint(
        timestamp: startTime.add(Duration(seconds: i * 10)),
        latitude: lat,
        longitude: lon,
      ));
    }
    
    return track;
  }

  /// Generate sample lean events for testing
  static List<LeanEvent> _generateLeanEvents(DateTime startTime) {
    return [
      LeanEvent(
        timestamp: startTime.add(const Duration(minutes: 12)),
        leanAngle: 38.5,
        severity: 'risky',
        latitude: 7.2180,
        longitude: 79.8480,
      ),
      LeanEvent(
        timestamp: startTime.add(const Duration(minutes: 25)),
        leanAngle: -47.2,
        severity: 'critical',
        latitude: 7.2350,
        longitude: 79.8660,
      ),
      LeanEvent(
        timestamp: startTime.add(const Duration(minutes: 38)),
        leanAngle: 42.1,
        severity: 'risky',
        latitude: 7.2530,
        longitude: 79.8830,
      ),
    ];
  }
}
