// ================================================
// UPDATED Member1Page.dart
// ================================================
// I have added a professional "Weekly Report" button in the AppBar.
// Clicking it navigates to the new separate WeeklyReportPage (see code below).
// No other changes were made to your existing logic.

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../services/bluetooth_manager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smart_helmet_app/providers/sensor_data_provider.dart';
import 'package:smart_helmet_app/providers/ride_session_provider.dart';
import 'package:smart_helmet_app/providers/emotion_provider.dart';
// If you have auth service:
import '../../../../services/auth_service.dart';

// NEW IMPORT (create the file in the same folder or adjust path)
import 'weekly_report_page.dart'; // ← ADD THIS LINE

class Member1Page extends StatefulWidget {
  const Member1Page({super.key});

  @override
  State<Member1Page> createState() => _Member1PageState();
}

class _Member1PageState extends State<Member1Page>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  static const String deviceName = "SmartWatch_ESP32";

  String status = "Waiting...";
  String errorMessage = "";
  StreamSubscription? _dataSubscription;
  StreamSubscription? _todaySummarySubscription;
  int reconnectAttempts = 0;
  final int maxReconnectAttempts = 3;

  // Sensor values
  double heartRate = 0.0;
  double bodyTemperature = 0.0;
  String riskLevel = "Unknown";
  Color riskColor = Colors.grey;

  Interpreter? _interpreter;

  // Emotional state (placeholder)
  String frustrationState = "Neutral";
  String frustrationEmoji = "😐";

  // Chart data
  final int maxDataPoints = 30;
  final List<FlSpot> heartRateSpots = [];
  final List<FlSpot> temperatureSpots = [];
  double _currentX = 0.0;

  // Firestore save throttling
  // Firestore save throttling - High frequency for real-time dashboard sync
  DateTime? _lastSavedTime;
  final Duration _saveInterval = const Duration(milliseconds: 500);

  // Firestore
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSaving = false;

  // Historical summary for TODAY
  double _todayAvgHR = 0;
  double _todayAvgTemp = 0;
  int _todayReadings = 0;
  bool _isLoadingToday = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadModel();
    _startLocationTracking();

    // Important: delay connection until first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();

      // Optional safety retry if still not connected after ~8 seconds

      Future.delayed(const Duration(seconds: 8), () {
        if (mounted &&
            !context.read<BluetoothManager>().isConnected(deviceName) &&
            heartRate == 0.0) {
          _autoConnect(isRetry: true);
        }
      });

      _initTodaySummaryListener();
    });
  }

  Future<void> _loadModel() async {
    try {
      _interpreter =
          await Interpreter.fromAsset('assets/heart_risk_model.tflite');
      debugPrint("TFLite model loaded successfully");
    } catch (e) {
      debugPrint("Error loading model: $e");
      if (mounted)
        setState(() => errorMessage = "Failed to load prediction model");
    }
  }

  // ────────────────────────────────────────────────
// Auto-connect + retry logic
// ────────────────────────────────────────────────

  Future<void> _autoConnect({bool isRetry = false}) async {
    final btManager = context.read<BluetoothManager>();

    if (btManager.isConnected(deviceName)) {
      if (mounted) {
        setState(() {
          status = "Connected (already detected)";
          errorMessage = "";
        });
      }
      _subscribeToData();
      return;
    }

    if (!mounted) return;

    setState(() {
      status = isRetry ? "Reconnecting..." : "Auto-connecting $deviceName...";
      errorMessage = " ";
    });

    try {
      final result = await btManager.connectToDevice(deviceName);

      if (!mounted) return;

      setState(() {
        status = result;
      });

      if (btManager.isConnected(deviceName)) {
        reconnectAttempts = 0;
        _subscribeToData();
        setState(() {
          status = "Connected • SmartWatch";
          errorMessage = "";
        });
      } else {
        _handleConnectionFailure(result);
      }
    } catch (e) {
      _handleConnectionFailure("Error: $e");
    }
  }

  void _handleConnectionFailure(String reason) {
    if (reconnectAttempts < maxReconnectAttempts) {
      reconnectAttempts++;
      setState(() {
        status = "Retry ${reconnectAttempts}/${maxReconnectAttempts}...";
        errorMessage = "$reason\nTrying again in a moment...";
      });
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) _autoConnect(isRetry: true);
      });
    } else {
      setState(() {
        status = "Connection failed";
        errorMessage =
            "Could not connect after $maxReconnectAttempts attempts.\n"
            "Make sure:\n"
            "• Device is powered on\n"
            "• Bluetooth is enabled\n"
            "• Device is paired";
      });
    }
  }

  Future<void> _init() async {
    final btManager = context.read<BluetoothManager>();
    await btManager.requestPermissions();
    if (btManager.isConnected(deviceName)) {
      _subscribeToData();
      setState(() => status = "Connected");
    }
  }

  void _subscribeToData() {
    final btManager = context.read<BluetoothManager>();

    // Flexible device discovery
    String? deviceToUse;
    if (btManager.isConnected(deviceName)) {
      deviceToUse = deviceName;
    } else {
      final connectedDevices = btManager.getConnectedDevices();
      debugPrint("Member1Page: Checking connected devices: $connectedDevices");
      for (final dev in connectedDevices) {
        // Look for any ESP32, SmartWatch, or Helmet device
        if (dev.toLowerCase().contains('esp') ||
            dev.toLowerCase().contains('watch') ||
            dev.toLowerCase().contains('helmet') ||
            dev.toLowerCase().contains('hr')) {
          deviceToUse = dev;
          break;
        }
      }
      // Fallback to first connected device if still null
      if (deviceToUse == null && connectedDevices.isNotEmpty) {
        deviceToUse = connectedDevices.first;
      }
    }

    if (deviceToUse == null) {
      debugPrint(
          "Member1Page: No suitable connected device found to subscribe");
      return;
    }

    final dataStream = btManager.getDataStream(deviceToUse);
    if (dataStream == null) {
      debugPrint("Member1Page: Could not get data stream for $deviceToUse");
      return;
    }

    String buffer = '';
    _dataSubscription?.cancel();
    _dataSubscription = dataStream.listen(
      (data) {
        if (!mounted) return;
        buffer += String.fromCharCodes(data);
        List<String> lines = buffer.split('\n');
        if (lines.length > 1) {
          for (int i = 0; i < lines.length - 1; i++) {
            String line = lines[i].trim();
            if (line.isNotEmpty) _parseAndUpdateData(line);
          }
          buffer = lines.last;
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() => errorMessage = "Stream error ($deviceToUse): $e");
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            status = "Disconnected";
            riskLevel = "Unknown";
            riskColor = Colors.grey;
          });

          // Auto-reconnect attempt
          if (reconnectAttempts < maxReconnectAttempts) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) _autoConnect(isRetry: true);
            });
          }
        }
      },
    );
    debugPrint("✓ Subscribed to $deviceToUse data stream in Member1Page");
    if (mounted) {
      setState(() {
        status = "Connected • $deviceToUse";
      });
    }
  }

  // Add near the top of the class
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  bool _locationServiceEnabled = false;
  LocationPermission _permission = LocationPermission.denied;

// Add this method (call it in initState)
  Future<void> _startLocationTracking() async {
    // Check if location services are enabled
    _locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!_locationServiceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled')),
        );
      }
      return;
    }

    // Check/request permission
    _permission = await Geolocator.checkPermission();
    if (_permission == LocationPermission.denied) {
      _permission = await Geolocator.requestPermission();
      if (_permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
        }
        return;
      }
    }

    if (_permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Location permissions permanently denied')),
        );
      }
      return;
    }

    // Start listening to position updates
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // update every 10 meters
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });
  }

  double _getEmotionRiskMultiplier(String emotion) {
    final lower = emotion.toLowerCase();
    if (lower.contains('stressed') ||
        lower.contains('frustrated') ||
        lower.contains('angry') ||
        lower.contains('anxious')) {
      return 1.6; // significant acute trigger
    }
    if (lower.contains('neutral')) {
      return 1.0;
    }
    if (lower.contains('relaxed') ||
        lower.contains('calm') ||
        lower.contains('happy')) {
      return 0.75; // protective effect
    }
    return 1.0; // default
  }

  // Vibration Filter / Moving Average Array
  final List<double> _hrBuffer = [];
  final int _hrBufferSize = 5;

  void _parseAndUpdateData(String jsonString) {
    try {
      final json = jsonDecode(jsonString);
      final double rawHr = (json['hr'] as num?)?.toDouble() ?? 0.0;
      final double temp = (json['temp'] as num?)?.toDouble() ?? 0.0;

      // --- 1. Vibration Filter: Moving Average for Heart Rate ---
      _hrBuffer.add(rawHr);
      if (_hrBuffer.length > _hrBufferSize) {
        _hrBuffer.removeAt(0);
      }
      final double hr = _hrBuffer.reduce((a, b) => a + b) / _hrBuffer.length;

      // Inside _parseAndUpdateData or after setState
      final sensorProvider =
          Provider.of<SensorDataProvider>(context, listen: false);
      sensorProvider.updateHeartRate(hr.toInt());
      sensorProvider.updateTemperature(temp);
      sensorProvider.updateDangerAlert(hr > 110 || temp > 38.0);

      debugPrint(
          "Sent to provider → HR (Smoothed): $hr, Temp: $temp, Danger: ${hr > 110 || temp > 38.0}");

      if (mounted) {
        setState(() {
          heartRate = hr;
          bodyTemperature = temp;

          _currentX += 1.0;
          heartRateSpots.add(FlSpot(_currentX, hr));
          temperatureSpots.add(FlSpot(_currentX, temp));

          if (heartRateSpots.length > maxDataPoints) {
            heartRateSpots.removeAt(0);
            temperatureSpots.removeAt(0);
          }
        });
      }

      _predictWithTFLite(hr, temp);
      // Real-time save: ONLY when a ride is active
      final rideProvider =
          Provider.of<RideSessionProvider>(context, listen: false);
      if (rideProvider.isRideActive) {
        // FIXED: These variables must be at CLASS level (moved from inside method)
        // Add these two lines at the TOP of _Member1PageState class:
        // DateTime? _lastSavedTime;
        // final Duration _saveInterval = const Duration(seconds: 10);

        if (hr > 0 && temp > 0) {
          final now = DateTime.now();
          if (_lastSavedTime == null ||
              now.difference(_lastSavedTime!) >= _saveInterval) {
            _saveToFirestore(hr, temp);
            _lastSavedTime = now;
          }
        }
      }
    } catch (e) {
      debugPrint("Parse error: $e | Raw: $jsonString");
    }
  }

  Future<void> _saveToFirestore(double hr, double temp) async {
    final rideProvider =
        Provider.of<RideSessionProvider>(context, listen: false);

    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final userId = auth.userId;

      if (userId == null) {
        debugPrint("❌ No logged-in user — cannot save to Firestore");
        return;
      }

      final String isoTimestamp = DateTime.now().toIso8601String();

      // Standardize fields and add common aliases for robustness
      final Map<String, dynamic> data = {
        "timestamp": isoTimestamp,
        "heartRate": hr,
        "heart_rate": hr, // Alias 1
        "bpm": hr, // Alias 2
        "bodyTemperature": temp,
        "body_temperature": temp, // Alias 1
        "temp": temp, // Alias 2
        "riskLevel": riskLevel,
        "riskColor":
            "#${riskColor.value.toRadixString(16).padLeft(8, '0').substring(2)}",
        "userId": userId,
        "uid": userId, // Alias for UID
        "deviceName": deviceName,
        "createdAt": FieldValue.serverTimestamp(),
        "location": const GeoPoint(7.2000, 79.8730),
      };

      // Add ride metadata ONLY if a ride is active
      if (rideProvider.isRideActive && rideProvider.currentRideId != null) {
        data["rideId"] = rideProvider.currentRideId!;
        data["rideStartLocation"] = rideProvider.startLocation;
        data["rideDestination"] = rideProvider.destinationName;
        data["rideEndLocation"] = rideProvider.endLocation;
      }

      // Real-time location of THIS reading
      if (_currentPosition != null) {
        data["currentLocation"] =
            GeoPoint(_currentPosition!.latitude, _currentPosition!.longitude);
      }

      await _firestore.collection("health_readings").add(data);
      debugPrint("✅ Health reading saved: HR=$hr, Temp=$temp (User: $userId)");

      // Real-time feedback for the user
      if (mounted) {
        final sensorProvider =
            Provider.of<SensorDataProvider>(context, listen: false);
        // We can use a temporary flag or just assume success if no error
      }
    } catch (e) {
      debugPrint("❌ Firestore save error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Cloud Sync Error: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _predictWithTFLite(double hr, double temp) {
    if (hr == 0 || temp == 0 || _interpreter == null) {
      _fallbackLocalRisk(hr, temp);
      return;
    }

    try {
      // ────────────────────────────────────────────────
      // 1. Get current emotional state from provider
      // ────────────────────────────────────────────────
      final emotionProvider = Provider.of<EmotionProvider>(
        context,
        listen: false,
      );
      final currentEmotion = emotionProvider.stressState.emotion;
      final emotionEmoji = emotionProvider.stressState.emoji ?? "😐";

      final emotionMultiplier = _getEmotionRiskMultiplier(currentEmotion);

      // ────────────────────────────────────────────────
      // 2. User Profile (still mocked — replace with real DB fetch later)
      // ────────────────────────────────────────────────
      double age = 30.0;
      double gender = 0.0; // 0 = Male, 1 = Female
      double weight = 75.0; // kg
      double height = 1.75; // meters

      // ────────────────────────────────────────────────
      // 3. Feature Engineering
      // ────────────────────────────────────────────────
      double derivedBMI = weight / (height * height);

      // Crude HRV proxy
      double derivedHRV = 60.0;
      if (hr > 100 || hr < 60) derivedHRV = 30.0;

      // Scalers (from your original training pipeline)
      List<double> means = [
        99.70281639014169,
        37.07289512301389,
        50.93246,
        0.49886,
        27.610900222144865,
        47.90562916450637
      ];
      List<double> scales = [
        28.799757731731674,
        1.1095593883726716,
        19.336496464016147,
        0.5000000000147614,
        8.52047814467008,
        17.265580269863933
      ];

      double s_hr = (hr - means[0]) / scales[0];
      double s_temp = (temp - means[1]) / scales[1];
      double s_age = (age - means[2]) / scales[2];
      double s_gender = (gender - means[3]) / scales[3];
      double s_bmi = (derivedBMI - means[4]) / scales[4];
      double s_hrv = (derivedHRV - means[5]) / scales[5];

      // Input tensor shape: [1, 6]
      var input = [
        [s_hr, s_temp, s_age, s_gender, s_bmi, s_hrv]
      ];
      var output = List.filled(1, [0.0]);

      _interpreter!.run(input, output);

      double baseProbability = output[0][0].clamp(0.0, 1.0);

      // ────────────────────────────────────────────────
      // 4. Apply emotion adjustment
      // ────────────────────────────────────────────────
      final adjustedProbability =
          (baseProbability * emotionMultiplier).clamp(0.0, 1.0);
      final int riskPercentage = (adjustedProbability * 100).round();

      String newRisk;
      Color newColor;

      if (adjustedProbability > 0.75) {
        newRisk = "High Risk";
        newColor = const Color(0xFFFF3B30);
      } else if (adjustedProbability > 0.45) {
        newRisk = "Medium Risk";
        newColor = const Color(0xFFFF9500);
      } else {
        newRisk = "Normal";
        newColor = const Color(0xFF34C759);
      }

      if (mounted) {
        setState(() {
          riskLevel =
              "$newRisk ($riskPercentage%) • $currentEmotion $emotionEmoji";
          riskColor = newColor;
        });
      }
    } catch (e) {
      debugPrint("TFLite inference error: $e");
      _fallbackLocalRisk(hr, temp);
    }
  }

// ────────────────────────────────────────────────
// Helper: Emotion → Acute Risk Multiplier
// Values inspired by epidemiological literature:
//   - Anger/frustration/anxiety → ~1.4–2.0× acute risk
//   - Relaxed/calm → protective (~0.7–0.9)
// ────────────────────────────────────────────────

  void _fallbackLocalRisk(double hr, double temp) {
    String newRisk = "Normal";
    Color newColor = const Color(0xFF34C759);
    int riskPercentage = 15;

    // High Risk: HR > 120 or < 40 OR (Temp > 38.0 AND high HR)
    if (hr > 120 || hr < 40 || (temp > 38.0 && hr > 100)) {
      newRisk = "High Risk";
      newColor = const Color(0xFFFF3B30);
      riskPercentage = 90;
    }
    // Medium Risk: HR (100-120 or 50-59) OR Temp (37.3-38.0)
    else if ((hr >= 100 && hr <= 120) ||
        (hr >= 50 && hr <= 59) ||
        (temp >= 37.3 && temp <= 38.0)) {
      newRisk = "Medium Risk";
      newColor = const Color(0xFFFF9500);
      riskPercentage = 60;
    }
    // Normal: HR (60-100) AND Temp (36.1-37.2)
    else if (hr >= 60 && hr <= 100 && temp >= 36.1 && temp <= 37.2) {
      newRisk = "Normal";
      newColor = const Color(0xFF34C759);
      riskPercentage = 10;
    }

    if (mounted) {
      setState(() {
        riskLevel = "$newRisk ($riskPercentage%)";
        riskColor = newColor;
      });
    }
  }

  Future<void> connectToDevice() async {
    final btManager = context.read<BluetoothManager>();
    setState(() {
      status = "Connecting...";
      errorMessage = "";
    });

    try {
      final result = await btManager.connectToDevice(deviceName);
      if (!mounted) return;

      if (btManager.isConnected(deviceName)) {
        reconnectAttempts = 0;
        _subscribeToData();
        setState(() {
          status = "Connected";
          errorMessage = "";
        });
      } else {
        if (reconnectAttempts < maxReconnectAttempts) {
          reconnectAttempts++;
          await Future.delayed(const Duration(seconds: 3));
          connectToDevice();
        } else {
          setState(() {
            status = "Connection failed";
            errorMessage =
                "Failed after $maxReconnectAttempts attempts. Please check device.";
          });
        }
      }
    } catch (e) {
      setState(() {
        status = "Connection failed";
        errorMessage = "Error: $e";
      });
    }
  }

  Future<void> disconnectDevice() async {
    final btManager = context.read<BluetoothManager>();
    await btManager.disconnectDevice(deviceName);
    _dataSubscription?.cancel();

    setState(() {
      status = "Disconnected";
      heartRate = bodyTemperature = 0.0;
      riskLevel = "Unknown";
      riskColor = Colors.grey;
      heartRateSpots.clear();
      temperatureSpots.clear();
      _currentX = 0.0;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dataSubscription?.cancel();
    _todaySummarySubscription?.cancel();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final btManager = context.watch<BluetoothManager>();
    final isConnected = btManager.isConnected(deviceName);

    // ─── Read real emotional state from provider ───
    final emotionProvider = context.watch<EmotionProvider>();
    final currentEmotion = emotionProvider.state.emotion;
    final currentEmoji = emotionProvider.state.emoji;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: const Color(0xFF065aa7),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFFB9B9B9),
          indicatorColor: Colors.white,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.sensors), text: "Live Monitoring"),
            Tab(
                icon: Icon(Icons.analytics_outlined),
                text: "Vital health report"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLiveMonitoringTab(),
          const WeeklyReportPage(isEmbedded: true),
        ],
      ),
    );
  }

  Widget _buildLiveMonitoringTab() {
    final btManager = context.watch<BluetoothManager>();
    final isConnected = btManager.isConnected(deviceName);

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            if (!isConnected) _autoConnect();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConnectionStatus(isConnected),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: MedicalVitalCard(
                        title: "HEART RATE",
                        value:
                            heartRate > 0 ? heartRate.toInt().toString() : "--",
                        unit: "BPM",
                        percentage: heartRate.toInt(),
                        status: _getHRStatus(heartRate),
                        statusColor: _getStatusColor(_getHRStatus(heartRate)),
                        iconWidget: AnimatedHeartIcon(
                          color: Colors.red,
                          percentage: heartRate.toInt(),
                        ),
                        description: "Cardiovascular frequency in real-time.",
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MedicalVitalCard(
                        title: "BODY TEMP",
                        value: bodyTemperature > 0
                            ? bodyTemperature.toStringAsFixed(1)
                            : "--",
                        unit: "°C",
                        percentage: (bodyTemperature * 2.5).toInt(),
                        status: _getTempStatus(bodyTemperature),
                        statusColor:
                            _getStatusColor(_getTempStatus(bodyTemperature)),
                        iconWidget: AnimatedTempIcon(
                          color: const Color(0xFFF89E0A),
                          percentage: (bodyTemperature * 2.5).toInt(),
                        ),
                        description: "Core biological temperature stability.",
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                _buildOverallHealthStatusCard(),
                const SizedBox(height: 24),
                _buildTodaySummaryCard(),
                const SizedBox(height: 24),
                _buildPersonalizedRecommendations(),
                const SizedBox(height: 24),
                _buildEmotionalState(isConnected),
                const SizedBox(height: 24),
                const SizedBox(height: 20),
                //_buildRiskAssessment(),
                const SizedBox(height: 20),

                // Updated: now uses real emotion from provider
                _buildEmotionalState(isConnected),

                const SizedBox(height: 20),

                _buildVitalsChart(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
        if (_isSaving)
          Positioned(
            bottom: 24,
            right: 24,
            child: Card(
              color: Colors.black87,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Saving reading...",
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildConnectionStatus(bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isConnected ? Colors.white : const Color(0xFFFEF7E0),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color:
              isConnected ? const Color(0xFFE5E7EB) : const Color(0xFFFDE68A),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.sensors : Icons.sensors_off,
            color:
                isConnected ? const Color(0xFF34C759) : const Color(0xFFF59E0B),
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isConnected
                    ? const Color(0xFF1F2937)
                    : const Color(0xFF92400E),
              ),
            ),
          ),
          if (!isConnected)
            GestureDetector(
              onTap: () => _autoConnect(),
              child: const Text(
                "Reconnect",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D62ED),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Replace _buildConnectionControls() with this
  Widget _buildConnectionHeader(bool isConnected) {
    final btManager = context.watch<BluetoothManager>();
    final isConnected = btManager.isConnected(deviceName);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: isConnected ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isConnected
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
            if (errorMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline,
                        size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage,
                        style:
                            TextStyle(color: Colors.red.shade800, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!isConnected) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text("Retry Connection"),
                  onPressed: () => _autoConnect(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: const BorderSide(color: Colors.blue),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVitalCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: color,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    unit,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _calculateHealthScore() {
    int score = 100;

    // Temperature impact
    if (bodyTemperature > 37.5 || bodyTemperature < 36.0) {
      score -= 15;
    } else if (bodyTemperature > 38.5 || bodyTemperature < 35.0) {
      score -= 30;
    }
    Widget _buildEmotionalState(
        bool isConnected, String emotion, String emoji) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                "Emotional State",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Text(
                emoji,
                style: const TextStyle(fontSize: 64),
              ),
              const SizedBox(height: 12),
              Text(
                emotion,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isConnected
                    ? "Analyzing real-time signals..."
                    : "Connect EEG device to detect emotional state",
                style: const TextStyle(fontSize: 12, color: Colors.black38),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Risk level impact
    if (riskLevel.toLowerCase().contains('medium')) score -= 20;
    if (riskLevel.toLowerCase().contains('high')) score -= 40;

    return score.clamp(0, 100);
  }

  Widget _buildOverallHealthStatusCard() {
    final int score = _calculateHealthScore();
    final String statusLabel = score >= 85
        ? "OPTIMAL"
        : score >= 60
            ? "STABLE"
            : "CAUTION";
    final Color statusColor = score >= 85
        ? const Color(0xFF34C759)
        : score >= 60
            ? const Color(0xFF007AFF)
            : const Color(0xFFFF3B30);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF065aa7).withOpacity(0.05),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
            color: const Color(0xFF065aa7).withOpacity(0.12), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Overall Health Status",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Based on real-time biometrics",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 10,
                      backgroundColor: Colors.white,
                      color: statusColor,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "$score",
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1C1C1E),
                          height: 1,
                        ),
                      ),
                      const Text(
                        "SCORE",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      riskLevel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: riskColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getRiskDescription(riskLevel),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalizedRecommendations() {
    final List<Map<String, dynamic>> recommendations = [];

    if (heartRate > 100) {
      recommendations.add({
        "icon": Icons.air_rounded,
        "title": "Breathing Exercise",
        "tip":
            "High heart rate detected. Try deep breathing for 2 minutes to lower stress.",
        "color": Colors.blue,
      });
    }

    if (bodyTemperature > 37.5) {
      recommendations.add({
        "icon": Icons.local_drink_rounded,
        "title": "Hydration Alert",
        "tip":
            "Body temp is elevated. Drink chilled water to maintain regulation.",
        "color": Colors.orange,
      });
    }

    if (riskLevel.toLowerCase().contains('risk')) {
      recommendations.add({
        "icon": Icons.hotel_rounded,
        "title": "Rest Suggested",
        "tip":
            "Biometrics are showing instability. Stop your journey and take a 15-min break.",
        "color": Colors.red,
      });
    }

    recommendations.add({
      "icon": Icons.shield_rounded,
      "title": "Weekly Checkup",
      "tip": "Your health trends remain stable. Keep maintaining your routine!",
      "color": Colors.green,
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            "Personalized Recommendations",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1C1C1E),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 120, // Adjust height as needed
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: recommendations.length,
            itemBuilder: (context, index) {
              final rec = recommendations[index];
              return Container(
                width: 240,
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: rec["color"].withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(rec["icon"], color: rec["color"], size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            rec["title"],
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1C1C1E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            rec["tip"],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _initTodaySummaryListener() {
    final rawId = context.read<AuthService>().userId;
    if (rawId == null) return;

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    // Using a simpler query by userId and filtering by date in memory
    // This is more robust against index requirements and works in real-time
    _todaySummarySubscription = _firestore
        .collection("health_readings")
        .where("userId", isEqualTo: rawId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final todayDocs = snapshot.docs.where((doc) {
        final data = doc.data();
        DateTime? ts;

        // Robust timestamp parsing
        final dynamic createdAt = data['createdAt'];
        if (createdAt != null) {
          if (createdAt is Timestamp) {
            ts = createdAt.toDate();
          } else if (createdAt is String) {
            ts = DateTime.tryParse(createdAt);
          }
        }

        if (ts == null && data['timestamp'] != null) {
          ts = DateTime.tryParse(data['timestamp'].toString());
        }

        if (ts == null) return false;

        // Check if the timestamp belongs to TODAY
        return ts.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
            ts.isBefore(endOfDay.add(const Duration(seconds: 1)));
      }).toList();

      if (todayDocs.isEmpty) {
        setState(() {
          _todayAvgHR = 0;
          _todayAvgTemp = 0;
          _todayReadings = 0;
          _isLoadingToday = false;
        });
        return;
      }

      double sumHR = 0, sumTemp = 0;
      int hrCount = 0, tempCount = 0;

      for (var doc in todayDocs) {
        final data = doc.data();

        // Robust Heart Rate parsing (check all aliases)
        double hr = (data['heartRate'] as num?)?.toDouble() ??
            (data['heart_rate'] as num?)?.toDouble() ??
            (data['bpm'] as num?)?.toDouble() ??
            0.0;

        // Robust Temperature parsing (check all aliases)
        double temp = (data['bodyTemperature'] as num?)?.toDouble() ??
            (data['body_temperature'] as num?)?.toDouble() ??
            (data['temp'] as num?)?.toDouble() ??
            0.0;

        if (hr > 0) {
          sumHR += hr;
          hrCount++;
        }
        if (temp > 0) {
          sumTemp += temp;
          tempCount++;
        }
      }

      if (mounted) {
        setState(() {
          _todayAvgHR = hrCount > 0 ? sumHR / hrCount : 0;
          _todayAvgTemp = tempCount > 0 ? sumTemp / tempCount : 0;
          _todayReadings = todayDocs.length;
          _isLoadingToday = false;
        });
      }
    }, onError: (e) {
      debugPrint("Error in today summary listener: $e");
      if (mounted) setState(() => _isLoadingToday = false);
    });
  }

  Widget _buildTodaySummaryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: const Color(0xFF2D62ED).withOpacity(0.1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        onTap: () {
          _tabController.animateTo(1);
        },
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2D62ED).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.history_toggle_off_rounded,
              color: Color(0xFF2D62ED), size: 28),
        ),
        title: const Text(
          "Today's Average Log",
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8E8E93)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                _isLoadingToday
                    ? "Calculating..."
                    : "${_todayAvgHR.toInt()} BPM",
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1C1C1E)),
              ),
              const SizedBox(width: 12),
              Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                      color: Colors.grey, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Text(
                _isLoadingToday
                    ? "..."
                    : "${_todayAvgTemp.toStringAsFixed(1)}°C",
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2D62ED)),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded,
            color: Color(0xFF2D62ED), size: 16),
      ),
    );
  }

  String _getRiskDescription(String level) {
    switch (level.toLowerCase()) {
      case 'normal':
        return "All vitals are within safe medical ranges.";
      case 'medium risk':
        return "Elevated vitals detected. Monitor closely.";
      case 'high risk':
        return "CRITICAL: Immediate attention required.";
      default:
        return "Analyzing real-time sensor data...";
    }
  }

  Widget _buildRiskPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: riskColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        riskLevel.split('(')[0].trim(),
        style: TextStyle(
          color: riskColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // --- ENHANCED CHART CODE STARTS HERE ---

  Widget _buildEmotionalState(bool isConnected) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: const Color(0xFF2D62ED).withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D62ED).withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Emotional State",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1C1C1E),
                ),
              ),
              StatusPill(
                label: "Beta AI",
                color: const Color(0xFF2D62ED),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F7),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(frustrationEmoji,
                      style: const TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    frustrationState,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                  const Text(
                    "Physiological Correlation",
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8E8E93),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- ENHANCED CHART CODE STARTS HERE ---

  Widget _buildVitalsChart() {
    // Define professional colors
    final Color hrColor = const Color(0xFFFF4D4D);
    final Color tempColor = const Color(0xFF4D94FF);

    // 1. CALCULATE DYNAMIC MIN/MAX Y
    double minY = 0;
    double maxY = 100;

    if (heartRateSpots.isNotEmpty || temperatureSpots.isNotEmpty) {
      // Get all Y values from both lists
      final allYValues = [
        ...heartRateSpots.map((e) => e.y),
        ...temperatureSpots.map((e) => e.y)
      ];

      if (allYValues.isNotEmpty) {
        // Find the absolute min and max in the current data
        double dataMin =
            allYValues.reduce((curr, next) => curr < next ? curr : next);
        double dataMax =
            allYValues.reduce((curr, next) => curr > next ? curr : next);

        // Add "padding" so the line doesn't touch the very edge
        minY = (dataMin - 10)
            .clamp(0, double.infinity); // Ensure it doesn't go below 0
        maxY = dataMax + 20; // Add headroom at the top
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Real-time Analytics",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1C1C1E),
                        letterSpacing: -0.5),
                  ),
                  Text(
                    "High-fidelity sensor feed",
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF34C759).withOpacity(0.3))),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: Color(0xFF34C759), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    const Text("LIVE",
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF34C759),
                            letterSpacing: 1.0)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 220,
            child: heartRateSpots.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.query_stats,
                            size: 48, color: Colors.grey.shade200),
                        const SizedBox(height: 12),
                        Text("Waiting for medical signal...",
                            style: TextStyle(
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  )
                : LineChart(
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeInOutCubic,
                    LineChartData(
                      backgroundColor: Colors.transparent,
                      clipData: const FlClipData.all(),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 20,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey.shade100,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 35,
                            interval: (maxY - minY) > 100 ? 50 : 20,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toInt().toString(),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade400,
                                    fontWeight: FontWeight.bold),
                              );
                            },
                          ),
                        ),
                        bottomTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: heartRateSpots,
                          isCurved: true,
                          curveSmoothness: 0.35,
                          preventCurveOverShooting: true,
                          color: hrColor.withOpacity(0.8),
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                hrColor.withOpacity(0.2),
                                hrColor.withOpacity(0.0),
                              ],
                            ),
                          ),
                        ),
                        LineChartBarData(
                          spots: temperatureSpots,
                          isCurved: true,
                          curveSmoothness: 0.35,
                          preventCurveOverShooting: true,
                          color: tempColor.withOpacity(0.8),
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                tempColor.withOpacity(0.2),
                                tempColor.withOpacity(0.0),
                              ],
                            ),
                          ),
                        ),
                      ],
                      minY: minY,
                      maxY: maxY,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildModernLegend(hrColor, "Heart Rate (bpm)"),
              const SizedBox(width: 24),
              _buildModernLegend(tempColor, "Body Temp (°C)"),
            ],
          )
        ],
      ),
    );
  }

  // Helper widget for the Legend
  Widget _buildModernLegend(Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  String _getRiskMessage() {
    if (riskLevel.contains("High"))
      return "Immediate attention recommended. Elevated vitals detected.";
    if (riskLevel.contains("Medium"))
      return "Monitor closely. Rest and stay hydrated.";
    if (riskLevel.contains("Low"))
      return "Vitals within normal range. Continue monitoring.";
    return "Waiting for sensor data...";
  }

  // --- UI Redesign Helper Methods ---

  String _getHRStatus(double hr) {
    if (hr == 0) return "No Data";

    // High Risk: HR > 120 or < 40 bpm
    if (hr > 120 || hr < 40) return "High Risk";

    // Medium Risk: 100 to 120 bpm OR 50 to 59 bpm
    if ((hr >= 100 && hr <= 120) || (hr >= 50 && hr <= 59))
      return "Medium Risk";

    // Normal: 60 to 100 bpm
    if (hr >= 60 && hr < 100) return "Normal";

    // Default cases for small gaps (e.g., 40-50, 59-60)
    if (hr < 50) return "High Risk"; // Closer to 40
    return "Normal";
  }

  String _getTempStatus(double temp) {
    if (temp == 0) return "No Data";

    // High Risk: > 38°C (Special case: combined with high HR handled in global risk)
    if (temp > 38.0) return "High Risk";

    // Medium Risk: 37.3°C to 38.0°C
    if (temp >= 37.3 && temp <= 38.0) return "Medium Risk";

    // Normal: 36.1°C to 37.2°C
    if (temp >= 36.1 && temp <= 37.2) return "Normal";

    // Below normal (< 36.1) - often Normal in stable resting but can be Low
    return "Normal";
  }

  Color _getStatusColor(String status) {
    if (status.contains("High")) return const Color(0xFFFF3B30); // Apple Red
    if (status.contains("Medium"))
      return const Color(0xFFFF9500); // Apple Orange
    if (status.contains("Normal"))
      return const Color(0xFF34C759); // Apple Green
    return const Color(0xFF8E8E93); // Medical Grey for No Data
  }
}

// ================================================
// NEW MEDICAL UI COMPONENTS
// ================================================

class MedicalVitalCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final int percentage;
  final String status;
  final Color statusColor;
  final Widget iconWidget;
  final String description;

  const MedicalVitalCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.percentage,
    required this.status,
    required this.statusColor,
    required this.iconWidget,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    // Determine dynamic color based on percentage
    Color dynamicColor;
    if (percentage < 40) {
      dynamicColor = const Color(0xFF34C759); // Green
    } else if (percentage < 70) {
      dynamicColor = const Color(0xFFFF9500); // Orange
    } else {
      dynamicColor = const Color(0xFFFF3B30); // Red
    }

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12), // Even more compact
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: dynamicColor.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Shrink-wrap
        children: [
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 85, // Even smaller for compact height
                  height: 85,
                  child: CustomPaint(
                    painter: SemiCircularGaugePainter(
                      percentage: (percentage / 100).clamp(0.01, 1.0),
                    ),
                  ),
                ),
                // ANIMATED ICON CONTAINER
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: dynamicColor.withOpacity(0.12),
                        blurRadius: 10,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: iconWidget,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1C1C1E),
              letterSpacing: -1,
            ),
          ),
          Text(
            unit,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8E8E93),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          StatusBadge(label: status, color: statusColor),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: dynamicColor.withOpacity(0.6),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// --- ANIMATED ICONS ---

class AnimatedHeartIcon extends StatefulWidget {
  final Color color;
  final int percentage;

  const AnimatedHeartIcon(
      {super.key, required this.color, required this.percentage});

  @override
  State<AnimatedHeartIcon> createState() => _AnimatedHeartIconState();
}

class _AnimatedHeartIconState extends State<AnimatedHeartIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(AnimatedHeartIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Speed up pulse if heart rate (percentage proxy) is high
    int speed = 1000;
    if (widget.percentage > 70) speed = 600;
    if (widget.percentage > 40 && widget.percentage <= 70) speed = 850;

    _controller.duration = Duration(milliseconds: speed);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite, color: widget.color, size: 26),
          Text(
            "${widget.percentage}%",
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedTempIcon extends StatefulWidget {
  final Color color;
  final int percentage;

  const AnimatedTempIcon(
      {super.key, required this.color, required this.percentage});

  @override
  State<AnimatedTempIcon> createState() => _AnimatedTempIconState();
}

class _AnimatedTempIconState extends State<AnimatedTempIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        duration: const Duration(milliseconds: 2000), vsync: this)
      ..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.thermostat, color: widget.color, size: 26),
          Text(
            "${widget.percentage}%",
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// Alias for compatibility with existing code
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const StatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return StatusBadge(label: label, color: color);
  }
}

// --- PULSING SHIELD & SCANNING EFFECT ---

class PulsingShield extends StatefulWidget {
  final Color color;
  const PulsingShield({super.key, required this.color});

  @override
  State<PulsingShield> createState() => _PulsingShieldState();
}

class _PulsingShieldState extends State<PulsingShield>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(duration: const Duration(seconds: 2), vsync: this)
          ..repeat(reverse: true);
    _animation = Tween<double>(begin: 1.0, end: 1.15)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: widget.color.withOpacity(0.2), width: 2),
        ),
        child: Icon(Icons.shield_rounded, color: widget.color, size: 36),
      ),
    );
  }
}

class ScanningEffect extends StatefulWidget {
  const ScanningEffect({super.key});

  @override
  State<ScanningEffect> createState() => _ScanningEffectState();
}

class _ScanningEffectState extends State<ScanningEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(duration: const Duration(seconds: 3), vsync: this)
          ..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [
                (_animation.value - 0.2).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.2).clamp(0.0, 1.0),
              ],
              colors: [
                Colors.white.withOpacity(0.0),
                Colors.white.withOpacity(0.2),
                Colors.white.withOpacity(0.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SemiCircularGaugePainter extends CustomPainter {
  final double percentage;

  SemiCircularGaugePainter({required this.percentage});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 12.0;

    // Background track
    final trackPaint = Paint()
      ..color = const Color(0xFFF2F2F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final Rect arcRect =
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);
    const startAngle = 0.75 * 3.14159;
    const sweepAngle = 1.5 * 3.14159;

    // SEAM-SAFE DYNAMIC GRADIENT (Green -> Yellow -> Orange -> Red)
    // We map the colors to the 270 degree sweep, and use the 90 degree gap to loop back to Green.
    // This removes the red "bleed" at the start of the arc.
    final progressPaint = Paint()
      ..shader = SweepGradient(
        colors: const [
          Color(0xFF34C759), // Green (Start)
          Color(0xFF34C759), // Green (Anchor)
          Color(0xFFFFD60A), // Yellow (Medium)
          Color(0xFFFF9500), // Orange (High)
          Color(0xFFFF3B30), // Red (Danger)
          Color(0xFF34C759), // Green (Loop back for seam-safety)
        ],
        // Sweep is 270 deg = 0.75 of circle. Stops are adjusted to match.
        stops: const [0.0, 0.1, 0.35, 0.55, 0.75, 1.0],
        startAngle: 0.0,
        endAngle: 3.14159 * 2,
        transform: GradientRotation(startAngle),
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(arcRect, startAngle, sweepAngle, false, trackPaint);

    canvas.drawArc(
      arcRect,
      startAngle,
      sweepAngle * percentage.clamp(0.01, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant SemiCircularGaugePainter oldDelegate) {
    return oldDelegate.percentage != percentage;
  }
}
