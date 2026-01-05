import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';

import 'thinkgear.dart';
import '../../../../services/bluetooth_manager.dart';

class Member2Page extends StatefulWidget {
  const Member2Page({super.key});

  @override
  State<Member2Page> createState() => _Member2PageState();
}

class _Member2PageState extends State<Member2Page> {
  static const String deviceName = "HR-S0C1913";

  String status = "Waiting...";
  String errorMessage = "";

  Interpreter? interpreter;

  // Current values from model and bands
  double stressScore = 0.0;
  double relaxedScore = 0.0;
  String currentMood = "No Signal";
  String moodEmoji = "📡";

  // Signal quality
  int poorSignalLevel = 200;

  // Additional parsed metrics
  int attention = 0;
  int meditation = 0;
  List<double> powerBands = List.filled(
    8,
    0.0,
  ); // [delta, theta, lowA, highA, lowB, highB, lowG, midG]

  // For stable mood
  String _previousMood = "No Signal";
  static const double moodThresholdHigh = 0.75;
  static const double moodThresholdLow = 0.60;

  // For persistent stress detection (for safety alerts)
  Timer? _stressTimer;
  bool showRestAlert = false;
  static const Duration stressPersistenceThreshold = Duration(seconds: 30);

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
      if (poorSignalLevel <= 50) {
        _processRawEEG(raw);
      }
    };

    tg.onPoorSignal = (signalQuality) {
      if (!mounted) return;
      setState(() {
        poorSignalLevel = signalQuality;

        if (signalQuality > 100) {
          errorMessage = "No contact – place headset properly on forehead";
          _resetToNoSignal();
        } else if (signalQuality > 50) {
          errorMessage = "Weak signal – adjust headset for better contact";
          _resetToNoSignal();
        } else {
          errorMessage = "";
        }
      });
    };

    tg.onAttention = (att) {
      if (mounted && poorSignalLevel <= 50) {
        setState(() => attention = att);
        _updateStressAndMood();
      }
    };

    tg.onMeditation = (med) {
      if (mounted && poorSignalLevel <= 50) {
        setState(() => meditation = med);
        _updateStressAndMood();
      }
    };

    tg.onPowerBands = (bands) {
      if (mounted && poorSignalLevel <= 50) {
        setState(() {
          powerBands = bands.map((e) => e.toDouble()).toList();
        });
        _updateStressAndMood();
      }
    };

    if (btManager.isConnected(deviceName)) {
      _subscribeToData();
      setState(() => status = "Connected");
    }
  }

  void _resetToNoSignal() {
    setState(() {
      currentMood = "No Signal";
      moodEmoji = "📡";
      stressScore = 0.0;
      relaxedScore = 0.0;
      attention = 0;
      meditation = 0;
      powerBands = List.filled(8, 0.0);
      showRestAlert = false;
    });
    modelWindow.clear();
    _stressTimer?.cancel();
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
    if (interpreter == null || !mounted || poorSignalLevel > 50) return;

    try {
      // Correct input shape: [1, 1, 32]
      var input = [inputWindow]; // → [1, 32]
      var shapedInput = [input]; // → [1, 1, 32]

      // Output: [[relax_logit, stress_logit]]
      var output = List.generate(1, (_) => List.filled(2, 0.0));

      interpreter!.run(shapedInput, output);

      final relaxLogit = output[0][0];
      final stressLogit = output[0][1];

      // Softmax to get probabilities
      final expRelax = math.exp(relaxLogit);
      final expStress = math.exp(stressLogit);
      final sum = expRelax + expStress;

      final newStress = expStress / sum;
      final newRelaxed = expRelax / sum;

      setState(() {
        stressScore = newStress;
        relaxedScore = newRelaxed;
      });

      _updateStressAndMood();
    } catch (e) {
      debugPrint("TFLite inference error: $e");
    }
  }

  void _processRawEEG(int raw) {
    final normalized = raw / 2048.0;
    modelWindow.add(normalized);

    if (modelWindow.length >= modelWindowSize) {
      _runModel(List.from(modelWindow));
      modelWindow.clear();
    }
  }

  /// Compute hybrid stress score using model, meditation, and band ratios for accuracy
  void _updateStressAndMood() {
    if (poorSignalLevel > 50 || powerBands.every((e) => e == 0)) return;

    // Improved band-based stress with better normalization
    double alpha = powerBands[2] + powerBands[3] + 1e-6; // low + high alpha
    double beta = powerBands[4] + powerBands[5];
    double gamma = powerBands[6] + powerBands[7];

    double rawRatio = (beta + gamma) / alpha;

    // Use logarithmic scaling or soft clamp for better range (typical ratios 0.1 to 20+)
    double bandStress =
        rawRatio / (rawRatio + 2.0); // Sigmoid-like: approaches 0-1 naturally

    bandStress =
        bandStress.clamp(0.0, 5.0) /
        5.0; // Normalize to 0-1 based on typical ranges

    // Meditation-based stress (inverted, as low meditation = high stress)
    double medStress = 1.0 - (meditation / 100.0).clamp(0.0, 1.0);

    // Hybrid stress: average model, bands, and meditation for better accuracy
    double hybridStress = (stressScore + bandStress + medStress) / 3.0;
    double hybridRelaxed = 1.0 - hybridStress;

    setState(() {
      stressScore = hybridStress;
      relaxedScore = hybridRelaxed;
    });

    // Update mood with hysteresis
    String candidateMood;
    String candidateEmoji;

    if (hybridStress > moodThresholdHigh ||
        (_previousMood == "Stressed" && hybridStress > moodThresholdLow)) {
      candidateMood = "Stressed";
      candidateEmoji = "😰";
    } else if (hybridRelaxed > moodThresholdHigh ||
        (_previousMood == "Relaxed" && hybridRelaxed > moodThresholdLow)) {
      candidateMood = "Relaxed";
      candidateEmoji = "🧘‍♂️";
    } else {
      candidateMood = "Neutral";
      candidateEmoji = "😐";
    }

    if (candidateMood != currentMood) {
      setState(() {
        currentMood = candidateMood;
        moodEmoji = candidateEmoji;
        _previousMood = candidateMood;
      });
    }

    // Safety alert for persistent stress (for riders)
    if (hybridStress > 0.7) {
      if (_stressTimer == null || !_stressTimer!.isActive) {
        _stressTimer = Timer(stressPersistenceThreshold, () {
          if (mounted) {
            setState(() => showRestAlert = true);
          }
        });
      }
    } else {
      _stressTimer?.cancel();
      setState(() => showRestAlert = false);
    }
  }

  void _handleDisconnection() {
    if (mounted) {
      setState(() {
        status = "Disconnected";
        _resetToNoSignal();
        _previousMood = "No Signal";
        poorSignalLevel = 200;
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
      _resetToNoSignal();
      _previousMood = "No Signal";
      poorSignalLevel = 200;
      modelWindow.clear();
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _stressTimer?.cancel();
    interpreter?.close();
    super.dispose();
  }

  Color _getStressColor() {
    if (poorSignalLevel > 50) return Colors.grey;
    if (stressScore > 0.7) return Colors.red;
    if (stressScore > 0.4) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final btManager = context.watch<BluetoothManager>();
    final isConnected = btManager.isConnected(deviceName);

    final bool hasGoodSignal = poorSignalLevel <= 50;

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
                    if (errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
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
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
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

            const SizedBox(height: 30),

            // Mood Display
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
                      _getStressColor().withOpacity(0.25),
                      _getStressColor().withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Text(moodEmoji, style: const TextStyle(fontSize: 90)),
                    const SizedBox(height: 20),
                    Text(
                      currentMood,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: _getStressColor(),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      hasGoodSignal
                          ? _getMoodMessage()
                          : "Waiting for stable brain signal...",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Stress Level
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      hasGoodSignal
                          ? "Current Stress Level"
                          : "Signal Quality Required",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 180,
                          height: 180,
                          child: CircularProgressIndicator(
                            value: hasGoodSignal ? stressScore : 0.0,
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
                              hasGoodSignal
                                  ? "${(stressScore * 100).toStringAsFixed(0)}%"
                                  : "—",
                              style: TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                color: _getStressColor(),
                              ),
                            ),
                            Text(
                              hasGoodSignal ? "Stress" : "No Signal",
                              style: TextStyle(
                                fontSize: 16,
                                color: hasGoodSignal
                                    ? Colors.black54
                                    : Colors.grey,
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

            if (showRestAlert) ...[
              const SizedBox(height: 20),
              Card(
                elevation: 8,
                color: Colors.red.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red, size: 32),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "High stress detected for too long!\nFor safety, pull over and rest before continuing your ride.",
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  String _getMoodMessage() {
    switch (currentMood) {
      case "Stressed":
        return "High mental load detected.\nTake a deep breath, step away, or try a quick meditation.";
      case "Relaxed":
        return "You're in a calm and focused state.\nPerfect for learning, creativity, or rest.";
      case "Neutral":
        return "Your mind is balanced.\nNormal cognitive activity detected.";
      default:
        return "Establishing connection with brain signals...";
    }
  }
}
