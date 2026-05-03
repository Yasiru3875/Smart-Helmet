// ============================================================
// dummy_journey_data.dart  – IT22608086 Post-Journey Component
// Realistic sample data: Kaduwela → Malabe, Sri Lanka
// All events (turns, brakes, stress peaks, critical) are
// tagged with REAL GPS coordinates along the actual route.
//
// Route: Kaduwela Town → Malabe (A1 → Kaduwela Rd → Malabe Rd)
// Duration: ~35 min, Distance: ~12.5 km
//
// Danger zones placed at recognisable road points:
//  - Kaduwela Junction sharp left turn
//  - Orugodawatte bridge risky overtake
//  - Hospital junction sudden brake
//  - Malabe roundabout stress peak
//  - Multiple critical events at complex junctions
// ============================================================

import '../../../../models/journey_model.dart';

class DummyJourneyData {
  // ─────────────────────────────────────────────────────────
  // PRIMARY SAMPLE: Kaduwela → Malabe
  // ─────────────────────────────────────────────────────────
  static JourneyData getSampleJourney() {
    final start = DateTime(2025, 3, 15, 8, 12, 0);
    final end = start.add(const Duration(minutes: 35));

    // ── GPS Track: 70 points, Kaduwela → Malabe ──────────
    final gps = _buildGpsTrack(start);

    // ── Turn Events (with real coordinates) ──────────────
    final turns = <TurnEvent>[
      // Risky turn: Kaduwela main junction (sharp left off A1)
      TurnEvent(
        timestamp: start.add(const Duration(minutes: 3, seconds: 20)),
        severity: 'risky',
        turnRate: 162.4,
        latitude: 6.9337,
        longitude: 79.9175,
      ),
      // Sharp turn: bend before Welikade prison
      TurnEvent(
        timestamp: start.add(const Duration(minutes: 6, seconds: 45)),
        severity: 'sharp',
        turnRate: 118.2,
        latitude: 6.9298,
        longitude: 79.9221,
      ),
      // Sharp turn: Orugodawatte flyover approach curve
      TurnEvent(
        timestamp: start.add(const Duration(minutes: 9, seconds: 10)),
        severity: 'sharp',
        turnRate: 112.7,
        latitude: 6.9271,
        longitude: 79.9264,
      ),
      // Risky turn: Battaramulla junction — tight right
      TurnEvent(
        timestamp: start.add(const Duration(minutes: 15, seconds: 30)),
        severity: 'risky',
        turnRate: 171.8,
        latitude: 6.9143,
        longitude: 79.9302,
      ),
      // Sharp turn: Koswatta Rd bend
      TurnEvent(
        timestamp: start.add(const Duration(minutes: 19, seconds: 55)),
        severity: 'sharp',
        turnRate: 105.3,
        latitude: 6.9096,
        longitude: 79.9346,
      ),
      // Risky turn: Sri Jayawardenepura roundabout exit
      TurnEvent(
        timestamp: start.add(const Duration(minutes: 23, seconds: 40)),
        severity: 'risky',
        turnRate: 155.1,
        latitude: 6.9065,
        longitude: 79.9383,
      ),
      // Sharp turn: Malabe Rd narrow S-bend
      TurnEvent(
        timestamp: start.add(const Duration(minutes: 28, seconds: 20)),
        severity: 'sharp',
        turnRate: 124.6,
        latitude: 6.9022,
        longitude: 79.9432,
      ),
      // Sharp turn: final approach to Malabe town
      TurnEvent(
        timestamp: start.add(const Duration(minutes: 32, seconds: 5)),
        severity: 'sharp',
        turnRate: 109.8,
        latitude: 6.8993,
        longitude: 79.9471,
      ),
    ];

    // ── Brake Events (with real coordinates) ─────────────
    final brakes = <BrakeEvent>[
      // Harsh brake: pedestrian crossing near Welikade
      BrakeEvent(
        timestamp: start.add(const Duration(minutes: 5, seconds: 50)),
        severity: 'harsh',
        deceleration: 15.3,
        latitude: 6.9305,
        longitude: 79.9210,
      ),
      // Moderate brake: traffic buildup Orugodawatte
      BrakeEvent(
        timestamp: start.add(const Duration(minutes: 10, seconds: 30)),
        severity: 'moderate',
        deceleration: 9.7,
        latitude: 6.9258,
        longitude: 79.9272,
      ),
      // Harsh brake: sudden stop at Battaramulla Hospital junction
      BrakeEvent(
        timestamp: start.add(const Duration(minutes: 14, seconds: 20)),
        severity: 'harsh',
        deceleration: 16.8,
        latitude: 6.9161,
        longitude: 79.9289,
      ),
      // Moderate brake: speed bump near IIT Campus
      BrakeEvent(
        timestamp: start.add(const Duration(minutes: 22, seconds: 10)),
        severity: 'moderate',
        deceleration: 10.2,
        latitude: 6.9076,
        longitude: 79.9365,
      ),
      // Harsh brake: emergency stop near Malabe flyover
      BrakeEvent(
        timestamp: start.add(const Duration(minutes: 30, seconds: 40)),
        severity: 'harsh',
        deceleration: 14.9,
        latitude: 6.9008,
        longitude: 79.9452,
      ),
    ];

    // ── Stress Peaks (EEG — with real coordinates) ───────
    final stressPeaks = <StressPeakEvent>[
      // Peak at Kaduwela congested junction
      StressPeakEvent(
        timestamp: start.add(const Duration(minutes: 4, seconds: 10)),
        stressLevel: 72,
        latitude: 6.9320,
        longitude: 79.9192,
      ),
      // Peak at Battaramulla Hospital junction
      StressPeakEvent(
        timestamp: start.add(const Duration(minutes: 14, seconds: 35)),
        stressLevel: 81,
        latitude: 6.9158,
        longitude: 79.9291,
      ),
      // Peak during complex overtake near Sri Jayawardenepura
      StressPeakEvent(
        timestamp: start.add(const Duration(minutes: 24, seconds: 5)),
        stressLevel: 76,
        latitude: 6.9060,
        longitude: 79.9387,
      ),
    ];

    // ── Critical Events (multi-factor, GPS-tagged) ───────
    final criticals = <CriticalEvent>[
      // Critical: Battaramulla Hospital — risky turn + harsh brake + stress peak
      CriticalEvent(
        timestamp: start.add(const Duration(minutes: 14, seconds: 45)),
        factors: ['risky_turn', 'harsh_braking', 'stress_peak'],
        severity: 3,
        description: 'High-stress sudden stop at Battaramulla Hospital junction',
        latitude: 6.9155,
        longitude: 79.9293,
      ),
      // High: Kaduwela junction — risky turn + stress peak
      CriticalEvent(
        timestamp: start.add(const Duration(minutes: 3, seconds: 30)),
        factors: ['risky_turn', 'stress_peak', 'sudden_braking'],
        severity: 2,
        description: 'Congested overtaking at Kaduwela main junction',
        latitude: 6.9333,
        longitude: 79.9178,
      ),
      // Moderate: Sri Jayawardenepura — risky turn + speed
      CriticalEvent(
        timestamp: start.add(const Duration(minutes: 23, seconds: 50)),
        factors: ['risky_turn', 'overspeed'],
        severity: 2,
        description: 'Excessive speed through roundabout exit',
        latitude: 6.9062,
        longitude: 79.9386,
      ),
      // Moderate: Welikade crossroads — harsh brake + sharp turn
      CriticalEvent(
        timestamp: start.add(const Duration(minutes: 5, seconds: 55)),
        factors: ['harsh_braking', 'sharp_turn'],
        severity: 1,
        description: 'Sudden braking while turning near Welikade',
        latitude: 6.9303,
        longitude: 79.9212,
      ),
    ];

    // ── Sensor readings (45 readings, 35 min) ────────────
    final sensors = _buildSensorReadings(start, 35);

    return JourneyData(
      id: 'sample_kaduwela_malabe_001',
      startTime: start,
      endTime: end,
      startLocation: 'Kaduwela Town',
      destination: 'Malabe',
      sharpTurns: turns.where((t) => t.severity == 'sharp').length,
      riskyTurns: turns.where((t) => t.severity == 'risky').length,
      totalBrakingEvents: brakes.length,
      averageSpeed: 38.4,
      maxSpeed: 67.2,
      totalDistance: 12.48,
      turnEvents: turns,
      brakingEvents: brakes,
      sensorReadings: sensors,
      gpsTrack: gps,
    );
  }

  // ─────────────────────────────────────────────────────────
  // Build GPS track: Kaduwela → Malabe (real coordinates)
  // ─────────────────────────────────────────────────────────
  static List<GpsPoint> _buildGpsTrack(DateTime start) {
    // Waypoints along the actual Kaduwela → Malabe road
    final waypoints = <List<double>>[
      [6.9352, 79.9160], // 0: Kaduwela start
      [6.9345, 79.9162],
      [6.9337, 79.9168], // Kaduwela junction (risky turn)
      [6.9330, 79.9175],
      [6.9322, 79.9183],
      [6.9315, 79.9190],
      [6.9307, 79.9198],
      [6.9299, 79.9208], // Welikade area
      [6.9292, 79.9218],
      [6.9285, 79.9228],
      [6.9278, 79.9238],
      [6.9271, 79.9248], // Orugodawatte flyover
      [6.9264, 79.9258],
      [6.9258, 79.9268],
      [6.9251, 79.9275],
      [6.9245, 79.9282],
      [6.9238, 79.9288],
      [6.9231, 79.9293],
      [6.9224, 79.9295],
      [6.9217, 79.9296],
      [6.9209, 79.9295],
      [6.9200, 79.9292],
      [6.9191, 79.9291],
      [6.9181, 79.9290], // Battaramulla area
      [6.9171, 79.9291],
      [6.9162, 79.9292], // Hospital junction (critical)
      [6.9153, 79.9294],
      [6.9144, 79.9298], // Battaramulla junction (risky turn)
      [6.9136, 79.9303],
      [6.9128, 79.9310],
      [6.9120, 79.9318],
      [6.9112, 79.9326],
      [6.9104, 79.9333],
      [6.9097, 79.9341],
      [6.9090, 79.9349],
      [6.9083, 79.9357],
      [6.9076, 79.9365], // IIT Campus speed bump
      [6.9070, 79.9372],
      [6.9064, 79.9380],
      [6.9058, 79.9387], // Sri Jayawardenepura roundabout
      [6.9053, 79.9393],
      [6.9047, 79.9399],
      [6.9042, 79.9406],
      [6.9036, 79.9413],
      [6.9030, 79.9420],
      [6.9024, 79.9427],
      [6.9018, 79.9434],
      [6.9012, 79.9441],
      [6.9007, 79.9447],
      [6.9002, 79.9453], // Malabe flyover
      [6.8997, 79.9458],
      [6.8993, 79.9463],
      [6.8989, 79.9467],
      [6.8985, 79.9470],
      [6.8982, 79.9472],
      [6.8979, 79.9474],
      [6.8976, 79.9476],
      [6.8974, 79.9478],
      [6.8972, 79.9480],
      [6.8970, 79.9482], // Malabe town end
    ];

    // Build GpsPoint list with realistic speeds
    final speeds = <double>[
      25, 32, 28, 35, 42, 48, 52, 45, 38, 55,
      62, 58, 48, 42, 38, 44, 50, 55, 60, 65,
      67, 58, 42, 35, 30, 25, 32, 38, 45, 52,
      58, 60, 55, 50, 48, 52, 40, 38, 44, 50,
      48, 55, 60, 62, 58, 52, 48, 45, 42, 38,
      32, 30, 28, 25, 22, 20, 18, 16, 14, 12,
    ];

    return List.generate(waypoints.length, (i) {
      final secs = (i * 35.0 * 60 / waypoints.length).round();
      return GpsPoint(
        latitude: waypoints[i][0],
        longitude: waypoints[i][1],
        timestamp: start.add(Duration(seconds: secs)),
        speed: i < speeds.length ? speeds[i] : 30,
      );
    });
  }

  // ─────────────────────────────────────────────────────────
  // Build sensor readings (EEG stress profile)
  // Stress rises at junctions, peaks at critical events
  // ─────────────────────────────────────────────────────────
  static List<SensorReading> _buildSensorReadings(DateTime start, int minutes) {
    final readings = <SensorReading>[];
    // Stress profile: rises at 3min, 14min, 23min (danger zones)
    const stressProfile = [
      22, 28, 35, 55, 68, 58, 42, 38, 35, 32,  // 0-9 min
      30, 35, 42, 50, 72, 78, 65, 52, 44, 38,  // 10-19 min
      34, 30, 38, 56, 74, 62, 48, 40, 36, 32,  // 20-29 min
      35, 38, 32, 28, 25,                        // 30-34 min
    ];

    for (int i = 0; i < minutes; i++) {
      readings.add(SensorReading(
        timestamp: start.add(Duration(minutes: i, seconds: 15)),
        heartRate: 72 + (stressProfile[i] / 5).round() + (i % 3),
        temperature: 36.6 + (i % 4) * 0.05,
        stressLevel: stressProfile[i],
      ));
    }
    return readings;
  }

  // ─────────────────────────────────────────────────────────
  // Additional sample journeys for history list
  // ─────────────────────────────────────────────────────────
  static List<JourneyData> getSampleJourneyHistory() {
    return [
      getSampleJourney(),
      _colomboToNugegodaSafe(),
      _kiribathgodaToGampahaModeratRisk(),
      _colomboToKaduwelaHighRisk(),
    ];
  }

  /// Safe ride: Colombo Fort → Nugegoda (low traffic, dry weather)
  static JourneyData _colomboToNugegodaSafe() {
    final start = DateTime(2025, 3, 14, 16, 30, 0);
    return JourneyData(
      id: 'sample_colombo_nugegoda_002',
      startTime: start,
      endTime: start.add(const Duration(minutes: 28)),
      startLocation: 'Colombo Fort',
      destination: 'Nugegoda',
      sharpTurns: 2,
      riskyTurns: 0,
      suddenBrakes: 1,
      averageSpeed: 44.2,
      maxSpeed: 62.1,
      totalDistance: 11.2,
      averageStressLevel: 24.5,
      stressPeakCount: 0,
      maxStressLevel: 35.0,
      riskScore: 86.0,
      turnEvents: [
        TurnEvent(timestamp: start.add(const Duration(minutes: 8)), severity: 'sharp', turnRate: 108.0, latitude: 6.9054, longitude: 79.8716),
        TurnEvent(timestamp: start.add(const Duration(minutes: 19)), severity: 'sharp', turnRate: 103.2, latitude: 6.8756, longitude: 79.8821),
      ],
      brakeEvents: [
        BrakeEvent(timestamp: start.add(const Duration(minutes: 14)), severity: 'moderate', deceleration: 9.1, latitude: 6.8908, longitude: 79.8769),
      ],
      stressPeaks: [],
      criticalEvents: [],
      sensorReadings: List.generate(28, (i) => SensorReading(
        timestamp: start.add(Duration(minutes: i)),
        heartRate: 68 + (i % 4),
        temperature: 36.6,
        stressLevel: 20 + (i % 6) * 2,
      )),
      gpsTrack: _simpleTrack(6.9345, 79.8428, 6.8756, 79.8888, start, 28),
      weatherContext: WeatherContext(
        condition: 'Clear', description: 'clear sky',
        temperature: 31.2, humidity: 68.0, windSpeed: 10.5, visibility: 12.0, icon: '01d',
      ),
      recommendations: ['Excellent ride! Maintain your smooth braking technique.'],
    );
  }

  /// Moderate risk: Kiribathgoda → Gampaha
  static JourneyData _kiribathgodaToGampahaModeratRisk() {
    final start = DateTime(2025, 3, 12, 9, 0, 0);
    return JourneyData(
      id: 'sample_kiribathgoda_gampaha_003',
      startTime: start,
      endTime: start.add(const Duration(minutes: 42)),
      startLocation: 'Kiribathgoda',
      destination: 'Gampaha',
      sharpTurns: 6,
      riskyTurns: 2,
      suddenBrakes: 4,
      averageSpeed: 48.0,
      maxSpeed: 72.3,
      totalDistance: 22.6,
      averageStressLevel: 38.4,
      stressPeakCount: 2,
      maxStressLevel: 68.0,
      riskScore: 57.0,
      turnEvents: [
        TurnEvent(timestamp: start.add(const Duration(minutes: 6)), severity: 'risky', turnRate: 158.0, latitude: 7.0024, longitude: 79.9945),
        TurnEvent(timestamp: start.add(const Duration(minutes: 14)), severity: 'sharp', turnRate: 115.5, latitude: 7.0218, longitude: 80.0124),
        TurnEvent(timestamp: start.add(const Duration(minutes: 21)), severity: 'risky', turnRate: 163.7, latitude: 7.0452, longitude: 80.0231),
        TurnEvent(timestamp: start.add(const Duration(minutes: 30)), severity: 'sharp', turnRate: 107.2, latitude: 7.0634, longitude: 80.0312),
      ],
      brakeEvents: [
        BrakeEvent(timestamp: start.add(const Duration(minutes: 9)), severity: 'harsh', deceleration: 14.2, latitude: 7.0087, longitude: 79.9989),
        BrakeEvent(timestamp: start.add(const Duration(minutes: 22)), severity: 'moderate', deceleration: 10.8, latitude: 7.0468, longitude: 80.0242),
        BrakeEvent(timestamp: start.add(const Duration(minutes: 35)), severity: 'harsh', deceleration: 15.1, latitude: 7.0712, longitude: 80.0387),
      ],
      stressPeaks: [
        StressPeakEvent(timestamp: start.add(const Duration(minutes: 7)), stressLevel: 68, latitude: 7.0031, longitude: 79.9958),
        StressPeakEvent(timestamp: start.add(const Duration(minutes: 22)), stressLevel: 66, latitude: 7.0461, longitude: 80.0245),
      ],
      criticalEvents: [
        CriticalEvent(timestamp: start.add(const Duration(minutes: 7)), factors: ['risky_turn', 'stress_peak'], severity: 2, description: 'Risky turn under stress at Kiribathgoda exit', latitude: 7.0027, longitude: 79.9952),
      ],
      sensorReadings: List.generate(42, (i) => SensorReading(
        timestamp: start.add(Duration(minutes: i)),
        heartRate: 75 + (i % 5),
        temperature: 36.7,
        stressLevel: 30 + (i % 10) * 4,
      )),
      gpsTrack: _simpleTrack(7.0024, 79.9901, 7.0823, 80.0441, start, 42),
      weatherContext: WeatherContext(
        condition: 'Clouds', description: 'overcast clouds',
        temperature: 28.4, humidity: 78.0, windSpeed: 12.0, visibility: 9.5, icon: '04d',
      ),
      recommendations: [
        'Reduce speed before the Kiribathgoda junction exit — two risky turns detected in that zone.',
        '4 sudden braking events suggest too-close following distance. Keep 2-second gap.',
      ],
    );
  }

  /// High risk: Colombo → Kaduwela (rush hour, wet)
  static JourneyData _colomboToKaduwelaHighRisk() {
    final start = DateTime(2025, 3, 11, 17, 45, 0);
    return JourneyData(
      id: 'sample_colombo_kaduwela_004',
      startTime: start,
      endTime: start.add(const Duration(minutes: 58)),
      startLocation: 'Colombo Pettah',
      destination: 'Kaduwela',
      sharpTurns: 9,
      riskyTurns: 6,
      suddenBrakes: 8,
      averageSpeed: 22.8,
      maxSpeed: 71.5,
      totalDistance: 15.4,
      averageStressLevel: 62.3,
      stressPeakCount: 5,
      maxStressLevel: 88.0,
      riskScore: 29.0,
      turnEvents: List.generate(6, (i) => TurnEvent(
        timestamp: start.add(Duration(minutes: 5 + i * 8)),
        severity: 'risky',
        turnRate: 155.0 + i * 4.5,
        latitude: 6.9228 + i * 0.0012,
        longitude: 79.8610 + i * 0.0085,
      )) + List.generate(9, (i) => TurnEvent(
        timestamp: start.add(Duration(minutes: 7 + i * 5)),
        severity: 'sharp',
        turnRate: 102.0 + i * 3.2,
        latitude: 6.9215 + i * 0.0018,
        longitude: 79.8625 + i * 0.0088,
      )),
      brakeEvents: List.generate(8, (i) => BrakeEvent(
        timestamp: start.add(Duration(minutes: 4 + i * 6)),
        severity: i % 2 == 0 ? 'harsh' : 'moderate',
        deceleration: 9.5 + i * 1.2,
        latitude: 6.9218 + i * 0.0015,
        longitude: 79.8600 + i * 0.0080,
      )),
      stressPeaks: List.generate(5, (i) => StressPeakEvent(
        timestamp: start.add(Duration(minutes: 8 + i * 10)),
        stressLevel: 70 + i * 4,
        latitude: 6.9222 + i * 0.0020,
        longitude: 79.8614 + i * 0.0090,
      )),
      criticalEvents: [
        CriticalEvent(timestamp: start.add(const Duration(minutes: 12)), factors: ['risky_turn', 'stress_peak', 'harsh_braking', 'adverse_weather'], severity: 3, description: 'Multiple risk factors in congested evening traffic', latitude: 6.9235, longitude: 79.8703),
        CriticalEvent(timestamp: start.add(const Duration(minutes: 28)), factors: ['risky_turn', 'overspeed', 'stress_peak'], severity: 3, description: 'Speeding through narrow lane under high stress', latitude: 6.9275, longitude: 79.8919),
        CriticalEvent(timestamp: start.add(const Duration(minutes: 44)), factors: ['harsh_braking', 'stress_peak', 'sharp_turn'], severity: 2, description: 'Emergency stop while negotiating tight turn', latitude: 6.9318, longitude: 79.9105),
      ],
      sensorReadings: List.generate(58, (i) => SensorReading(
        timestamp: start.add(Duration(minutes: i)),
        heartRate: 88 + (i % 6),
        temperature: 36.9,
        stressLevel: 50 + (i % 10) * 4,
      )),
      gpsTrack: _simpleTrack(6.9331, 79.8498, 6.9352, 79.9160, start, 58),
      weatherContext: WeatherContext(
        condition: 'Thunderstorm', description: 'thunderstorm with light rain',
        temperature: 25.8, humidity: 93.0, windSpeed: 28.4, visibility: 3.2, icon: '11d',
      ),
      recommendations: [
        '⚠ HIGH RISK ride. Consider avoiding evening rush hour on this route.',
        'Thunderstorm conditions require 30% speed reduction — max safe speed was ~45 km/h.',
        'Stress level exceeded 80% five times. Take rest breaks on long congested routes.',
        'Review the two critical danger zones on the map — both had 3+ simultaneous risk factors.',
        'Practice smooth braking: 8 sudden brake events indicate aggressive following distance.',
      ],
    );
  }

  /// Generate a simple linear GPS track between two coordinates
  static List<GpsPoint> _simpleTrack(
    double startLat, double startLng,
    double endLat, double endLng,
    DateTime startTime, int minutes,
  ) {
    const steps = 40;
    return List.generate(steps, (i) {
      final t = i / (steps - 1);
      final secs = (t * minutes * 60).round();
      return GpsPoint(
        latitude: startLat + (endLat - startLat) * t,
        longitude: startLng + (endLng - startLng) * t,
        timestamp: startTime.add(Duration(seconds: secs)),
        speed: 30.0 + 20.0 * (0.5 - (t - 0.5).abs()),
      );
    });
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
