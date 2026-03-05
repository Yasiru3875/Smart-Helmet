// member2_page.dart (updated with button)
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import 'thinkgear.dart';
import '../../../../services/bluetooth_manager.dart';

import '../../../../services/auth_service.dart';
import 'weekly_stress_report.dart'; // ← NEW import

import 'package:smart_helmet_app/providers/sensor_data_provider.dart';

import 'package:smart_helmet_app/providers/ride_session_provider.dart';
import 'package:smart_helmet_app/providers/emotion_provider.dart';
// If you have auth:
// import '../../../../services/auth_service.dart';

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
  Color moodColor = Colors.grey;

  double fatigueScore = 0.0;
  String fatigueLevel = "No Signal";
  String fatigueEmoji = "📡";
  Color fatigueColor = Colors.grey;

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
  static const int waveformMaxPoints = 600;
  static const int waveformUpdateIntervalMs = 100;
  static const int smoothingWindow = 5;

  final List<FlSpot> _waveformSpots = [];
  final List<double> _rawBuffer = [];
  final List<double> _smoothedBuffer = [];
  Timer? _waveformUpdateTimer;

  final ThinkGearParser tg = ThinkGearParser();
  StreamSubscription? _dataSubscription;

  final List<double> modelWindow = [];
  final int modelWindowSize = 64;

  // ────────────────────────────────────────────────
  // Firestore integration
  // ────────────────────────────────────────────────
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSaving = false;

  // Throttle saving: max once every 10 seconds
  DateTime? _lastSavedTime;
  final Duration _saveInterval = const Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _init(); // model + listeners
    _startLocationTracking();

    // Auto connect flow
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnectSensor();

      // Optional: retry once after 6 seconds if still not connected
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted &&
            !context.read<BluetoothManager>().isConnected(deviceName) &&
            poorSignalLevel == 200) {
          _autoConnectSensor(isRetry: true);
        }
      });
    });

    _waveformUpdateTimer = Timer.periodic(
      const Duration(milliseconds: waveformUpdateIntervalMs),
      (_) => _flushWaveformBuffer(),
    );
  }

  Future<void> _autoConnectSensor({bool isRetry = false}) async {
    final btManager = context.read<BluetoothManager>();

    // Already connected → just subscribe
    if (btManager.isConnected(deviceName)) {
      if (mounted) {
        setState(() => status = "Connected (already)");
      }
      _subscribeToData();
      return;
    }

    if (!mounted) return;

    setState(() {
      status = "${isRetry ? 'Re-' : 'A'}uto-connecting $deviceName...";
      errorMessage = null;
    });

    try {
      final result = await btManager.connectToDevice(deviceName);

      if (!mounted) return;

      setState(() {
        status = result;
      });

      if (btManager.isConnected(deviceName)) {
        _subscribeToData();
        setState(() {
          status = "Connected • $deviceName";
          errorMessage = null;
        });
      } else {
        setState(() {
          errorMessage =
              "Connection failed → $result\nMake sure device is on and paired.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        status = "Connection error";
        errorMessage =
            "Error: $e\nCheck Bluetooth • Is $deviceName powered on?";
      });
    }
  }

  Future<void> _init() async {
    final btManager = context.read<BluetoothManager>();
    await btManager.requestPermissions();
    await _loadModel();

    tg.onRaw = (raw) {
      if (poorSignalLevel <= 50) {
        _processRawEEG(raw);
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
          errorMessage = null;
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

  Future<void> _loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset(
        'assets/models/eeg_stress_model_float32.tflite',
      );
      debugPrint("EEG Stress Model Loaded Successfully");
      if (mounted) setState(() => errorMessage = null);
    } catch (e) {
      debugPrint("Model load failed: $e");
      if (mounted) {
        setState(() {
          errorMessage =
              "Failed to load AI model. Check file and pubspec.yaml.";
        });
      }
    }
  }

  void _resetToNoSignal() {
    setState(() {
      currentMood = "No Signal";
      moodEmoji = "📡";
      moodColor = Colors.grey;

      fatigueLevel = "No Signal";
      fatigueEmoji = "📡";
      fatigueColor = Colors.grey;

      fatigueScore = stressScore = relaxedScore = 0.0;
      attention = meditation = 0;
      powerBands = List.filled(8, 0.0);
      eegBands.updateAll((key, value) => 0.0);
      arousalLevel = valenceLevel = 0.0;
      frustrationState = "Neutral";
      frustrationEmoji = "😐";
      showRestAlert = false;
      _waveformSpots.clear();
      _rawBuffer.clear();
      errorMessage = "";
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
      // 1. Convert flat List<double> (length 64) → List<List<double>> (64 × 1)
      List<List<double>> sequence = inputWindow.map((e) => [e]).toList();

      // 2. Add batch dimension → List<List<List<double>>> with shape [1, 64, 1]
      List<List<List<double>>> shapedInput = [sequence];

      // Prepare output buffer [1, 2]
      var output = List.generate(1, (_) => List.filled(2, 0.0));

      // Run inference
      interpreter!.run(shapedInput, output);

      // Softmax over logits
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

    if (_waveformSpots.length > waveformMaxPoints) {
      final int removeCount = _waveformSpots.length - waveformMaxPoints;
      _waveformSpots.removeRange(0, removeCount);
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

  // Add near the top of the class
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  bool _locationServiceEnabled = false;
  LocationPermission _permission = LocationPermission.denied;

// Add this method (call it in initState)
  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable location services'),
            duration: Duration(seconds: 6),
          ),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Location permission permanently denied – open app settings'),
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: () => Geolocator.openAppSettings(),
            ),
          ),
        );
      }
      return;
    }

    // Start stream with slightly more forgiving settings for faster first fix
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium, // ← changed from high
        distanceFilter: 8,
        timeLimit: Duration(seconds: 8), // help get first fix faster
      ),
    ).listen(
      (Position pos) {
        print("Position update → ${pos.latitude.toStringAsFixed(6)}, "
            "${pos.longitude.toStringAsFixed(6)} • acc: ${pos.accuracy}m");
        if (mounted) setState(() => _currentPosition = pos);
      },
      onError: (e) => print("Position stream error: $e"),
    );

    // Optional: get one initial position right away (faster first save)
    try {
      final initial = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 6),
      );
      if (mounted) setState(() => _currentPosition = initial);
    } catch (e) {
      print("Initial position fetch failed: $e");
    }
  }

  void _updateStressAndMood() {
    if (poorSignalLevel > 50 || powerBands.every((e) => e == 0)) {
      Provider.of<EmotionProvider>(context, listen: false).resetOnNoSignal();
      return;
    }

    double alpha = powerBands[2] + powerBands[3] + 1e-6;
    double beta = powerBands[4] + powerBands[5];
    double gamma = powerBands[6] + powerBands[7];
    double rawRatio = (beta + gamma) / alpha;
    double bandStress = rawRatio / (rawRatio + 2.0);
    bandStress = bandStress.clamp(0.0, 5.0) / 5.0;

    double medStress = 1.0 - (meditation / 100.0).clamp(0.0, 1.0);

    double signalQuality = (200 - poorSignalLevel).clamp(0, 200) / 200.0;
    signalQuality = math.pow(signalQuality, 1.5).toDouble();

    double trustedStress = stressScore * signalQuality;
    double hybridStress = (trustedStress + bandStress + medStress) / 3.0;
    double hybridRelaxed = 1.0 - hybridStress;

    final sensorProvider =
        Provider.of<SensorDataProvider>(context, listen: false);
    final int stressPercent = (hybridStress * 100).round().clamp(0, 100);
    sensorProvider.updateStressLevel(stressPercent);

    // ─── Multi-level stress ──────────────────────────────────────────────────
    String newStressLevel;
    String newStressEmoji;
    Color stressLevelColor;

    if (hybridStress <= 0.25) {
      newStressLevel = "Very Relaxed";
      newStressEmoji = "😌";
      stressLevelColor = Colors.green[800]!;
    } else if (hybridStress <= 0.45) {
      newStressLevel = "Relaxed";
      newStressEmoji = "🙂";
      stressLevelColor = Colors.green[400]!;
    } else if (hybridStress <= 0.65) {
      newStressLevel = "Neutral";
      newStressEmoji = "😐";
      stressLevelColor = Colors.yellow[800]!;
    } else if (hybridStress <= 0.80) {
      newStressLevel = "Elevated";
      newStressEmoji = "😟";
      stressLevelColor = Colors.orange[700]!;
    } else {
      newStressLevel = "High Stress";
      newStressEmoji = "😰";
      stressLevelColor = Colors.red[700]!;
    }

    bool stressLevelChanged = newStressLevel != currentMood;

    // ─── Fatigue calculation ─────────────────────────────────────────────────
    double thetaPower = eegBands['Theta']!;
    double deltaPower = eegBands['Delta']!;
    double betaPower = eegBands['Beta']!;
    double thetaBetaRatio = (thetaPower + 1e-6) / (betaPower + 1e-6);
    double deltaBetaRatio = (deltaPower + 1e-6) / (betaPower + 1e-6);

    double attentionDrop = (100 - attention) / 100.0;

    double fatigueRaw = 0.0;
    fatigueRaw += 0.40 * (thetaBetaRatio / 5.0).clamp(0.0, 1.0);
    fatigueRaw += 0.25 * (deltaBetaRatio / 3.0).clamp(0.0, 1.0);
    fatigueRaw += 0.35 * attentionDrop.clamp(0.0, 1.0);

    fatigueScore = fatigueRaw * signalQuality;

    String newFatigueLevel;
    String newFatigueEmoji;
    Color fatigueLevelColor;

    if (fatigueScore <= 0.25) {
      newFatigueLevel = "Alert";
      newFatigueEmoji = "⚡";
      fatigueLevelColor = Colors.green[700]!;
    } else if (fatigueScore <= 0.45) {
      newFatigueLevel = "Mild Fatigue";
      newFatigueEmoji = "🥱";
      fatigueLevelColor = Colors.yellow[800]!;
    } else if (fatigueScore <= 0.65) {
      newFatigueLevel = "Moderate Fatigue";
      newFatigueEmoji = "😴";
      fatigueLevelColor = Colors.orange[700]!;
    } else {
      newFatigueLevel = "High Fatigue";
      newFatigueEmoji = "☠️";
      fatigueLevelColor = Colors.red[800]!;
    }

    final emotionProvider =
        Provider.of<EmotionProvider>(context, listen: false);

    emotionProvider.updateStress(
      emotion: newStressLevel,
      emoji: newStressEmoji,
      color: stressLevelColor,
    );

    setState(() {
      currentMood = newStressLevel;
      moodEmoji = newStressEmoji;
      moodColor = stressLevelColor;

      fatigueLevel = newFatigueLevel;
      fatigueEmoji = newFatigueEmoji;
      fatigueColor = fatigueLevelColor;

      stressScore = hybridStress;
      relaxedScore = hybridRelaxed;
    });

    // Persistence alert (now uses hybridStress > 0.7)
    if (hybridStress > 0.7) {
      _stressTimer ??= Timer(stressPersistenceThreshold, () {
        if (mounted) setState(() => showRestAlert = true);
      });
    } else {
      _stressTimer?.cancel();
      _stressTimer = null;
      if (mounted) setState(() => showRestAlert = false);
    }

    // Firestore save
    final now = DateTime.now();
    final timeToSave = _lastSavedTime == null ||
        now.difference(_lastSavedTime!) >= _saveInterval;

    final importantChange = stressLevelChanged &&
        (newStressLevel == "High Stress" || newStressLevel == "Very Relaxed");

    if (timeToSave || importantChange) {
      _saveToFirestore();
      _lastSavedTime = now;
    }
  }

  void _saveToFirestoreIfNeeded(bool moodChanged) {
    if (poorSignalLevel > 50) return;

    final now = DateTime.now();
    final timeToSave = _lastSavedTime == null ||
        now.difference(_lastSavedTime!) >= _saveInterval;

    final importantChange =
        moodChanged && (currentMood == "Stressed" || currentMood == "Relaxed");

    if (timeToSave || importantChange) {
      _saveToFirestore();
      _lastSavedTime = now;
    }
  }

  Future<void> _saveToFirestore() async {
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
        "stressScore": stressScore,
        "relaxedScore": relaxedScore,
        "currentMood": currentMood,
        "arousalLevel": arousalLevel,
        "valenceLevel": valenceLevel,
        "frustrationState": frustrationState,
        "poorSignalLevel": poorSignalLevel,
        "attention": attention,
        "meditation": meditation,
        "userId": userId, // ← now dynamic!
        "deviceName": deviceName,
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

        "createdAt": FieldValue.serverTimestamp(),

        // "location":
        //     const GeoPoint(7.2000, 79.8730), // replace with real location later
      };

      await _firestore.collection("stress_mood_readings").add(data);

      debugPrint(
          "Stress/Mood reading saved for user $userId: $currentMood ($stressScore) | "
          "Ride: ${rideProvider.currentRideId} | "
          "Location: ${_currentPosition?.latitude.toStringAsFixed(6) ?? 'N/A'}, "
          "${_currentPosition?.longitude.toStringAsFixed(6) ?? 'N/A'}");
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
    _positionStream?.cancel();
    interpreter?.close();
    super.dispose();
  }

  Color _getStressColor() {
    if (poorSignalLevel > 50) return Colors.grey;
    if (stressScore > 0.7) return Colors.red;
    if (stressScore > 0.4) return Colors.orange;
    return Colors.green;
  }

  IconData _getConnectionIcon() {
    final bm = context.watch<BluetoothManager>();
    if (bm.isConnected(deviceName)) return Icons.bluetooth_connected;
    if (status.contains("Connecting")) return Icons.bluetooth_searching;
    return Icons.bluetooth_disabled;
  }

  Color _getConnectionColor() {
    final bm = context.watch<BluetoothManager>();
    if (bm.isConnected(deviceName)) return Colors.green;
    if (status.contains("Connecting")) return Colors.blue;
    if (status.contains("failed") || status.contains("Error"))
      return Colors.red;
    return Colors.orange;
  }

  String _getStressMessage() {
    switch (currentMood) {
      case "Very Relaxed":
        return "Deep calm detected.\nIdeal mental state – enjoy the ride.";
      case "Relaxed":
        return "Calm and focused.\nPerfect for safe, steady riding.";
      case "Neutral":
        return "Balanced mental activity.\nNormal and stable.";
      case "Elevated":
        return "Mild tension rising.\nTake slow breaths, stay aware.";
      case "High Stress":
        return "High mental load detected.\nConsider pulling over if it persists.";
      default:
        return "Establishing connection with brain signals...";
    }
  }

  String _getFatigueMessage() {
    switch (fatigueLevel) {
      case "Alert":
        return "Fully alert and sharp.\nSafe to continue riding.";
      case "Mild Fatigue":
        return "Slight tiredness detected.\nStay hydrated, maintain focus.";
      case "Moderate Fatigue":
        return "Moderate fatigue building.\nPlan a short break in the next 20–30 min.";
      case "High Fatigue":
        return "High drowsiness risk!\nPull over safely as soon as possible.";
      default:
        return "Waiting for stable signal...";
    }
  }

  // ────────────────────────────────────────────────
  // Your existing widget methods (unchanged)
  // ────────────────────────────────────────────────

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
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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

  Widget _buildConnectButton() {
    final btManager = context.watch<BluetoothManager>();
    final isConnected = btManager.isConnected(deviceName);

    return ElevatedButton.icon(
      icon: Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
      label: Text(isConnected ? 'Connected' : 'Connect EEG'),
      style: ElevatedButton.styleFrom(
        backgroundColor: isConnected ? Colors.green : Colors.blue,
      ),
      onPressed: isConnected ? null : _autoConnectSensor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final btManager = context.watch<BluetoothManager>();
    final isConnected = btManager.isConnected(deviceName);
    final bool hasGoodSignal = poorSignalLevel <= 50;

    return Scaffold(
      appBar: AppBar(
        title: const Text("EEG Stress & Fatigue Monitor"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Connection status card (unchanged)
                Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _getConnectionIcon(),
                              color: _getConnectionColor(),
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _getConnectionColor(),
                              ),
                            ),
                          ],
                        ),
                        if (errorMessage != null &&
                            errorMessage!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber,
                                    color: Colors.orange),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    errorMessage!,
                                    style: TextStyle(
                                        color: Colors.orange.shade800,
                                        fontSize: 14),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (!isConnected)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text("Retry connection"),
                            onPressed: _autoConnectSensor,
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Stress Card (updated with dynamic color)
                Card(
                  elevation: 10,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 40, horizontal: 20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        colors: [
                          moodColor.withOpacity(0.25),
                          moodColor.withOpacity(0.05),
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
                            color: moodColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          hasGoodSignal
                              ? _getStressMessage()
                              : "Waiting for stable brain signal...",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // // ─── NEW: Fatigue Card ────────────────────────────────────────────────
                // Card(
                //   elevation: 10,
                //   shape: RoundedRectangleBorder(
                //       borderRadius: BorderRadius.circular(24)),
                //   child: Container(
                //     padding: const EdgeInsets.symmetric(
                //         vertical: 40, horizontal: 20),
                //     decoration: BoxDecoration(
                //       borderRadius: BorderRadius.circular(24),
                //       gradient: LinearGradient(
                //         colors: [
                //           fatigueColor.withOpacity(0.25),
                //           fatigueColor.withOpacity(0.05),
                //         ],
                //         begin: Alignment.topLeft,
                //         end: Alignment.bottomRight,
                //       ),
                //     ),
                //     child: Column(
                //       children: [
                //         Text(fatigueEmoji,
                //             style: const TextStyle(fontSize: 90)),
                //         const SizedBox(height: 20),
                //         Text(
                //           fatigueLevel,
                //           style: TextStyle(
                //             fontSize: 34,
                //             fontWeight: FontWeight.w900,
                //             color: fatigueColor,
                //             letterSpacing: 1.2,
                //           ),
                //         ),
                //         const SizedBox(height: 16),
                //         Text(
                //           hasGoodSignal
                //               ? _getFatigueMessage()
                //               : "Waiting for stable brain signal...",
                //           textAlign: TextAlign.center,
                //           style: const TextStyle(
                //               fontSize: 16, color: Colors.black87),
                //         ),
                //       ],
                //     ),
                //   ),
                // ),

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
                        const Text(
                          "Live brain electrical activity • ~1.5 seconds window",
                          style: TextStyle(fontSize: 14, color: Colors.black54),
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
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.warning,
                              color: Colors.red, size: 32),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              "High stress / fatigue detected for too long!\n"
                              "For safety, pull over and rest before continuing your ride.",
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

                // ────────────────────────────────────────────────
                // NEW: Button for weekly report
                // ────────────────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const WeeklyStressReport()),
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Download Weekly Report'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // Saving indicator
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
}
