import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:provider/provider.dart';

import 'thinkgear.dart';
import '../../../../services/bluetooth_manager.dart';

class Member2Page extends StatefulWidget {
  const Member2Page({super.key});

  @override
  State<Member2Page> createState() => _Member2PageState();
}

class _Member2PageState extends State<Member2Page> {
  static const String deviceName = "HR-S0C1913"; // EEG device

  String status = "Waiting...";
  String errorMessage = "";

  Interpreter? interpreter;

  // Stress detection state
  double stressScore = 0.0; // 0.0 to 1.0
  double relaxedScore = 0.0;
  String currentMood = "Neutral";
  String moodEmoji = "😐";

  // For stable mood display (only change if confidence > threshold)
  static const double moodChangeThreshold = 0.7;

  final ThinkGearParser tg = ThinkGearParser();
  StreamSubscription? _dataSubscription;

  final List<double> modelWindow = [];
  final int modelWindowSize = 32;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final btManager = context.read<BluetoothManager>();
    await btManager.requestPermissions();
    await _loadModel();

    tg.onRaw = (raw) {
      _processRawEEG(raw);
    };

    tg.onPoorSignal = (signalQuality) {
      if (mounted) {
        setState(() {
          if (signalQuality > 100) {
            errorMessage = "Poor headset contact – adjust position";
          } else if (signalQuality > 50) {
            errorMessage = "Weak signal – ensure good skin contact";
          } else {
            errorMessage = "";
          }
        });
      }
    };

    if (btManager.isConnected(deviceName)) {
      _subscribeToData();
      setState(() => status = "Connected");
    }
  }

  void _subscribeToData() {
    final btManager = context.read<BluetoothManager>();
    final dataStream = btManager.getDataStream(deviceName);

    _dataSubscription?.cancel();
    _dataSubscription = dataStream?.listen(
      tg.feed,
      onError: (e) => debugPrint("EEG Stream Error: $e"),
      onDone: () => _handleDisconnection(),
    );
  }

  Future<void> _loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset("assets/eeg_model.tflite");
      debugPrint("EEG Stress Model Loaded");
    } catch (e) {
      debugPrint("Model load failed: $e");
      if (mounted) {
        setState(() => errorMessage = "Failed to load AI model");
      }
    }
  }

  void _runModel(List<double> inputWindow) {
    if (interpreter == null || !mounted) return;

    try {
      final input = [inputWindow];
      final output = List.generate(2, (_) => List.filled(1, 0.0));

      interpreter!.run(input, output);

      final newStress = output[0][0];
      final newRelaxed = output[1][0];

      setState(() {
        stressScore = newStress;
        relaxedScore = newRelaxed;

        // Only update mood if one class dominates clearly
        if (newStress > moodChangeThreshold) {
          currentMood = "Stressed";
          moodEmoji = "😰";
        } else if (newRelaxed > moodChangeThreshold) {
          currentMood = "Relaxed";
          moodEmoji = "🧘‍♂️";
        } else {
          currentMood = "Neutral";
          moodEmoji = "😐";
        }
      });
    } catch (e) {
      debugPrint("Inference error: $e");
    }
  }

  // Feed raw EEG values into model window
  void _processRawEEG(int raw) {
    final normalized = raw / 2048.0; // Normalize to ~[-1, 1]

    modelWindow.add(normalized);
    if (modelWindow.length == modelWindowSize) {
      _runModel(List.from(modelWindow));
      modelWindow.clear();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-subscribe if connection status changes
    final btManager = context.watch<BluetoothManager>();
    if (btManager.isConnected(deviceName) && _dataSubscription == null) {
      _subscribeToData();
      setState(() => status = "Connected");
    }
  }

  void _handleDisconnection() {
    if (mounted) {
      setState(() {
        status = "Disconnected";
        currentMood = "Neutral";
        moodEmoji = "😐";
        stressScore = 0.0;
        relaxedScore = 0.0;
      });
    }
  }

  Future<void> connectToEEG() async {
    final btManager = context.read<BluetoothManager>();
    setState(() {
      status = "Connecting...";
      errorMessage = "";
    });

    final result = await btManager.connectToDevice(deviceName);
    setState(() => status = result);

    if (btManager.isConnected(deviceName)) {
      _subscribeToData();
      setState(() => status = "Connected");
    }
  }

  Future<void> disconnectEEG() async {
    final btManager = context.read<BluetoothManager>();
    await btManager.disconnectDevice(deviceName);
    _dataSubscription?.cancel();
    _dataSubscription = null;

    setState(() {
      status = "Disconnected";
      currentMood = "Neutral";
      moodEmoji = "😐";
      stressScore = 0.0;
      modelWindow.clear();
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    interpreter?.close();
    super.dispose();
  }

  Color _getStressColor() {
    if (stressScore > 0.7) return Colors.red;
    if (stressScore > 0.4) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final btManager = context.watch<BluetoothManager>();
    final isConnected = btManager.isConnected(deviceName);

    return Scaffold(
      appBar: AppBar(
        title: const Text("EEG Stress & Mood Detection"),
        backgroundColor: Colors.deepPurple,
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
                            onPressed: isConnected ? null : connectToEEG,
                            icon: const Icon(Icons.sensors),
                            label: const Text("Connect EEG"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isConnected ? disconnectEEG : null,
                            icon: const Icon(Icons.bluetooth_disabled),
                            label: const Text("Disconnect"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
                    if (errorMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  errorMessage,
                                  style: const TextStyle(color: Colors.orange),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Current Mood Display
            Card(
              elevation: 10,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 40,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [
                      _getStressColor().withOpacity(0.2),
                      _getStressColor().withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Text(moodEmoji, style: const TextStyle(fontSize: 80)),
                    const SizedBox(height: 20),
                    Text(
                      currentMood,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: _getStressColor(),
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _getMoodMessage(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Colors.black),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Stress Level Ring
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      "Current Stress Level",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 180,
                          height: 180,
                          child: CircularProgressIndicator(
                            value: stressScore,
                            strokeWidth: 16,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: AlwaysStoppedAnimation(
                              _getStressColor(),
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            Text(
                              "${(stressScore * 100).toStringAsFixed(0)}%",
                              style: TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                color: _getStressColor(),
                              ),
                            ),
                            const Text(
                              "Stress",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ],
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

  String _getMoodMessage() {
    switch (currentMood) {
      case "Stressed":
        return "High mental load detected.\nTake a break, breathe deeply, or try meditation.";
      case "Relaxed":
        return "You're in a calm and focused state.\nGreat for productivity or recovery.";
      default:
        return "Monitoring your brain activity...\nAdjust headset for better signal.";
    }
  }
}
