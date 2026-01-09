import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

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
  String? errorMessage = "";

  Interpreter? interpreter;

  double stressScore = 0.0;
  double relaxedScore = 0.0;
  String currentMood = "No Signal";
  String moodEmoji = "📡";

  int poorSignalLevel = 200;

  int attention = 0;
  int meditation = 0;
  List<double> powerBands = List.filled(8, 0.0);

  Map<String, double> eegBands = {
    'Delta': 0.0,
    'Theta': 0.0,
    'Alpha': 0.0,
    'Beta': 0.0,
    'Gamma': 0.0,
  };

  double arousalLevel = 0.0;
  double valenceLevel = 0.0;
  String frustrationState = "Neutral";
  String frustrationEmoji = "😐";

  String _previousMood = "No Signal";
  static const double moodThresholdHigh = 0.75;
  static const double moodThresholdLow = 0.60;

  Timer? _stressTimer;
  bool showRestAlert = false;
  static const Duration stressPersistenceThreshold = Duration(seconds: 30);

  // === Enhanced Real-time EEG Waveform ===
  static const int waveformMaxPoints = 600; // Reduced for smoother feel
  static const int waveformUpdateIntervalMs = 100; // Slower UI updates (10 FPS)
  static const int smoothingWindow = 5; // Moving average smoothing

  final List<FlSpot> _waveformSpots = [];
  final List<double> _rawBuffer = [];
  final List<double> _smoothedBuffer = []; // For moving average
  Timer? _waveformUpdateTimer;

  final ThinkGearParser tg = ThinkGearParser();
  StreamSubscription? _dataSubscription;

  final List<double> modelWindow = [];
  final int modelWindowSize = 32;

  @override
  void initState() {
    super.initState();
    _init();
    _waveformUpdateTimer = Timer.periodic(
      const Duration(milliseconds: waveformUpdateIntervalMs),
      (_) => _flushWaveformBuffer(),
    );
  }

  Future<void> _init() async {
    final btManager = context.read<BluetoothManager>();
    await btManager.requestPermissions();
    await _loadModel();

    tg.onRaw = (raw) {
      if (poorSignalLevel <= 50) {
        _processRawEEG(raw);
        // Add to buffer for smoothing
        _rawBuffer.add(raw.toDouble());
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
          eegBands['Delta'] = powerBands[0];
          eegBands['Theta'] = powerBands[1];
          eegBands['Alpha'] = powerBands[2] + powerBands[3];
          eegBands['Beta'] = powerBands[4] + powerBands[5];
          eegBands['Gamma'] = powerBands[6] + powerBands[7];
        });
        _updateStressAndMood();
        _updateEmotionalStates();
      }
    };

    if (context.read<BluetoothManager>().isConnected(deviceName)) {
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
      eegBands.updateAll((key, value) => 0.0);
      arousalLevel = 0.0;
      valenceLevel = 0.0;
      frustrationState = "Neutral";
      frustrationEmoji = "😐";
      showRestAlert = false;
      _waveformSpots.clear();
      _rawBuffer.clear();
      errorMessage = ""; // Clear any error message
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
      onDone: _handleDisconnection,
    );
  }

  Future<void> _loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset(
        "assets/eeg_stress_model_final.tflite",
      );

      debugPrint("EEG Stress Model Loaded Successfully");

      if (mounted) {
        setState(() {
          errorMessage = null; // Safe: clear error on success
        });
      }
    } catch (e) {
      debugPrint("Model load failed: $e");

      if (mounted) {
        setState(() {
          errorMessage =
              "Failed to load AI model. Check if the file exists and pubspec.yaml is correct.";
        });
      }
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

  void _runModel(List<double> inputWindow) {
    if (interpreter == null || !mounted || poorSignalLevel > 50) return;

    try {
      var input = [inputWindow];
      var shapedInput = [input];
      var output = List.generate(1, (_) => List.filled(2, 0.0));

      interpreter!.run(shapedInput, output);

      final relaxLogit = output[0][0];
      final stressLogit = output[0][1];
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

  void _flushWaveformBuffer() {
    if (_rawBuffer.isEmpty || !mounted || poorSignalLevel > 50) {
      if (_rawBuffer.isEmpty && _smoothedBuffer.isNotEmpty) {
        _smoothedBuffer.clear();
      }
      return;
    }

    // Apply moving average smoothing
    for (double raw in _rawBuffer) {
      _smoothedBuffer.add(raw);
      if (_smoothedBuffer.length > smoothingWindow) {
        _smoothedBuffer.removeAt(0);
      }
      double avg =
          _smoothedBuffer.reduce((a, b) => a + b) / _smoothedBuffer.length;
      double normalized = avg / 2048.0;

      _waveformSpots.add(FlSpot(_waveformSpots.length.toDouble(), normalized));
    }

    // Keep only max points
    if (_waveformSpots.length > waveformMaxPoints) {
      final int removeCount = _waveformSpots.length - waveformMaxPoints;
      _waveformSpots.removeRange(0, removeCount);
      // Re-index X values
      for (int i = 0; i < _waveformSpots.length; i++) {
        _waveformSpots[i] = FlSpot(i.toDouble(), _waveformSpots[i].y);
      }
    }

    _rawBuffer.clear();

    if (mounted) setState(() {});
  }

  void _updateEmotionalStates() {
    if (powerBands.every((e) => e == 0)) return;

    double alpha = eegBands['Alpha']! + 1e-6;
    double beta = eegBands['Beta']!;
    double gamma = eegBands['Gamma']!;

    double betaAlphaRatio = (beta + gamma) / alpha;
    arousalLevel = (betaAlphaRatio / (betaAlphaRatio + 2.0)).clamp(0.0, 1.0);

    double pleasantFactor = (meditation / 100.0) + (1.0 - stressScore);
    valenceLevel = (pleasantFactor / 2.0).clamp(0.0, 1.0);

    String candidateFrustration;
    String candidateEmoji;

    if (arousalLevel > 0.65 && valenceLevel < 0.45) {
      candidateFrustration = "Frustrated";
      candidateEmoji = "😣";
    } else if (arousalLevel > 0.6 && valenceLevel > 0.55) {
      candidateFrustration = "Excited";
      candidateEmoji = "😃";
    } else if (arousalLevel < 0.4 && valenceLevel > 0.55) {
      candidateFrustration = "Calm/Relaxed";
      candidateEmoji = "😌";
    } else {
      candidateFrustration = "Neutral";
      candidateEmoji = "😐";
    }

    setState(() {
      frustrationState = candidateFrustration;
      frustrationEmoji = candidateEmoji;
    });
  }

  void _updateStressAndMood() {
    if (poorSignalLevel > 50 || powerBands.every((e) => e == 0)) return;

    double alpha = powerBands[2] + powerBands[3] + 1e-6;
    double beta = powerBands[4] + powerBands[5];
    double gamma = powerBands[6] + powerBands[7];
    double rawRatio = (beta + gamma) / alpha;
    double bandStress = rawRatio / (rawRatio + 2.0);
    bandStress = bandStress.clamp(0.0, 5.0) / 5.0;

    double medStress = 1.0 - (meditation / 100.0).clamp(0.0, 1.0);
    double hybridStress = (stressScore + bandStress + medStress) / 3.0;
    double hybridRelaxed = 1.0 - hybridStress;

    setState(() {
      stressScore = hybridStress;
      relaxedScore = hybridRelaxed;
    });

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

    if (hybridStress > 0.7) {
      _stressTimer ??= Timer(stressPersistenceThreshold, () {
        if (mounted) setState(() => showRestAlert = true);
      });
    } else {
      _stressTimer?.cancel();
      _stressTimer = null;
      if (mounted) setState(() => showRestAlert = false);
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
    _waveformUpdateTimer?.cancel();
    interpreter?.close();
    super.dispose();
  }

  Color _getStressColor() {
    if (poorSignalLevel > 50) return Colors.grey;
    if (stressScore > 0.7) return Colors.red;
    if (stressScore > 0.4) return Colors.orange;
    return Colors.green;
  }

  Widget _buildBandBar(
    String label,
    double value,
    Color color,
    String freqRange,
    String description,
  ) {
    double maxBand = eegBands.values.reduce(math.max);
    double normalized = maxBand > 0 ? value / maxBand : 0.0;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 180,
              alignment: Alignment.bottomCenter,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: FractionallySizedBox(
                heightFactor: normalized.clamp(0.0, 1.0),
                widthFactor: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [color, color.withOpacity(0.7)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            Text(
              freqRange,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Power: ${value.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.black54,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveformChart() {
    final bool hasData = _waveformSpots.isNotEmpty;

    if (!hasData) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.waves, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              "Waiting for brain signals...",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RepaintBoundary(
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: 0.5,
            verticalInterval: 100,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
            getDrawingVerticalLine: (value) =>
                FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: 0.5,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toStringAsFixed(1),
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: waveformMaxPoints / 4,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${(value / waveformMaxPoints * 1.5).toStringAsFixed(1)}s',
                    style: const TextStyle(color: Colors.black54, fontSize: 11),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          minX: 0,
          maxX: waveformMaxPoints.toDouble(),
          minY: -1.0,
          maxY: 1.0,
          clipData: const FlClipData.all(),
          backgroundColor: Colors.grey.shade50.withOpacity(0.3),
          lineBarsData: [
            LineChartBarData(
              spots: _waveformSpots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: Colors.cyanAccent,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.cyanAccent.withOpacity(0.15),
              ),
              shadow: const Shadow(
                color: Colors.cyanAccent,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => Colors.black87,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${(spot.y * 2048).toStringAsFixed(0)} μV',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
        duration: const Duration(milliseconds: 150),
      ),
    );
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
                    // FIXED: Safe null check for errorMessage
                    if (errorMessage != null && errorMessage!.isNotEmpty) ...[
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
                                errorMessage!, // Safe to use ! here
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
            const SizedBox(height: 30),
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      "Real-time EEG Waveform",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Live brain electrical activity • ~1.5 seconds window",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      height: 240,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: hasGoodSignal
                          ? _buildWaveformChart()
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.waves_outlined,
                                    size: 60,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    "Establishing signal contact...",
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 16,
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
                      "EEG Power Bands",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Relative power levels across brainwave frequencies",
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (hasGoodSignal)
                      Row(
                        children: [
                          _buildBandBar(
                            'Delta',
                            eegBands['Delta']!,
                            Colors.deepPurple,
                            '0.5–4 Hz',
                            'Deep sleep, healing, restoration',
                          ),
                          _buildBandBar(
                            'Theta',
                            eegBands['Theta']!,
                            Colors.blue,
                            '4–8 Hz',
                            'Drowsiness, creativity, intuition',
                          ),
                          _buildBandBar(
                            'Alpha',
                            eegBands['Alpha']!,
                            Colors.green,
                            '8–13 Hz',
                            'Relaxed alertness, calm focus',
                          ),
                          _buildBandBar(
                            'Beta',
                            eegBands['Beta']!,
                            Colors.orange,
                            '13–30 Hz',
                            'Active thinking, focus, anxiety if high',
                          ),
                          _buildBandBar(
                            'Gamma',
                            eegBands['Gamma']!,
                            Colors.red,
                            '>30 Hz',
                            'Peak cognition, insight, processing',
                          ),
                        ],
                      )
                    else
                      const Text(
                        "Waiting for good signal quality...",
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
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
                      const Icon(Icons.warning, color: Colors.red, size: 32),
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
