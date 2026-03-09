import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:smart_helmet_app/models/journey_model.dart';
import 'package:smart_helmet_app/providers/journey_provider.dart';
import 'package:smart_helmet_app/providers/ride_session_provider.dart';
import 'package:smart_helmet_app/services/journey_service.dart';
import 'package:smart_helmet_app/services/bluetooth_manager.dart';
import 'JourneyReportScreen.dart';
import 'dummy_journey_data.dart';

class Member3Page extends StatefulWidget {
  final JourneyData? completedJourney; // Optional: passed when ride just ended

  const Member3Page({super.key, this.completedJourney});

  @override
  State<Member3Page> createState() => _Member3PageState();
}

class _Member3PageState extends State<Member3Page>
    with SingleTickerProviderStateMixin {
  // Tab controller
  late TabController _tabController;

  // Journey Service
  final JourneyService _journeyService = JourneyService();
  List<JourneyData> _journeyHistory = [];

  bool _isLoadingHistory = false;

  // Show ride summary view
  bool _showRideSummary = false;
  JourneyData? _completedRide;

  // IMU Data from MPU6050 (Live Monitoring)
  double gyroX = 0.0;
  double gyroY = 0.0;
  double gyroZ = 0.0;
  double accelX = 0.0;
  double accelY = 0.0;
  double accelZ = 0.0;

  // Turn & Braking Detection
  int sharpTurnCount = 0;
  int riskyTurnCount = 0;
  int harshBrakeCount = 0;
  double leanAngle = 0.0; // Lean angle in degrees
  String currentTurnStatus = "Normal";
  Color statusColor = Colors.green;

  // Historical data for graph
  List<double> gyroZHistory = [];
  final int maxHistoryLength = 50;

  // Thresholds
  final double sharpTurnThreshold = 100.0;
  final double riskyTurnThreshold = 150.0;

  // Bluetooth - Uses shared BluetoothManager (connection handled in Home Page)
  static const String targetDeviceName = "SmartHelmet_ESP32";
  StreamSubscription? _dataSubscription;
  String _dataBuffer = "";
  bool _hasAddedBluetoothListener = false;

// Firestore
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSaving = false;
  DateTime? _lastSavedTime;
  final Duration _saveInterval =
      const Duration(seconds: 1); // ← change this value to control frequency
  // Current GPS state
  double currentSpeed = 0.0;
  double currentLat = 0.0;
  double currentLng = 0.0;

  // Distance tracking
  double totalDistanceKm = 0.0;
  double? lastLat;
  double? lastLng;

  // ── DEBUG DATA PUMP ───────────────────────────────────────
  Timer? _simulationTimer;
  bool _isSimulating = false;
  int _simPacketIndex = 0;

  // ── CSV LOGGING FOR RESEARCH ──────────────────────────────
  // Set to true to print raw data to Android Studio / VSCode console
  final bool _isCsvLoggingEnabled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadJourneyHistory();

    // Check if a completed journey was passed (ride just ended)
    if (widget.completedJourney != null) {
      _showRideSummary = true;
      _completedRide = widget.completedJourney;
    }

    // Add a listener to RideSessionProvider to detect when the ride ends
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final rideProvider =
            Provider.of<RideSessionProvider>(context, listen: false);
        rideProvider.addListener(_onRideStateChanged);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only add listener once
    if (!_hasAddedBluetoothListener) {
      _hasAddedBluetoothListener = true;
      // Subscribe to BluetoothManager changes to re-subscribe when connection state changes
      final btManager = context.read<BluetoothManager>();
      btManager.addListener(_onBluetoothStateChanged);
      // Initial subscription attempt
      _subscribeToESP32Data();
    }
  }

  void _onBluetoothStateChanged() {
    // Re-subscribe when connection state changes
    if (mounted) {
      _subscribeToESP32Data();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dataSubscription?.cancel();
    _simulationTimer?.cancel();
    // Remove listener from BluetoothManager
    try {
      final btManager = Provider.of<BluetoothManager>(context, listen: false);
      btManager.removeListener(_onBluetoothStateChanged);
    } catch (_) {}

    // Remove listener from RideSessionProvider
    try {
      final rideProvider =
          Provider.of<RideSessionProvider>(context, listen: false);
      rideProvider.removeListener(_onRideStateChanged);
    } catch (_) {}

    super.dispose();
  }

  // Detect when a ride ends
  void _onRideStateChanged() async {
    if (!mounted) return;
    final rideProvider =
        Provider.of<RideSessionProvider>(context, listen: false);
    final journeyProvider =
        Provider.of<JourneyProvider>(context, listen: false);

    // Trigger only when ride transitions from active → inactive
    if (!rideProvider.isRideActive && journeyProvider.isJourneyActive) {
      debugPrint(
          "RideSession ended. Saving JourneyData from memory to Firebase...");

      // Use the SHARED rideId from RideSessionProvider (same ID used by member1 & member2)

      // 1. Finalize in-memory journey (gives us GPS track, sensor readings, braking events)
      final baseJourney = journeyProvider.endJourney();
      if (baseJourney == null) return;

      // Grab the shared rideId AFTER baseJourney exists (fallback to baseJourney.id if provider has none)
      final sharedRideId = rideProvider.currentRideId ?? baseJourney.id;

      try {
        // 2. Build the final journey with the SHARED rideId
        final fullJourney = JourneyData(
          id: sharedRideId, // 🔑 Use shared rideId, NOT local timestamp
          startTime: baseJourney.startTime,
          endTime: DateTime.now(),
          startLocation:
              rideProvider.destinationName ?? baseJourney.startLocation,
          destination: rideProvider.destinationName ?? baseJourney.destination,
          sharpTurns: baseJourney.sharpTurns,
          riskyTurns: baseJourney.riskyTurns,
          totalBrakingEvents: baseJourney.totalBrakingEvents,
          averageSpeed: baseJourney.averageSpeed,
          maxSpeed: baseJourney.maxSpeed,
          maxTurnRate: baseJourney.maxTurnRate,
          totalDistance: baseJourney.totalDistance,
          dangerPrediction: baseJourney.dangerPrediction,
          turnEvents: baseJourney.turnEvents,
          brakingEvents: baseJourney.brakingEvents,
          sensorReadings: baseJourney.sensorReadings,
          gpsTrack: baseJourney.gpsTrack,
        );

        // 3. Save to Firestore under the SHARED rideId
        await _journeyService.saveJourney(fullJourney);
        debugPrint("✅ Journey saved with shared rideId: $sharedRideId | "
            "${fullJourney.turnEvents.length} turn events, "
            "${fullJourney.brakingEvents.length} braking events.");

        // 4. Navigate directly to the full JourneyReportScreen
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JourneyReportScreen(journey: fullJourney),
            ),
          );
        }

        // Refresh history in background
        _loadJourneyHistory();
      } catch (e) {
        debugPrint("❌ Error saving full journey data: $e");
        // Fallback: still show the report with whatever in-memory data we have
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JourneyReportScreen(journey: baseJourney),
            ),
          );
        }
      }
    }
  }

  // Subscribe to ESP32 data stream from shared BluetoothManager
  void _subscribeToESP32Data() {
    final btManager = context.read<BluetoothManager>();

    // Find a connected device - try specific name first, then any ESP32
    String? deviceToUse;

    if (btManager.isConnected(targetDeviceName)) {
      deviceToUse = targetDeviceName;
    } else {
      // Search for any connected device that looks like an ESP32
      final connectedDevices = btManager.getConnectedDevices();
      debugPrint("Connected devices: $connectedDevices");

      for (final device in connectedDevices) {
        if (device.toLowerCase().contains('esp') ||
            device.toLowerCase().contains('helmet') ||
            device.toLowerCase().contains('imu')) {
          deviceToUse = device;
          break;
        }
      }

      // If still not found, try the first connected device
      if (deviceToUse == null && connectedDevices.isNotEmpty) {
        deviceToUse = connectedDevices.first;
        debugPrint("Using first connected device: $deviceToUse");
      }
    }

    if (deviceToUse == null) {
      debugPrint("No ESP32/IMU device connected - waiting for connection");
      return;
    }

    final dataStream = btManager.getDataStream(deviceToUse);
    if (dataStream == null) {
      debugPrint("No data stream available for $deviceToUse");
      return;
    }

    // Cancel existing subscription before creating new one
    _dataSubscription?.cancel();
    _dataSubscription = dataStream.listen(
      (data) {
        debugPrint("Received ${data.length} bytes from $deviceToUse");
        _handleIncomingData(data);
      },
      onError: (e) => debugPrint("$deviceToUse Stream Error: $e"),
    );
    debugPrint("✓ Subscribed to $deviceToUse data stream");
  }

  // Load journey history from Firebase
  Future<void> _loadJourneyHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final journeys = await _journeyService.getAllJourneys();
      setState(() {
        _journeyHistory = journeys;
        _isLoadingHistory = false;
      });
    } catch (e) {
      setState(() => _isLoadingHistory = false);
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading journeys: $e')),
        );
      }
    }
  }

  // Handle incoming data from ESP32 via BluetoothManager
  void _handleIncomingData(List<int> data) {
    _dataBuffer += String.fromCharCodes(data);
    while (_dataBuffer.contains('\n')) {
      int newlineIndex = _dataBuffer.indexOf('\n');
      String jsonString = _dataBuffer.substring(0, newlineIndex).trim();
      _dataBuffer = _dataBuffer.substring(newlineIndex + 1);
      if (jsonString.isNotEmpty) {
        _parseIMUData(jsonString);
      }
    }
  }

  void _parseIMUData(String jsonString) {
    try {
      Map<String, dynamic> data = json.decode(jsonString);

      // Update GPS variables if they exist in the JSON
      // Note: Ensure your ESP32 sends 'spd', 'lat', 'lng' keys!
      double newSpeed = (data['spd'] ?? 0.0).toDouble();
      double newLat = (data['lat'] ?? 0.0).toDouble();
      double newLng = (data['lng'] ?? 0.0).toDouble();

      _processIMUData(
        imuData: {
          'gyroX': (data['gyroX'] ?? 0.0).toDouble(),
          'gyroY': (data['gyroY'] ?? 0.0).toDouble(),
          'gyroZ': (data['gyroZ'] ?? 0.0).toDouble(),
          'accelX': (data['accelX'] ?? 0.0).toDouble(),
          'accelY': (data['accelY'] ?? 0.0).toDouble(),
          'accelZ': (data['accelZ'] ?? 0.0).toDouble(),
        },
        speed: newSpeed,
        lat: newLat,
        lng: newLng,
      );
    } catch (e) {
      debugPrint('Error parsing Data: $e');
      debugPrint('Raw data: $jsonString');
    }
  }

  void _processIMUData({
    required Map<String, double> imuData,
    required double speed,
    required double lat,
    required double lng,
  }) {
    if (!mounted) return;

    final journeyProvider =
        Provider.of<JourneyProvider>(context, listen: false);

    // ─── NEW: Calculate new turn status FIRST ────────────────────────────────
    double turnRate = imuData['gyroZ']!.abs();
    String newTurnStatus = "Normal";
    Color newStatusColor = Colors.green;
    String? eventType; // null = no risky event

    if (turnRate > riskyTurnThreshold) {
      newTurnStatus = "RISKY TURN!";
      newStatusColor = Colors.red;
      isRiskyThisReading = true;
      riskyTurnCount++;
    } else if (turnRate > sharpTurnThreshold) {
      newTurnStatus = "Sharp Turn";
      newStatusColor = Colors.orange;
      sharpTurnCount++;
    }

    // ─── Save to Firestore BEFORE setState (we already know if it's risky) ───
    if (imuData['gyroZ'] != null) {
      _saveLiveReadingIfNeeded(
        imuData,
        speed,
        lat,
        lng,
        isRiskyThisReading, // ← pass the flag directly
      );
    }

    // Now safe to update UI
    setState(() {
      gyroX = imuData['gyroX']!;
      gyroY = imuData['gyroY']!;
      gyroZ = imuData['gyroZ']!;
      accelX = imuData['accelX']!;
      accelY = imuData['accelY']!;
      accelZ = imuData['accelZ']!;

      // Calculate lean angle from accelerometer (X=UP, Y=LEFT)
      // atan2(lateral, vertical) gives the tilt angle
      leanAngle = atan2(accelY, accelX) * (180.0 / pi);

      gyroZHistory.add(gyroX.abs()); // Use gyroX for yaw (X=UP axis mapping)
      if (gyroZHistory.length > maxHistoryLength) {
        gyroZHistory.removeAt(0);
      }

      currentTurnStatus = newTurnStatus;
      statusColor = newStatusColor;

      // GPS processing
      if (lat != 0.0 && lng != 0.0) {
        currentLat = lat;
        currentLng = lng;
        currentSpeed = speed;

        if (lastLat != null && lastLng != null) {
          totalDistanceKm += _calculateDistance(lastLat!, lastLng!, lat, lng);
        }
        lastLat = lat;
        lastLng = lng;

        if (journeyProvider.isJourneyActive) {
          journeyProvider.updateDistanceAndSpeed(totalDistanceKm, currentSpeed);
          // ✅ Record GPS point with speed into the journey track
          journeyProvider.addGpsPoint(
            latitude: lat,
            longitude: lng,
            speedKmh: speed,
          );
        }
      }

      // Add full sensor reading (including all IMU data + GPS for braking detection)
      if (eventType != null) {
        _saveRiskyEventOnly(
            imuData, currentSpeed, currentLat, currentLng, eventType);
      }
      if (journeyProvider.isJourneyActive) {
        if (isRiskyThisReading) {
          journeyProvider.addTurnEvent(
            severity: 'risky',
            turnRate: turnRate,
            latitude: currentLat,
            longitude: currentLng,
          );
        } else if (eventType == 'sharp_turn') {
          journeyProvider.addTurnEvent(
            severity: 'sharp',
            turnRate: turnRate,
            latitude: currentLat,
            longitude: currentLng,
          );
        } else if (eventType == 'harsh_brake' ||
            eventType == 'emergency_brake') {
          journeyProvider.addBrakingEvent(
            severity: eventType == 'emergency_brake' ? 'emergency' : 'hard',
            deceleration:
                imuData['accelZ']!, // accelZ = forward axis (X=UP mount)
            speedBefore: currentSpeed,
            latitude: currentLat,
            longitude: currentLng,
          );
        }
      }
    });
  }

  // Haversine formula to calculate distance between two GPS points in km
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371.0; // km
    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);
    double a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            (sin(dLon / 2) * sin(dLon / 2));
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degree) {
    return degree * (pi / 180);
  }

  Future<void> _saveLiveReadingIfNeeded(
    Map<String, double> imu,
    double speed,
    double lat,
    double lng,
    String eventType, // 'risky_turn', 'sharp_turn', 'harsh_brake'
  ) async {
    if (_isSaving) return;

    final now = DateTime.now();
    final timePassed = _lastSavedTime == null ||
        now.difference(_lastSavedTime!) >= _saveInterval;

    // Save if time interval passed OR this reading is risky
    if (!timePassed && !isRiskyThisReading) return;

    setState(() => _isSaving = true);

    try {
      final data = {
        "timestamp": now.toIso8601String(),
        "createdAt": FieldValue.serverTimestamp(),
        "gyroX": imu['gyroX'],
        "gyroY": imu['gyroY'],
        "gyroZ": imu['gyroZ'],
        "turnRateDegPerSec": turnRate,
        "accelX": imu['accelX'],
        "accelY": imu['accelY'],
        "accelZ": imu['accelZ'],
        "speedKmh": speed,
        "latitude": lat,
        "longitude": lng,
        "location": GeoPoint(lat, lng),
        "turnStatus":
            currentTurnStatus, // still use latest UI value, but we know it's risky
        "turnRateDegPerSec": imu['gyroZ']!.abs(),
        "sharpTurnsTotal": sharpTurnCount,
        "riskyTurnsTotal": riskyTurnCount,
        "totalDistanceKm": totalDistanceKm,
        "deviceName": targetDeviceName,
        "isRiskyEvent": isRiskyThisReading, // ← more accurate
      };

      await _firestore.collection("helmet_live_readings").add(data);

      _lastSavedTime = now;
      debugPrint("Live reading saved → Risky: $isRiskyThisReading");
    } catch (e) {
      debugPrint("Firestore save error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save risky event: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    if (mounted)
      setState(() {
        _isSimulating = false;
        _simPacketIndex = 0;
      });
    debugPrint('[SIM] Simulation stopped after $_simPacketIndex packets.');
  }

  // Load risky events from Firebase for a specific ride
  Future<List<Map<String, dynamic>>> loadRiskyEventsForRide(
      String rideId) async {
    try {
      final snapshot = await _firestore
          .collection("risky_events")
          .where("rideId", isEqualTo: rideId)
          .orderBy("timestamp")
          .get();

      return snapshot.docs
          .map((doc) => {
                ...doc.data(),
                "docId": doc.id,
              })
          .toList();
    } catch (e) {
      debugPrint("Error loading risky events: $e");
      return [];
    }
  }

  // Get all risky events for current ride (for visualization)
  List<Map<String, dynamic>> getRiskyEventsForVisualization() {
    return List.from(_riskyEventsThisRide);
  }

  // Load risky events from Firebase for a specific ride
  Future<List<Map<String, dynamic>>> loadRiskyEventsForRide(String rideId) async {
    try {
      final snapshot = await _firestore
          .collection("risky_events")
          .where("rideId", isEqualTo: rideId)
          .orderBy("timestamp")
          .get();
      
      return snapshot.docs.map((doc) => {
        ...doc.data(),
        "docId": doc.id,
      }).toList();
    } catch (e) {
      debugPrint("Error loading risky events: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Risk Assessment',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        backgroundColor: Colors.blue[700],
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.history), text: 'Journey History'),
            Tab(icon: Icon(Icons.sensors), text: 'Live Monitoring'),
          ],
        ),
        actions: [
          // DEBUG: Simulate ride data pump
          IconButton(
            icon: Icon(
              _isSimulating ? Icons.stop_circle : Icons.science,
              color: _isSimulating ? Colors.redAccent : Colors.amber,
            ),
            tooltip: _isSimulating ? 'Stop Simulation' : 'Simulate Ride Data',
            onPressed: _startSimulatedRide,
          ),
          // Connection status indicator in AppBar (read-only, connect from Home)
          Consumer<BluetoothManager>(
            builder: (context, btManager, child) {
              // Check for any connected device
              final connectedDevices = btManager.getConnectedDevices();
              final isConnected = connectedDevices.isNotEmpty;
              return IconButton(
                icon: Icon(isConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled),
                color: isConnected ? Colors.green : Colors.white70,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isConnected
                            ? 'Connected to: ${connectedDevices.join(", ")}'
                            : 'Not connected. Connect from Home page.',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                tooltip: isConnected ? 'Connected ✓' : 'Not Connected',
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _showRideSummary && _completedRide != null
              ? _buildRideSummaryView(_completedRide!)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildJourneyHistoryTab(),
                    _buildLiveMonitoringTab(),
                  ],
                ),

          // Saving indicator
          if (_isSaving)
            const Positioned(
              bottom: 24,
              right: 24,
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        "Saving...",
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Ride Summary View - shown after ride ends
  Widget _buildRideSummaryView(JourneyData journey) {
    final duration = journey.endTime != null
        ? journey.endTime!.difference(journey.startTime)
        : Duration.zero;

    final totalTurns = journey.sharpTurns + journey.riskyTurns;
    final riskLevel = journey.riskyTurns > 5 || totalTurns > 15
        ? 'High Risk'
        : journey.riskyTurns > 2 || totalTurns > 8
            ? 'Moderate'
            : 'Low Risk';
    final riskColor = journey.riskyTurns > 5 || totalTurns > 15
        ? Colors.red
        : journey.riskyTurns > 2 || totalTurns > 8
            ? Colors.orange
            : Colors.green;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Success Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green[400]!, Colors.green[600]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle, size: 64, color: Colors.white),
                const SizedBox(height: 12),
                const Text(
                  'Ride Completed!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  DateFormat('EEEE, MMM dd, yyyy • HH:mm')
                      .format(journey.startTime),
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Route Info Card
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.route, color: Colors.blue[700], size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        'Route',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildRouteRow(Icons.trip_origin, 'Start',
                      journey.startLocation ?? 'Unknown', Colors.green),
                  const SizedBox(height: 12),
                  _buildRouteRow(Icons.place, 'Destination',
                      journey.destination ?? 'Unknown', Colors.red),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Stats Grid
          Row(
            children: [
              Expanded(
                  child: _buildSummaryStatCard('Duration',
                      '${duration.inMinutes} min', Icons.timer, Colors.blue)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildSummaryStatCard(
                      'Distance',
                      '${journey.totalDistance.toStringAsFixed(1)} km',
                      Icons.straighten,
                      Colors.purple)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _buildSummaryStatCard(
                      'Avg Speed',
                      '${journey.averageSpeed.toStringAsFixed(1)} km/h',
                      Icons.speed,
                      Colors.teal)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildSummaryStatCard(
                      'Risk Level', riskLevel, Icons.shield, riskColor)),
            ],
          ),
          const SizedBox(height: 16),

          // Turn Events Card
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics,
                          color: Colors.orange[700], size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        'Turn Analysis',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTurnStat(
                            'Sharp Turns', journey.sharpTurns, Colors.orange),
                      ),
                      Container(width: 1, height: 60, color: Colors.grey[300]),
                      Expanded(
                        child: _buildTurnStat(
                            'Risky Turns', journey.riskyTurns, Colors.red),
                      ),
                    ],
                  ),
                  if (journey.turnEvents.isNotEmpty) ...[
                    const Divider(height: 24),
                    const Text(
                      'Turn Events Timeline',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    ...journey.turnEvents
                        .take(5)
                        .map((event) => _buildTurnEventItem(event)),
                    if (journey.turnEvents.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '+ ${journey.turnEvents.length - 5} more events',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _buildSummaryActions(journey),
        ],
      ),
    );
  }

  Widget _buildRouteRow(
      IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            Text(value,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  // Update Ride Summary Actions
  Widget _buildSummaryActions(JourneyData journey) {
    return Column(children: [
      // View Detailed Report Button
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            _showJourneyDetails(journey);
          },
          icon: const Icon(Icons.analytics),
          label: const Text('View Detailed Report'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(
                0xFF2A2D35), // Dark sleek color matching the report screen
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 4,
          ),
        ),
      ),
      const SizedBox(height: 16),
      // Action Buttons
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _showRideSummary = false;
                  _completedRide = null;
                });
              },
              icon: const Icon(Icons.history),
              label: const Text('All Journeys'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context)
                  .pop(), // Pop to go back to previous dashboard state
              icon: const Icon(Icons.home),
              label: const Text('Back to Home'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _buildSummaryStatCard(
      String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnStat(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildTurnEventItem(TurnEvent event) {
    final isRisky = event.severity == 'risky';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isRisky ? Colors.red : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${isRisky ? "Risky" : "Sharp"} turn at ${DateFormat('HH:mm:ss').format(event.timestamp)}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            '${event.turnRate.toStringAsFixed(1)}°/s',
            style: TextStyle(
              fontSize: 12,
              color: isRisky ? Colors.red : Colors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Journey History Tab

  Widget _buildJourneyHistoryTab() {
    return RefreshIndicator(
      onRefresh: _loadJourneyHistory,
      child: _isLoadingHistory
          ? const Center(child: CircularProgressIndicator())
          : _journeyHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.route_outlined,
                          size: 70,
                          color: _textSecondary.withValues(alpha: 0.2)),
                      const SizedBox(height: 16),
                      const Text('No journeys recorded yet',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: _textPrimary)),
                      const SizedBox(height: 8),
                      const Text('Start a journey from Home Dashboard',
                          style:
                              TextStyle(fontSize: 14, color: _textSecondary)),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          gradient:
                              const LinearGradient(colors: [_primary, _accent]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _showDummyReport,
                          icon: const Icon(Icons.science, color: Colors.white),
                          label: const Text('View Sample Report',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Test button
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [Colors.orange[700]!, Colors.deepOrange]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _showDummyReport,
                          icon: const Icon(Icons.science, color: Colors.white),
                          label: const Text('View Sample Report',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _journeyHistory.length,
                        itemBuilder: (context, index) {
                          final journey = _journeyHistory[index];
                          return _buildJourneyCard(journey);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildJourneyCard(JourneyData journey) {
    final duration = journey.endTime != null
        ? journey.endTime!.difference(journey.startTime)
        : Duration.zero;

    // Determine risk color for left border
    final totalTurns = journey.sharpTurns + journey.riskyTurns;
    final Color riskColor = journey.riskyTurns > 5 || totalTurns > 15
        ? const Color(0xFFC62828)
        : journey.riskyTurns > 2 || totalTurns > 8
            ? const Color(0xFFF57F17)
            : const Color(0xFF2E7D32);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: InkWell(
        onTap: () => _showJourneyDetails(journey),
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            // Left colored accent bar
            Container(
              width: 5,
              height: 130,
              decoration: BoxDecoration(
                color: riskColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.navigation,
                              color: _accent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                journey.destination ?? 'Unknown Destination',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: _textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('MMM dd, yyyy • HH:mm')
                                    .format(journey.startTime),
                                style: const TextStyle(
                                    color: _textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        _getRiskBadge(journey),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                        height: 1,
                        color: _textSecondary.withValues(alpha: 0.2)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatColumn(
                            Icons.route,
                            '${journey.totalDistance.toStringAsFixed(1)} km',
                            'Distance'),
                        _buildStatColumn(Icons.timer,
                            '${duration.inMinutes} min', 'Duration'),
                        _buildStatColumn(
                            Icons.turn_sharp_right,
                            '${journey.sharpTurns}',
                            'Sharp',
                            const Color(0xFFF57F17)),
                        _buildStatColumn(Icons.warning, '${journey.riskyTurns}',
                            'Risky', const Color(0xFFC62828)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getRiskBadge(JourneyData journey) {
    final totalTurns = journey.sharpTurns + journey.riskyTurns;
    Color color;
    String label;
    IconData icon;

    if (journey.riskyTurns > 5 || totalTurns > 15) {
      color = const Color(0xFFC62828);
      label = 'HIGH';
      icon = Icons.error_outline;
    } else if (journey.riskyTurns > 2 || totalTurns > 8) {
      color = const Color(0xFFF57F17);
      label = 'MED';
      icon = Icons.warning_amber_rounded;
    } else {
      color = const Color(0xFF2E7D32);
      label = 'LOW';
      icon = Icons.shield_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildStatColumn(IconData icon, String value, String label,
      [Color? color]) {
    final c = color ?? _accent;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: c),
        ),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color ?? _textPrimary)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: _textSecondary)),
      ],
    );
  }

  void _showJourneyDetails(JourneyData journey) {
    // Navigate to full report screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JourneyReportScreen(journey: journey),
      ),
    );
  }

  // Method to show dummy report directly for testing
  void _showDummyReport() {
    final dummyJourney = DummyJourneyData.getSampleJourney();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JourneyReportScreen(journey: dummyJourney),
      ),
    );
  }

  // Method to load dummy history for testing

  // Live Monitoring Tab
  // ═══════════════════════════════════════════════════════════════
  //  DESIGN SYSTEM CONSTANTS
  // ═══════════════════════════════════════════════════════════════
  static const Color _primary = Color(0xFF1565C0);
  static const Color _accent = Color(0xFF00B0FF);
  static const Color _cardBg = Colors.white;
  static const Color _surfaceBg = Color(0xFFF0F2F5);
  static const Color _textPrimary = Color(0xFF1E1E2E);
  static const Color _textSecondary = Color(0xFF6B7280);

  Widget _buildLiveMonitoringTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildConnectionCard(),
          const SizedBox(height: 16),
          _buildStatusCard(),
          const SizedBox(height: 16),
          _buildGPSCard(),
          const SizedBox(height: 16),
          _buildStatisticsRow(),
          const SizedBox(height: 16),
          _buildLeanAngleCard(),
          const SizedBox(height: 20),
          _buildSectionHeader('Sensor Data', Icons.sensors),
          const SizedBox(height: 12),
          _buildGyroscopeCard(),
          const SizedBox(height: 12),
          _buildAccelerometerCard(),
          const SizedBox(height: 16),
          _buildTurnRateGraph(),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF0D47A1)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: _primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4))
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _resetCounters,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: const Text('Reset Counters',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_primary, _accent]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Text(title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _textPrimary)),
        const SizedBox(width: 12),
        Expanded(
            child: Container(
                height: 1, color: _textSecondary.withValues(alpha: 0.2))),
      ],
    );
  }

  // Keep all existing build methods for live monitoring
  Widget _buildConnectionCard() {
    return Consumer<BluetoothManager>(
      builder: (context, btManager, child) {
        // Check for specific device or any connected device
        final connectedDevices = btManager.getConnectedDevices();
        String? connectedDevice;

        if (btManager.isConnected(targetDeviceName)) {
          connectedDevice = targetDeviceName;
        } else {
          for (final device in connectedDevices) {
            if (device.toLowerCase().contains('esp') ||
                device.toLowerCase().contains('helmet') ||
                device.toLowerCase().contains('imu')) {
              connectedDevice = device;
              break;
            }
          }
          if (connectedDevice == null && connectedDevices.isNotEmpty) {
            connectedDevice = connectedDevices.first;
          }
        }

        final isConnected = connectedDevice != null;

        return Card(
          color: isConnected ? Colors.green[50] : Colors.grey[100],
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        children: [
                          Icon(
                            isConnected
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth_disabled,
                            color: isConnected ? Colors.green : Colors.grey,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('ESP32/IMU Connection',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                Text(
                                  isConnected
                                      ? 'Connected to: $connectedDevice'
                                      : 'Not connected',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: isConnected
                                          ? Colors.green
                                          : Colors.grey[700]),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isConnected)
                      OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Please connect to ESP32 from the Home page'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.info_outline, size: 18),
                        label: const Text('Connect from Home'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                        ),
                      ),
                    if (isConnected)
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 28),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusCard() {
    final isRisky = currentTurnStatus == "RISKY TURN!" ||
        currentTurnStatus == "EMERGENCY BRAKE!";
    final isWarning = currentTurnStatus == "Sharp Turn" ||
        currentTurnStatus == "Harsh Brake" ||
        currentTurnStatus == "HIGH SPEED!";

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isRisky
              ? [const Color(0xFFC62828), const Color(0xFFB71C1C)]
              : isWarning
                  ? [const Color(0xFFF57F17), const Color(0xFFE65100)]
                  : [const Color(0xFF1B5E20), const Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isRisky
                    ? const Color(0xFFC62828)
                    : isWarning
                        ? const Color(0xFFF57F17)
                        : const Color(0xFF2E7D32))
                .withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(_getStatusIcon(),
                key: ValueKey(currentTurnStatus),
                size: 52,
                color: Colors.white),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              currentTurnStatus,
              key: ValueKey('status_$currentTurnStatus'),
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 6),
          Text('Turn Rate: ${gyroX.abs().toStringAsFixed(1)}°/s',
              style: TextStyle(
                  fontSize: 14, color: Colors.white.withValues(alpha: 0.2))),
        ],
      ),
    );
  }

  IconData _getStatusIcon() {
    if (currentTurnStatus == "RISKY TURN!") return Icons.warning_amber;
    if (currentTurnStatus == "Sharp Turn") return Icons.turn_sharp_right;
    if (currentTurnStatus == "EMERGENCY BRAKE!" ||
        currentTurnStatus == "Harsh Brake") return Icons.front_hand_rounded;
    if (currentTurnStatus == "HIGH SPEED!") return Icons.speed;
    return Icons.check_circle;
  }

  Widget _buildStatisticsRow() {
    return Row(
      children: [
        Expanded(
            child: _buildStatCard('Sharp Turns', sharpTurnCount.toString(),
                Icons.turn_right, Colors.orange)),
        const SizedBox(width: 8),
        Expanded(
            child: _buildStatCard('Risky Turns', riskyTurnCount.toString(),
                Icons.warning, Colors.red)),
        const SizedBox(width: 8),
        Expanded(
            child: _buildStatCard('Harsh Brakes', harshBrakeCount.toString(),
                Icons.stop_circle_outlined, Colors.purple)),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: _textSecondary,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildLeanAngleCard() {
    final absAngle = leanAngle.abs();
    Color angleColor;
    String angleLabel;

    if (absAngle < 15) {
      angleColor = const Color(0xFF2E7D32);
      angleLabel = 'Normal';
    } else if (absAngle < 30) {
      angleColor = const Color(0xFFF57F17);
      angleLabel = 'Aggressive';
    } else if (absAngle < 45) {
      angleColor = Colors.deepOrange;
      angleLabel = 'Dangerous';
    } else {
      angleColor = const Color(0xFFC62828);
      angleLabel = 'EXTREME!';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: angleColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.rotate_90_degrees_ccw,
                    size: 20, color: angleColor),
              ),
              const SizedBox(width: 10),
              const Text('Lean Angle',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary)),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: angleColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: angleColor.withValues(alpha: 0.2), width: 1.5),
                ),
                child: Text(angleLabel,
                    style: TextStyle(
                        color: angleColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: CustomPaint(
                  painter:
                      _LeanAnglePainter(angle: leanAngle, color: angleColor)),
            ),
          ),
          const SizedBox(height: 10),
          Center(
              child: Text('${leanAngle.toStringAsFixed(1)}°',
                  style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: angleColor))),
          const SizedBox(height: 4),
          Center(
            child: Text(
              leanAngle > 0
                  ? '← Leaning Left'
                  : leanAngle < 0
                      ? 'Leaning Right →'
                      : 'Upright',
              style: const TextStyle(fontSize: 13, color: _textSecondary),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildAngleZone('0°-15°', 'Normal', const Color(0xFF2E7D32)),
              _buildAngleZone('15°-30°', 'Aggress.', const Color(0xFFF57F17)),
              _buildAngleZone('30°-45°', 'Danger', Colors.deepOrange),
              _buildAngleZone('45°+', 'Extreme', const Color(0xFFC62828)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAngleZone(String range, String label, Color color) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 4)
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(range,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _textPrimary)),
        Text(label, style: const TextStyle(fontSize: 9, color: _textSecondary)),
      ],
    );
  }

  Widget _buildGyroscopeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.screen_rotation_alt, size: 18, color: _accent),
              const SizedBox(width: 8),
              const Text('Gyroscope',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary)),
              const Spacer(),
              Text('°/s',
                  style: TextStyle(
                      fontSize: 12,
                      color: _textSecondary.withValues(alpha: 0.2))),
            ],
          ),
          const SizedBox(height: 14),
          _buildDataRow('X (Yaw)', gyroX, const Color(0xFFEF5350)),
          _buildDataRow('Y (Pitch)', gyroY, const Color(0xFF66BB6A)),
          _buildDataRow('Z (Roll)', gyroZ, const Color(0xFF42A5F5)),
        ],
      ),
    );
  }

  Widget _buildAccelerometerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, size: 18, color: _accent),
              const SizedBox(width: 8),
              const Text('Accelerometer',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary)),
              const Spacer(),
              Text('m/s²',
                  style: TextStyle(
                      fontSize: 12,
                      color: _textSecondary.withValues(alpha: 0.2))),
            ],
          ),
          const SizedBox(height: 14),
          _buildDataRow('X (Up)', accelX, const Color(0xFFEF5350)),
          _buildDataRow('Y (Lat)', accelY, const Color(0xFF66BB6A)),
          _buildDataRow('Z (Fwd)', accelZ, const Color(0xFF42A5F5)),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
              width: 75,
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: _textSecondary))),
          Expanded(
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                  color: _surfaceBg, borderRadius: BorderRadius.circular(6)),
              child: FractionallySizedBox(
                widthFactor: (value.abs() / 200).clamp(0.01, 1.0),
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [color.withValues(alpha: 0.2), color]),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: color),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnRateGraph() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.show_chart_rounded,
                    size: 18, color: _accent),
              ),
              const SizedBox(width: 10),
              const Text('Turn Rate History',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 150,
            decoration: BoxDecoration(
                color: _surfaceBg, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.all(8),
            child: CustomPaint(
              size: Size.infinite,
              painter: GraphPainter(
                  data: gyroZHistory,
                  sharpThreshold: sharpTurnThreshold,
                  riskyThreshold: riskyTurnThreshold),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegend('Normal', const Color(0xFF2E7D32)),
              const SizedBox(width: 16),
              _buildLegend('Sharp', const Color(0xFFF57F17)),
              const SizedBox(width: 16),
              _buildLegend('Risky', const Color(0xFFC62828)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(String label, Color color) {
    return Row(
      children: [
        Container(
            width: 14,
            height: 4,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 11, color: _textSecondary)),
      ],
    );
  }

  void _resetCounters() {
    setState(() {
      sharpTurnCount = 0;
      riskyTurnCount = 0;
      harshBrakeCount = 0;
      gyroZHistory.clear();
    });
  }

  Widget _buildGPSCard() {
    final hasFix = currentLat != 0.0 && currentLng != 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasFix
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.2)
                      : Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(hasFix ? Icons.gps_fixed : Icons.gps_not_fixed,
                    color: hasFix ? const Color(0xFF4CAF50) : Colors.grey,
                    size: 20),
              ),
              const SizedBox(width: 10),
              const Text('GPS Data',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary)),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hasFix
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.2)
                      : Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(hasFix ? '✓ Fix' : '✗ No Fix',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: hasFix ? const Color(0xFF4CAF50) : Colors.grey)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildGPSRow('Latitude',
              currentLat != 0.0 ? currentLat.toStringAsFixed(6) : '—'),
          _buildGPSRow('Longitude',
              currentLng != 0.0 ? currentLng.toStringAsFixed(6) : '—'),
          _buildGPSRow(
              'Speed',
              currentSpeed != 0.0
                  ? '${currentSpeed.toStringAsFixed(1)} km/h'
                  : '0.0 km/h'),
          _buildGPSRow('Distance', '${totalDistanceKm.toStringAsFixed(2)} km'),
        ],
      ),
    );
  }

  Widget _buildGPSRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: _textSecondary)),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary)),
        ],
      ),
    );
  }
} // End of _Member3PageState class

// Journey Details Sheet
class JourneyDetailsSheet extends StatelessWidget {
  final JourneyData journey;

  const JourneyDetailsSheet({super.key, required this.journey});

  @override
  Widget build(BuildContext context) {
    final duration = journey.endTime != null
        ? journey.endTime!.difference(journey.startTime)
        : Duration.zero;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      journey.destination ?? 'Journey Details',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('EEEE, MMM dd, yyyy • HH:mm')
                          .format(journey.startTime),
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                    _buildDetailCard(
                      'Journey Summary',
                      [
                        _buildDetailRow(Icons.route, 'Distance',
                            '${journey.totalDistance.toStringAsFixed(2)} km'),
                        _buildDetailRow(Icons.timer, 'Duration',
                            '${duration.inMinutes} minutes'),
                        _buildDetailRow(Icons.speed, 'Avg Speed',
                            '${journey.averageSpeed.toStringAsFixed(1)} km/h'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildDetailCard(
                      'Risk Assessment',
                      [
                        _buildDetailRow(Icons.turn_sharp_right, 'Sharp Turns',
                            '${journey.sharpTurns}', Colors.orange),
                        _buildDetailRow(Icons.warning, 'Risky Turns',
                            '${journey.riskyTurns}', Colors.red),
                        _buildDetailRow(Icons.assessment, 'Total Events',
                            '${journey.turnEvents.length}'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Generate PDF report
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Generate Report feature coming soon!')),
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Generate Report'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailCard(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value,
      [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 24, color: color ?? Colors.grey[700]),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

// Graph Painter
class GraphPainter extends CustomPainter {
  final List<double> data;
  final double sharpThreshold;
  final double riskyThreshold;

  GraphPainter({
    required this.data,
    required this.sharpThreshold,
    required this.riskyThreshold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // Threshold lines
    final sharpPaint = Paint()
      ..color = Colors.orange.withValues(alpha: 0.2)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final riskyPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.2)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    double sharpY = size.height - (sharpThreshold / 200 * size.height);
    double riskyY = size.height - (riskyThreshold / 200 * size.height);

    canvas.drawLine(Offset(0, sharpY), Offset(size.width, sharpY), sharpPaint);
    canvas.drawLine(Offset(0, riskyY), Offset(size.width, riskyY), riskyPaint);

    // Data line
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();

    for (int i = 0; i < data.length; i++) {
      double x = (i / (data.length - 1)) * size.width;
      double y = size.height - (data[i].clamp(0, 200) / 200 * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.sharpThreshold != sharpThreshold ||
        oldDelegate.riskyThreshold != riskyThreshold;
  }
}

// Lean Angle Visual Gauge Painter
class _LeanAnglePainter extends CustomPainter {
  final double angle; // in degrees, positive = left, negative = right
  final Color color;

  _LeanAnglePainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.8);
    final radius = size.height * 0.7;

    // Draw zone arcs (background)
    _drawZoneArc(
        canvas, center, radius, -45, -30, Colors.red.withValues(alpha: 0.2));
    _drawZoneArc(canvas, center, radius, -30, -15,
        Colors.deepOrange.withValues(alpha: 0.2));
    _drawZoneArc(
        canvas, center, radius, -15, 0, Colors.green.withValues(alpha: 0.2));
    _drawZoneArc(
        canvas, center, radius, 0, 15, Colors.green.withValues(alpha: 0.2));
    _drawZoneArc(canvas, center, radius, 15, 30,
        Colors.deepOrange.withValues(alpha: 0.2));
    _drawZoneArc(
        canvas, center, radius, 30, 45, Colors.red.withValues(alpha: 0.2));

    // Draw tick marks
    for (int deg = -45; deg <= 45; deg += 15) {
      final rad = (deg - 90) * pi / 180;
      final innerR = radius * 0.85;
      final outerR = radius;
      final start =
          Offset(center.dx + innerR * cos(rad), center.dy + innerR * sin(rad));
      final end =
          Offset(center.dx + outerR * cos(rad), center.dy + outerR * sin(rad));

      final tickPaint = Paint()
        ..color = deg == 0 ? Colors.white : Colors.grey
        ..strokeWidth = deg == 0 ? 3 : 1.5;
      canvas.drawLine(start, end, tickPaint);

      // Tick labels
      final labelR = radius * 0.75;
      final labelOffset =
          Offset(center.dx + labelR * cos(rad), center.dy + labelR * sin(rad));
      final textSpan = TextSpan(
        text: '${deg.abs()}°',
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 10,
          fontWeight: deg == 0 ? FontWeight.bold : FontWeight.normal,
        ),
      );
      final tp = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: ui.TextDirection.ltr);
      tp.layout();
      canvas.save();
      canvas.translate(
          labelOffset.dx - tp.width / 2, labelOffset.dy - tp.height / 2);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // Draw needle (the lean indicator)
    final clampedAngle = angle.clamp(-60.0, 60.0);
    final needleRad = (clampedAngle - 90) * pi / 180;
    final needleEnd = Offset(
      center.dx + (radius * 0.82) * cos(needleRad),
      center.dy + (radius * 0.82) * sin(needleRad),
    );

    // Needle shadow
    canvas.drawLine(
      center,
      needleEnd,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    // Needle
    canvas.drawLine(
      center,
      needleEnd,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Center dot
    canvas.drawCircle(center, 6, Paint()..color = color);
    canvas.drawCircle(center, 3, Paint()..color = Colors.white);
  }

  void _drawZoneArc(Canvas canvas, Offset center, double radius,
      double startDeg, double endDeg, Color color) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final startRad = (startDeg - 90) * pi / 180;
    final sweepRad = (endDeg - startDeg) * pi / 180;
    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      true,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _LeanAnglePainter oldDelegate) {
    return oldDelegate.angle != angle || oldDelegate.color != color;
  }
}
