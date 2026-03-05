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

class _Member1PageState extends State<Member1Page> {
  static const String deviceName = "SmartWatch_ESP32";

  String status = "Waiting...";
  String errorMessage = "";
  StreamSubscription? _dataSubscription;
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
  DateTime? _lastSavedTime;
  final Duration _saveInterval = const Duration(seconds: 10);

  // Firestore
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
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
    final dataStream = btManager.getDataStream(deviceName);
    String buffer = '';

    _dataSubscription?.cancel();
    _dataSubscription = dataStream?.listen(
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
          setState(() => errorMessage = "Stream error: $e");
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

      if (hr > 0 && temp > 0) {
        final now = DateTime.now();
        if (_lastSavedTime == null ||
            now.difference(_lastSavedTime!) >= _saveInterval) {
          _saveToFirestore(hr, temp);
          _lastSavedTime = now;
        }
      }
    } catch (e) {
      debugPrint("Parse error: $e | Raw: $jsonString");
    }
  }

  Future<void> _saveToFirestore(double hr, double temp) async {
    final rideProvider =
        Provider.of<RideSessionProvider>(context, listen: false);

    // Only save if ride is active
    if (!rideProvider.isRideActive || rideProvider.currentRideId == null) {
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final userId = auth.userId;

      if (userId == null) {
        debugPrint("No logged-in user — cannot save to Firestore");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please log in to save data")),
          );
        }
        return;
      }

      final String isoTimestamp = DateTime.now().toIso8601String();

      final data = {
        "timestamp": isoTimestamp,
        "heartRate": hr,
        "bodyTemperature": temp,
        "riskLevel": riskLevel,
        "riskColor":
            "#${riskColor.value.toRadixString(16).padLeft(8, '0').substring(2)}",
        "userId": userId,
        "deviceName": deviceName,

        "createdAt": FieldValue.serverTimestamp(),
        "location": const GeoPoint(7.2000, 79.8730),

        "rideId": rideProvider.currentRideId!,

        // Ride metadata (copied once per ride)
        "rideStartLocation": rideProvider.startLocation, // GeoPoint
        "rideDestination": rideProvider.destinationName, // String
        "rideEndLocation":
            rideProvider.endLocation, // GeoPoint? (null until end)

        // Real-time location of THIS reading
        "currentLocation": _currentPosition != null
            ? GeoPoint(_currentPosition!.latitude, _currentPosition!.longitude)
            : null,
      };

      await _firestore.collection("health_readings").add(data);
      debugPrint("Health reading saved: HR=$hr, Temp=$temp");
    } catch (e) {
      debugPrint("Firestore save error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save reading: $e")),
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

      if (adjustedProbability > 0.65) {
        newRisk = "High";
        newColor = Colors.red;
      } else if (adjustedProbability > 0.35) {
        newRisk = "Medium";
        newColor = Colors.orange;
      } else {
        newRisk = "Low";
        newColor = Colors.green;
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
    String newRisk = "Low";
    Color newColor = Colors.green;
    int riskPercentage = 15;

    if (hr > 120 || hr < 40 || temp > 38.0 || temp < 35.0) {
      newRisk = "High";
      newColor = Colors.red;
      riskPercentage = 85;
    } else if (hr > 100 || hr < 60 || temp > 37.2) {
      newRisk = "Medium";
      newColor = Colors.orange;
      riskPercentage = 60;
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
    _dataSubscription?.cancel();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final btManager = context.watch<BluetoothManager>();
    final isConnected = btManager.isConnected(deviceName);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          "Health Monitor",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.assessment_rounded, size: 28),
            tooltip: "Weekly Report",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WeeklyReportPage()),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Connection Status Bar
                _buildConnectionStatus(isConnected),

                const SizedBox(height: 16),

                // Connection Controls
                _buildConnectionHeader(isConnected),

                const SizedBox(height: 20),

                // Vital Signs Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildVitalCard(
                        title: "Heart Rate",
                        value:
                            heartRate > 0 ? heartRate.toStringAsFixed(0) : "--",
                        unit: "BPM",
                        icon: Icons.favorite,
                        color: Colors.red.shade400,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildVitalCard(
                        title: "Temperature",
                        value: bodyTemperature > 0
                            ? bodyTemperature.toStringAsFixed(1)
                            : "--",
                        unit: "°C",
                        icon: Icons.thermostat,
                        color: Colors.blue.shade400,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Risk Assessment Card
                _buildRiskAssessment(),

                const SizedBox(height: 20),

                // Emotional State Card
                _buildEmotionalState(isConnected),

                const SizedBox(height: 20),

                // Live Vitals Chart
                _buildVitalsChart(),

                const SizedBox(height: 40),
              ],
            ),
          ),

          // Optional: small saving indicator
          if (_isSaving)
            const Positioned(
              bottom: 24,
              right: 24,
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        "Saving reading...",
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

  Widget _buildConnectionStatus(bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected ? Colors.green.shade200 : Colors.orange.shade200,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.check_circle : Icons.warning_amber_rounded,
            color: isConnected ? Colors.green.shade700 : Colors.orange.shade700,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isConnected
                    ? Colors.green.shade700
                    : Colors.orange.shade700,
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

  Widget _buildRiskAssessment() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [riskColor.withOpacity(0.1), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.monitor_heart, size: 24, color: riskColor),
                const SizedBox(width: 12),
                const Text(
                  "Cardiac Risk Assessment",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: riskColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                riskLevel,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: riskColor,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _getRiskMessage(),
              style: const TextStyle(fontSize: 13, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmotionalState(bool isConnected) {
    // Determine gradient based on dummy data or risk
    final List<Color> gradientColors = frustrationState == "Neutral"
        ? [Colors.blue.shade50, Colors.white]
        : frustrationState == "Frustrated"
            ? [Colors.orange.shade50, Colors.white]
            : [Colors.indigo.shade50, Colors.white];

    return Card(
      elevation: 4,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Emotional State",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.psychology, size: 14, color: Colors.indigo),
                      SizedBox(width: 4),
                      Text("Beta",
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo)),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Text(frustrationEmoji,
                      style: const TextStyle(fontSize: 48)),
                ),
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      frustrationState,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Current Analysis",
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isConnected
                    ? "Analyzing real-time physiological signals..."
                    : "Connect device to detect emotional state",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isConnected
                        ? Colors.indigo.shade400
                        : Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
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

    return Card(
      elevation: 4,
      shadowColor: Colors.black12,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ... Header logic remains the same ...
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
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                    Text(
                      "Live sensor feed",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green.withOpacity(0.3))),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: Colors.green, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text("LIVE",
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700)),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 240,
              child: heartRateSpots.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.query_stats,
                              size: 48, color: Colors.grey.shade200),
                          const SizedBox(height: 12),
                          Text("Waiting for signal...",
                              style: TextStyle(color: Colors.grey.shade400)),
                        ],
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        backgroundColor: Colors.transparent,
                        clipData: const FlClipData.all(),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: true,
                          horizontalInterval: 20,
                          verticalInterval: 5,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Colors.grey.shade200,
                            strokeWidth: 1,
                            dashArray: [5, 5],
                          ),
                          getDrawingVerticalLine: (value) => FlLine(
                            color: Colors.grey.shade100,
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade200),
                            left: BorderSide(color: Colors.grey.shade200),
                            right: const BorderSide(color: Colors.transparent),
                            top: const BorderSide(color: Colors.transparent),
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              // 2. DYNAMIC INTERVAL
                              // Calculate interval based on range to prevent cluttered labels
                              interval: (maxY - minY) > 100 ? 50 : 20,
                              getTitlesWidget: (value, meta) {
                                if (value < minY || value > maxY)
                                  return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Text(
                                    value.toInt().toString(),
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade500,
                                        fontWeight: FontWeight.w500),
                                    textAlign: TextAlign.right,
                                  ),
                                );
                              },
                            ),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              interval: (maxY - minY) > 100 ? 50 : 20,
                              getTitlesWidget: (value, meta) {
                                if (value < minY || value > maxY)
                                  return const SizedBox.shrink();
                                return Text(
                                  '${value.toStringAsFixed(1)}°',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue.shade300),
                                );
                              },
                            ),
                          ),
                          bottomTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        minX: heartRateSpots.first.x,
                        maxX: heartRateSpots.last.x,
                        // 3. APPLY DYNAMIC MIN/MAX
                        minY: minY,
                        maxY: maxY,
                        lineTouchData: LineTouchData(
                          enabled: true,
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => Colors.blueGrey.shade900,
                            tooltipRoundedRadius: 8,
                            getTooltipItems: (spots) {
                              return spots.map((spot) {
                                final isHR = spot.barIndex == 0;
                                return LineTooltipItem(
                                  isHR
                                      ? '${spot.y.toInt()} BPM'
                                      : '${spot.y.toStringAsFixed(1)}°C',
                                  TextStyle(
                                    color: isHR
                                        ? const Color(0xFFFF8A8A)
                                        : const Color(0xFF8AAFFF),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: heartRateSpots,
                            isCurved: true,
                            curveSmoothness: 0.35,
                            color: hrColor,
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
                            color: tempColor,
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
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildModernLegend(hrColor, "Heart Rate"),
                const SizedBox(width: 24),
                _buildModernLegend(tempColor, "Body Temp"),
              ],
            ),
          ],
        ),
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
}
