import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:smart_helmet_app/models/journey_model.dart';
import 'package:smart_helmet_app/providers/journey_provider.dart';
import 'package:smart_helmet_app/services/journey_service.dart';
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
  JourneyData? _selectedJourney;
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

  // Turn Detection
  int sharpTurnCount = 0;
  int riskyTurnCount = 0;
  String currentTurnStatus = "Normal";
  Color statusColor = Colors.green;

  // Historical data for graph
  List<double> gyroZHistory = [];
  final int maxHistoryLength = 50;

  // Thresholds
  final double sharpTurnThreshold = 100.0;
  final double riskyTurnThreshold = 150.0;

  // Bluetooth Connection
  BluetoothConnection? _connection;
  bool isConnected = false;
  bool isConnecting = false;
  String connectionStatus = "Disconnected";
  String _dataBuffer = "";
  static const String targetDeviceName = "SmartHelmet_ESP32";

// Firestore
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSaving = false;
  
  // Risky Events Tracking (ONLY risky events saved to Firebase)
  String? _currentRideId;  // Generated when ride starts
  int _riskyEventsSavedCount = 0;
  List<Map<String, dynamic>> _riskyEventsThisRide = [];  // In-memory list for visualization
  
  // Current GPS state
  double currentSpeed = 0.0;
  double currentLat = 0.0;
  double currentLng = 0.0;

  // Distance tracking
  double totalDistanceKm = 0.0;
  double? lastLat;
  double? lastLng;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _requestPermissions();
    _loadJourneyHistory();

    // Check if a completed journey was passed (ride just ended)
    if (widget.completedJourney != null) {
      _showRideSummary = true;
      _completedRide = widget.completedJourney;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _disconnect();
    super.dispose();
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading journeys: $e')),
        );
      }
    }
  }

  // Request Bluetooth permissions
  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
  }

  // Scan and connect to device
  // ⚠️ UPDATED: Scan and connect with better error handling
  Future<void> _scanAndConnect() async {
    if (!mounted) return;

    setState(() {
      isConnecting = true;
      connectionStatus = "Checking Bluetooth...";
    });

    try {
      // Check if Bluetooth is enabled
      bool? isEnabled = await FlutterBluetoothSerial.instance.isEnabled;

      if (isEnabled == null || !isEnabled) {
        if (!mounted) return;
        setState(() {
          connectionStatus = "Bluetooth is OFF. Please enable it.";
          isConnecting = false;
        });

        // Show dialog to enable Bluetooth
        bool? turnOn = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Bluetooth Disabled'),
            content: const Text(
                'Bluetooth is turned off. Would you like to enable it?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Enable'),
              ),
            ],
          ),
        );

        if (turnOn == true) {
          await FlutterBluetoothSerial.instance.requestEnable();
          await Future.delayed(const Duration(seconds: 2));
        } else {
          return;
        }
      }

      setState(() => connectionStatus = "Scanning for devices...");

      // Get bonded devices
      List<BluetoothDevice> bondedDevices = [];
      try {
        bondedDevices =
            await FlutterBluetoothSerial.instance.getBondedDevices();
        print('Found ${bondedDevices.length} paired devices'); // Debug
      } catch (e) {
        print('Error getting bonded devices: $e');
        if (!mounted) return;
        setState(() {
          connectionStatus = "Error accessing Bluetooth: $e";
          isConnecting = false;
        });
        return;
      }

      // Find target device
      BluetoothDevice? targetDevice;
      for (BluetoothDevice device in bondedDevices) {
        print('Found device: ${device.name} - ${device.address}'); // Debug
        if (device.name == targetDeviceName) {
          targetDevice = device;
          break;
        }
      }

      // If not found, show device selection
      if (targetDevice == null) {
        if (!mounted) return;
        targetDevice = await _showDeviceSelectionDialog(bondedDevices);

        if (targetDevice == null) {
          if (!mounted) return;
          setState(() {
            connectionStatus = "No device selected";
            isConnecting = false;
          });
          return;
        }
      }

      if (!mounted) return;
      setState(
          () => connectionStatus = "Connecting to ${targetDevice!.name}...");

      print('Attempting to connect to: ${targetDevice.address}'); // Debug

      // Connect with timeout
      BluetoothConnection connection;
      try {
        connection = await BluetoothConnection.toAddress(targetDevice.address)
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        print('Connection timeout or error: $e'); // Debug
        if (!mounted) return;
        setState(() {
          connectionStatus = "Connection timeout. Try again.";
          isConnected = false;
          isConnecting = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _connection = connection;
        isConnected = true;
        isConnecting = false;
        connectionStatus = "Connected ✓";
      });

      print('Successfully connected!'); // Debug

      // Listen to incoming data
      _connection!.input!.listen(
        (Uint8List data) {
          _handleIncomingData(data);
        },
        onDone: () {
          print('Connection closed'); // Debug
          if (mounted) {
            setState(() {
              isConnected = false;
              connectionStatus = "Disconnected";
            });
          }
        },
        onError: (error) {
          print('Connection error: $error'); // Debug
          if (mounted) {
            setState(() {
              isConnected = false;
              connectionStatus = "Connection error";
            });
          }
        },
      );
    } catch (e) {
      print('General connection error: $e'); // Debug
      if (!mounted) return;
      setState(() {
        connectionStatus = "Failed: ${e.toString().substring(0, 50)}...";
        isConnected = false;
        isConnecting = false;
      });
    }
  }

  // Show dialog to select a Bluetooth device
  Future<BluetoothDevice?> _showDeviceSelectionDialog(
      List<BluetoothDevice> bondedDevices) async {
    return showDialog<BluetoothDevice>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Bluetooth Device'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paired Devices:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (bondedDevices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'No paired devices found.\n\n'
                      'Please pair your ESP32 first:\n'
                      '1. Go to Android Settings → Bluetooth\n'
                      '2. Find "SmartHelmet_ESP32"\n'
                      '3. Tap to pair',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: bondedDevices.length,
                      itemBuilder: (context, index) {
                        BluetoothDevice device = bondedDevices[index];
                        return ListTile(
                          leading: const Icon(Icons.bluetooth),
                          title: Text(device.name ?? 'Unknown Device'),
                          subtitle: Text(device.address),
                          trailing: device.name == targetDeviceName
                              ? const Icon(Icons.star, color: Colors.amber)
                              : null,
                          onTap: () => Navigator.of(context).pop(device),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Open system Bluetooth settings
                await FlutterBluetoothSerial.instance.openSettings();
              },
              child: const Text('Open Bluetooth Settings'),
            ),
          ],
        );
      },
    );
  }

  void _handleIncomingData(Uint8List data) {
    _dataBuffer += utf8.decode(data);
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
      print('Error parsing Data: $e');
      print('Raw data: $jsonString');
    }
  }

  Future<void> _disconnect() async {
    try {
      await _connection?.finish();
    } catch (e) {
      print('Disconnect error: $e');
    }
    if (!mounted) return;
    setState(() {
      _connection = null;
      isConnected = false;
      connectionStatus = "Disconnected";
    });
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

    // ─── Calculate turn status FIRST ────────────────────────────────
    double turnRate = imuData['gyroZ']!.abs();
    String newTurnStatus = "Normal";
    Color newStatusColor = Colors.green;
    String? eventType; // null = no risky event

    if (turnRate > riskyTurnThreshold) {
      newTurnStatus = "RISKY TURN!";
      newStatusColor = Colors.red;
      eventType = 'risky_turn';  // HIGH severity
      riskyTurnCount++;
    } else if (turnRate > sharpTurnThreshold) {
      newTurnStatus = "Sharp Turn";
      newStatusColor = Colors.orange;
      eventType = 'sharp_turn';  // MODERATE severity
      sharpTurnCount++;
    }

    // ─── ONLY SAVE RISKY EVENTS (not normal readings) ───────────────
    if (eventType != null && imuData['gyroZ'] != null) {
      _saveRiskyEventOnly(
        imuData,
        speed,
        lat,
        lng,
        eventType, // 'risky_turn' or 'sharp_turn'
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

      gyroZHistory.add(gyroZ.abs());
      if (gyroZHistory.length > maxHistoryLength) {
        gyroZHistory.removeAt(0);
      }

      currentTurnStatus = newTurnStatus;
      statusColor = newStatusColor;

      // GPS processing remains the same
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
        }
      }

      // Provider turn events (unchanged)
      if (journeyProvider.isJourneyActive) {
        if (eventType == 'risky_turn') {
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

  // ============================================================
  // START/END RIDE - Initialize and clear ride tracking
  // ============================================================
  void _startNewRide() {
    _currentRideId = DateTime.now().millisecondsSinceEpoch.toString();
    _riskyEventsSavedCount = 0;
    _riskyEventsThisRide = [];
    sharpTurnCount = 0;
    riskyTurnCount = 0;
    totalDistanceKm = 0.0;
    debugPrint("🚀 New ride started: $_currentRideId");
  }

  void _endCurrentRide() {
    debugPrint("🏁 Ride ended: $_currentRideId | Risky events saved: $_riskyEventsSavedCount");
    // Events remain in _riskyEventsThisRide for visualization
  }

  // ============================================================
  // SAVE ONLY RISKY EVENTS TO FIREBASE
  // ============================================================
  Future<void> _saveRiskyEventOnly(
    Map<String, double> imu,
    double speed,
    double lat,
    double lng,
    String eventType, // 'risky_turn', 'sharp_turn', 'harsh_brake'
  ) async {
    if (_isSaving) return;
    if (_currentRideId == null) {
      _startNewRide(); // Auto-start if not already started
    }

    setState(() => _isSaving = true);

    final now = DateTime.now();
    final turnRate = imu['gyroZ']?.abs() ?? 0.0;

    try {
      final eventData = {
        // Ride identification
        "rideId": _currentRideId,
        "eventNumber": _riskyEventsSavedCount + 1,
        
        // Timestamp
        "timestamp": now.toIso8601String(),
        "createdAt": FieldValue.serverTimestamp(),
        
        // Event classification
        "eventType": eventType,
        "severity": eventType == 'risky_turn' ? 'high' : 'moderate',
        
        // IMU data at event
        "gyroX": imu['gyroX'],
        "gyroY": imu['gyroY'],
        "gyroZ": imu['gyroZ'],
        "turnRateDegPerSec": turnRate,
        "accelX": imu['accelX'],
        "accelY": imu['accelY'],
        "accelZ": imu['accelZ'],
        
        // GPS location of event
        "latitude": lat,
        "longitude": lng,
        "location": GeoPoint(lat, lng),
        "speedKmh": speed,
        
        // Running totals at this point
        "sharpTurnsTotal": sharpTurnCount,
        "riskyTurnsTotal": riskyTurnCount,
        "totalDistanceKm": totalDistanceKm,
      };

      // Save to Firebase 'risky_events' collection
      final docRef = await _firestore.collection("risky_events").add(eventData);
      
      // Also keep in memory for end-of-ride visualization
      _riskyEventsThisRide.add({
        ...eventData,
        "docId": docRef.id,
      });
      
      _riskyEventsSavedCount++;
      
      debugPrint("🚨 RISKY EVENT #$_riskyEventsSavedCount saved → Type: $eventType | Turn: ${turnRate.toStringAsFixed(1)}°/s | ID: ${docRef.id}");
      
    } catch (e) {
      debugPrint("❌ Firebase risky event save error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save risky event: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
        title: const Text('Risk Assessment'),
        backgroundColor: Colors.blue[700],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.history), text: 'Journey History'),
            Tab(icon: Icon(Icons.sensors), text: 'Live Monitoring'),
          ],
        ),
        actions: [
          if (_tabController.index == 1)
            IconButton(
              icon: Icon(
                  isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
              onPressed: isConnected ? _disconnect : _scanAndConnect,
              tooltip: isConnected ? 'Disconnect' : 'Connect',
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

          // Risky Events Indicator (shows only when events detected)
          if (_isSaving || _riskyEventsSavedCount > 0)
            Positioned(
              bottom: 24,
              right: 24,
              child: Card(
                color: _isSaving 
                    ? Colors.orange[700] 
                    : (_riskyEventsSavedCount > 0 ? Colors.red[700] : Colors.green[700]),
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isSaving)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isSaving 
                                ? "Saving risky event..." 
                                : "🚨 $_riskyEventsSavedCount Risky Events",
                            style: const TextStyle(
                              color: Colors.white, 
                              fontSize: 13, 
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_currentRideId != null && !_isSaving)
                            Text(
                              "Ride: ${_currentRideId!.substring(0, 8)}...",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8), 
                                fontSize: 10,
                              ),
                            ),
                        ],
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
                  label: const Text('View All Journeys'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
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
                          size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No journeys recorded yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start a journey from Home Dashboard',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 24),
                      // ADD THIS: Test with dummy data button
                      ElevatedButton.icon(
                        onPressed: _showDummyReport,
                        icon: const Icon(Icons.science),
                        label: const Text('View Sample Report'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // ADD THIS: Test button at top of list
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton.icon(
                        onPressed: _showDummyReport,
                        icon: const Icon(Icons.science),
                        label: const Text('View Sample Report'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[600],
                          foregroundColor: Colors.white,
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

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      child: InkWell(
        onTap: () => _showJourneyDetails(journey),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.navigation, color: Colors.blue[700], size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          journey.destination ?? 'Unknown Destination',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          DateFormat('MMM dd, yyyy • HH:mm')
                              .format(journey.startTime),
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  _getRiskBadge(journey),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn(
                    Icons.route,
                    '${journey.totalDistance.toStringAsFixed(1)} km',
                    'Distance',
                  ),
                  _buildStatColumn(
                    Icons.timer,
                    '${duration.inMinutes} min',
                    'Duration',
                  ),
                  _buildStatColumn(
                    Icons.turn_sharp_right,
                    '${journey.sharpTurns}',
                    'Sharp',
                    Colors.orange,
                  ),
                  _buildStatColumn(
                    Icons.warning,
                    '${journey.riskyTurns}',
                    'Risky',
                    Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getRiskBadge(JourneyData journey) {
    final totalTurns = journey.sharpTurns + journey.riskyTurns;
    Color color;
    String label;

    if (journey.riskyTurns > 5 || totalTurns > 15) {
      color = Colors.red;
      label = 'HIGH RISK';
    } else if (journey.riskyTurns > 2 || totalTurns > 8) {
      color = Colors.orange;
      label = 'MODERATE';
    } else {
      color = Colors.green;
      label = 'LOW RISK';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildStatColumn(IconData icon, String value, String label,
      [Color? color]) {
    return Column(
      children: [
        Icon(icon, size: 24, color: color ?? Colors.grey[700]),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.black,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
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
  void _loadDummyHistory() {
    setState(() {
      _journeyHistory = DummyJourneyData.getSampleJourneyHistory();
      _isLoadingHistory = false;
    });
  }

  // Live Monitoring Tab
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
          _buildGyroscopeCard(),
          const SizedBox(height: 16),
          _buildAccelerometerCard(),
          const SizedBox(height: 16),
          _buildTurnRateGraph(),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _resetCounters,
            icon: const Icon(Icons.refresh),
            label: const Text('Reset Counters'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
          ),
        ],
      ),
    );
  }

  // Keep all existing build methods for live monitoring
  Widget _buildConnectionCard() {
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
                            const Text('ESP32 Connection',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(
                              connectionStatus,
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
                if (!isConnected && !isConnecting)
                  ElevatedButton.icon(
                    onPressed: _scanAndConnect,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (isConnecting)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      color: statusColor.withOpacity(0.2),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(_getStatusIcon(), size: 48, color: statusColor),
            const SizedBox(height: 12),
            Text(currentTurnStatus,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: statusColor)),
            const SizedBox(height: 8),
            Text('Turn Rate: ${gyroZ.abs().toStringAsFixed(1)}°/s',
                style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon() {
    if (currentTurnStatus == "RISKY TURN!") return Icons.warning_amber;
    if (currentTurnStatus == "Sharp Turn") return Icons.turn_sharp_right;
    return Icons.check_circle;
  }

  Widget _buildStatisticsRow() {
    return Row(
      children: [
        Expanded(
            child: _buildStatCard('Sharp Turns', sharpTurnCount.toString(),
                Icons.turn_right, Colors.orange)),
        const SizedBox(width: 16),
        Expanded(
            child: _buildStatCard('Risky Turns', riskyTurnCount.toString(),
                Icons.warning, Colors.red)),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildGyroscopeCard() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Gyroscope (°/s)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildDataRow('X-axis (Roll)', gyroX, Colors.red),
            _buildDataRow('Y-axis (Pitch)', gyroY, Colors.green),
            _buildDataRow('Z-axis (Yaw)', gyroZ, Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildAccelerometerCard() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Accelerometer (m/s²)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildDataRow('X-axis', accelX, Colors.red),
            _buildDataRow('Y-axis', accelY, Colors.green),
            _buildDataRow('Z-axis', accelZ, Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Row(
            children: [
              Container(
                width: 100,
                height: 20,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FractionallySizedBox(
                  widthFactor: (value.abs() / 200).clamp(0.0, 1.0),
                  alignment: Alignment.centerLeft,
                  child: Container(
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: Text(
                  value.toStringAsFixed(2),
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: color),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTurnRateGraph() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Turn Rate History',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: CustomPaint(
                size: Size.infinite,
                painter: GraphPainter(
                    data: gyroZHistory,
                    sharpThreshold: sharpTurnThreshold,
                    riskyThreshold: riskyTurnThreshold),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegend('Normal', Colors.green),
                const SizedBox(width: 12),
                _buildLegend('Sharp', Colors.orange),
                const SizedBox(width: 12),
                _buildLegend('Risky', Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(String label, Color color) {
    return Row(
      children: [
        Container(width: 16, height: 3, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  void _resetCounters() {
    setState(() {
      sharpTurnCount = 0;
      riskyTurnCount = 0;
      gyroZHistory.clear();
    });
  }

  // ⚠️ NEW: GPS Data Card
  Widget _buildGPSCard() {
    final hasFix = currentLat != 0.0 && currentLng != 0.0;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasFix ? Icons.gps_fixed : Icons.gps_not_fixed,
                  color: hasFix ? Colors.green : Colors.grey,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'GPS Data',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildGPSRow('Latitude',
                currentLat != 0.0 ? currentLat.toStringAsFixed(6) : 'No Fix'),
            _buildGPSRow('Longitude',
                currentLng != 0.0 ? currentLng.toStringAsFixed(6) : 'No Fix'),
            _buildGPSRow(
                'Speed',
                currentSpeed != 0.0
                    ? '${currentSpeed.toStringAsFixed(1)} km/h'
                    : '0.0 km/h'),
            _buildGPSRow(
                'Distance', '${totalDistanceKm.toStringAsFixed(2)} km'),
            _buildGPSRow('Status', hasFix ? '✓ GPS Fix' : '✗ Searching...'),
          ],
        ),
      ),
    );
  }

// ⚠️ NEW: GPS Row Builder
  Widget _buildGPSRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

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

// Graph Painter (keep existing)
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
      ..color = Colors.orange.withOpacity(0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final riskyPaint = Paint()
      ..color = Colors.red.withOpacity(0.3)
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
