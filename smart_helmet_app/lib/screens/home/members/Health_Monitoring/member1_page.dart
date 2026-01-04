import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../../../services/bluetooth_manager.dart';

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

  // Parsed sensor values
  double heartRate = 0.0;
  double bodyTemperature = 0.0;
  String riskLevel = "Unknown";
  Color riskColor = Colors.grey;

  Interpreter? _interpreter;

  // New: For Separate Emotional States (defaults since no EEG data in this page; integrate EEG for dynamic updates)
  double arousalLevel = 0.0; // High = excited/frustrated, Low = calm/bored
  double valenceLevel = 0.0; // High = positive/pleasant, Low = negative/unpleasant (e.g., frustration)
  String frustrationState = "Neutral";
  String frustrationEmoji = "😐";

  @override
  void initState() {
    super.initState();
    _loadModel();
    _init();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model.tflite');
      debugPrint("TFLite model loaded successfully");
    } catch (e) {
      debugPrint("Error loading TFLite model: $e");
      if (mounted) {
        setState(() {
          errorMessage = "Failed to load prediction model";
        });
      }
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

        // Split by newline (ESP32 sends with println)
        List<String> lines = buffer.split('\n');
        if (lines.length > 1) {
          for (int i = 0; i < lines.length - 1; i++) {
            String line = lines[i].trim();
            if (line.isNotEmpty) {
              _parseAndUpdateData(line);
            }
          }
          buffer = lines.last; // Keep incomplete part
        }
      },
      onError: (e) {
        debugPrint("Data stream error: $e");
        if (mounted) {
          setState(() => errorMessage = "Stream error: ${e.toString()}");
        }
      },
      onDone: () {
        debugPrint("$deviceName stream closed");
        if (mounted) {
          setState(() {
            status = "Disconnected";
            riskLevel = "Unknown";
            riskColor = Colors.grey;
          });
        }
      },
    );
  }

  void _parseAndUpdateData(String jsonString) {
    try {
      final Map<String, dynamic> json = jsonDecode(jsonString);
      final double hr = (json['hr'] as num?)?.toDouble() ?? 0.0;
      final double temp = (json['temp'] as num?)?.toDouble() ?? 0.0;

      if (mounted) {
        setState(() {
          heartRate = hr;
          bodyTemperature = temp;
        });
      }

      // Predict using TFLite
      _predictWithTFLite(hr, temp);
    } catch (e) {
      debugPrint("JSON parse error: $e | Raw: $jsonString");
    }
  }

  void _predictWithTFLite(double hr, double temp) {
    if (hr == 0 || temp == 0 || _interpreter == null) {
      _fallbackLocalRisk(hr, temp);
      return;
    }

    try {
      // Input: [heart_rate, body_temperature]
      // Assuming model expects float32 input shape [1, 2]
      var input = [[hr, temp]];
      var output = List.filled(1, [0.0]); // Output shape [1, 1] for probability

      _interpreter!.run(input, output);

      double prob = output[0][0] * 100; // Assuming sigmoid output (0-1)
      String newRisk = (output[0][0] > 0.5) ? "High" : "Low";
      int probInt = prob.round();

      Color newRiskColor = Colors.green;
      if (newRisk == "High") newRiskColor = Colors.red;
      else if (newRisk == "Medium") newRiskColor = Colors.orange; // If model outputs medium, but binary here

      if (mounted) {
        setState(() {
          riskLevel = "$newRisk ($probInt%)";
          riskColor = newRiskColor;
        });
      }
    } catch (e) {
      debugPrint("TFLite prediction error: $e");
      _fallbackLocalRisk(hr, temp);
    }
  }

  void _fallbackLocalRisk(double hr, double temp) {
    String newRisk = "Low";
    Color newRiskColor = Colors.green;

    if (hr > 100 || temp > 38.0) {
      newRisk = "High";
      newRiskColor = Colors.red;
    } else if (hr > 90 || temp > 37.5) {
      newRisk = "Medium";
      newRiskColor = Colors.orange;
    }

    if (mounted) {
      setState(() {
        riskLevel = newRisk;
        riskColor = newRiskColor;
      });
    }
  }

  Future<void> connectToDevice() async {
    final btManager = context.read<BluetoothManager>();

    setState(() {
      status = "Connecting...";
      errorMessage = "";
    });

    await Future.delayed(const Duration(seconds: 2));

    try {
      final result = await btManager.connectToDevice(deviceName);

      if (mounted) {
        setState(() => status = result);

        if (btManager.isConnected(deviceName)) {
          reconnectAttempts = 0;
          _subscribeToData();
          setState(() {
            status = "Connected";
            errorMessage = "";
          });
        } else {
          errorMessage = result;
          if (reconnectAttempts < maxReconnectAttempts) {
            reconnectAttempts++;
            debugPrint(
              "Reconnection attempt $reconnectAttempts/$maxReconnectAttempts",
            );
            await Future.delayed(const Duration(seconds: 3));
            if (mounted && !btManager.isConnected(deviceName))
              connectToDevice();
          } else {
            setState(() {
              status = "Connection failed";
              errorMessage =
                  "Failed after $maxReconnectAttempts attempts.\n\nTroubleshooting:\n"
                  "• Ensure ESP32 is powered on\n"
                  "• Check pairing in Bluetooth settings\n"
                  "• Unpair & re-pair device\n"
                  "• Restart ESP32\n"
                  "• Stay within 10m range";
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          status = "Connection failed";
          errorMessage = "Error: ${e.toString()}";
        });
      }
    }
  }

  Future<void> disconnectDevice() async {
    final btManager = context.read<BluetoothManager>();
    await btManager.disconnectDevice(deviceName);
    _dataSubscription?.cancel();
    _dataSubscription = null;

    setState(() {
      status = "Disconnected";
      errorMessage = "";
      heartRate = 0.0;
      bodyTemperature = 0.0;
      riskLevel = "Unknown";
      riskColor = Colors.grey;
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
      appBar: AppBar(
        title: const Text("Health Monitoring"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection Card
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isConnected ? null : connectToDevice,
                            icon: const Icon(Icons.bluetooth_connected),
                            label: const Text("Connect"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isConnected ? disconnectDevice : null,
                            icon: const Icon(Icons.bluetooth_disabled),
                            label: const Text("Disconnect"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isConnected ? Icons.circle : Icons.circle_outlined,
                          color: isConnected ? Colors.green : Colors.orange,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isConnected ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    if (errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                errorMessage,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Vital Signs Cards
            Row(
              children: [
                Expanded(
                  child: _buildVitalCard(
                    title: "Heart Rate",
                    value: heartRate > 0
                        ? "${heartRate.toStringAsFixed(0)} BPM"
                        : "--",
                    icon: Icons.favorite,
                    color: Colors.red.shade400,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildVitalCard(
                    title: "Body Temperature",
                    value: bodyTemperature > 0
                        ? "${bodyTemperature.toStringAsFixed(1)} °C"
                        : "--",
                    icon: Icons.thermostat,
                    color: Colors.blue.shade400,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Risk Assessment Card
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      riskColor.withOpacity(0.2),
                      riskColor.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(Icons.monitor_heart, size: 60, color: riskColor),
                    const SizedBox(height: 16),
                    const Text(
                      "Cardiac Risk Assessment",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      riskLevel,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: riskColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getRiskMessage(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // New: Separate Emotional States from EEG Waves
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              color: Colors.indigo.shade50,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      "Detected Emotional State (from EEG Waves)",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      frustrationEmoji,
                      style: const TextStyle(fontSize: 90),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      frustrationState,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isConnected
                          ? "Based on real-time EEG band ratios (Beta/Alpha for arousal + meditation/stress for valence)"
                          : "Waiting for good signal...",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    if (frustrationState == "Frustrated")
                      const Text(
                        "High arousal with unpleasant valence detected – possible frustration or anger.",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Emotional States to Predict Heart Attack (unchanged from previous)
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Emotional States to Predict Heart Attack",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Based on research (PMID: 24149648):",
                      style: TextStyle(fontSize: 16, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    const BulletPoint(
                      text:
                          "Unpleasant emotions / Frustration (before the event)",
                    ),
                    const BulletPoint(
                      text: "Rapid increase in anger (during the event)",
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Monitor your stress levels and seek medical advice if experiencing these states persistently.",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRiskMessage() {
    if (riskLevel.contains("High")) {
      return "Immediate attention recommended.\nHigh heart rate or elevated temperature detected.";
    } else if (riskLevel.contains("Medium")) {
      return "Monitor closely.\nSlightly elevated vitals – rest and hydrate.";
    } else if (riskLevel.contains("Low")) {
      return "Vitals appear normal.\nContinue regular monitoring.";
    } else {
      return "Waiting for data...";
    }
  }
}

class BulletPoint extends StatelessWidget {
  final String text;

  const BulletPoint({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "• ",
            style: TextStyle(fontSize: 16, color: Colors.black87),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}