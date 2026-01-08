import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dummy_data.dart';

class Member4Page extends StatefulWidget {
  final LatLng? predefinedStart;
  final LatLng? predefinedEnd;
  final List<LatLng>? predefinedRoute;
  final String? destinationName;
  final bool startJourney;

  const Member4Page({
    super.key,
    this.predefinedStart,
    this.predefinedEnd,
    this.predefinedRoute,
    this.destinationName,
    this.startJourney = false,
  });

  @override
  State<Member4Page> createState() => _Member4PageState();
}

class _Member4PageState extends State<Member4Page> {
  GoogleMapController? mapController;
  LatLng? startPoint;
  LatLng? endPoint;
  Position? currentPosition;
  final Set<Marker> markers = {};
  final Set<Polyline> polylines = {};
  bool recentlyUsed = false;
  bool isPredefined = false;
  bool isDummyRoute = false;
  bool showTips = false;
  List<String> safetyTips = [];
  final CameraPosition initialPosition = const CameraPosition(
    target: LatLng(6.9271, 79.8612), // Colombo
    zoom: 12,
  );
  late FlutterTts flutterTts;

  // Live sensor data (simulated)
  int heartRate = 78;
  double temperature = 36.8;
  int stressLevel = 32;
  bool dangerAlert = false;
  int? pastHeartRate;
  double? pastTemperature;
  int? pastStressLevel;
  bool? pastDangerAlert;
  Timer? _sensorTimer;
  Timer? _locationTimer;
  String? destKey;

  // Custom motorcycle icon
  BitmapDescriptor? _motorcycleIcon;

  // TFLite
  Interpreter? _interpreter;
  double? _predictedRisk;

  // Model preprocessing constants
  static const List<String> numericalCols = [
    'Location_Latitude',
    'Location_Longitude',
    'Temperature',
    'Humidity',
    'Wind_Speed',
    'Precipitation',
    'Visibility',
    'Traffic_Speed',
    'Travel_Time_Estimate'
  ];

  static const List<String> categoricalCols = [
    'Weather_Condition',
    'Congestion_Level',
    'Road_Type'
  ];

  static const List<String> weatherConditions = [
    'Clear',
    'Cloudy',
    'Overcast',
    'Rainy',
    'Snowy',
    'Foggy'
  ];

  static const List<String> congestionLevels = ['Low', 'Medium', 'High'];

  static const List<String> roadTypes = [
    'Highway',
    'Residential',
    'Commercial',
    'Rural',
    'Urban',
    'Busy urban',
    'Narrow paths',
    'Heavy traffic',
    'Poor lighting road'
  ];

  static final List<String> catColumns = [
    ...weatherConditions.map((e) => 'Weather_Condition_$e'),
    ...congestionLevels.map((e) => 'Congestion_Level_$e'),
    ...roadTypes.map((e) => 'Road_Type_$e'),
  ];

  static const Map<String, double> numMeans = {
    'Location_Latitude': 40.0,
    'Location_Longitude': -74.0,
    'Temperature': 20.0,
    'Humidity': 60.0,
    'Wind_Speed': 10.0,
    'Precipitation': 0.5,
    'Visibility': 8000.0,
    'Traffic_Speed': 40.0,
    'Travel_Time_Estimate': 60.0,
  };

  static const Map<String, double> numScales = {
    'Location_Latitude': 5.0,
    'Location_Longitude': 5.0,
    'Temperature': 10.0,
    'Humidity': 20.0,
    'Wind_Speed': 5.0,
    'Precipitation': 1.0,
    'Visibility': 3000.0,
    'Traffic_Speed': 15.0,
    'Travel_Time_Estimate': 30.0,
  };

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final GoogleMapsFlutterPlatform mapsImplementation =
          GoogleMapsFlutterPlatform.instance;
      if (mapsImplementation is GoogleMapsFlutterAndroid) {
        mapsImplementation.useAndroidViewSurface = true;
      }
    }
    flutterTts = FlutterTts();
    _loadMotorcycleIcon();

    isPredefined = widget.predefinedRoute != null;
    final String destLower = (widget.destinationName ?? '').toLowerCase();
    if (destLower.contains('kaduwela')) {
      destKey = 'kaduwela';
      recentlyUsed = true;
    } else if (destLower.contains('malabe')) {
      destKey = 'malabe';
      recentlyUsed = false;
    } else {
      destKey = null;
      recentlyUsed = false;
    }
    isDummyRoute = destKey != null;

    if (isPredefined) {
      startPoint = widget.predefinedStart;
      endPoint = widget.predefinedEnd;
      _addStartEndMarkers();
    }

    // Load model first, then analyze route if needed
    _loadModel().then((_) {
      if (isPredefined && widget.predefinedRoute != null) {
        analyzeRoute(widget.predefinedRoute!);
      }
    });

    if (widget.startJourney) {
      _startLiveUpdates();
    }
  }

  Future<void> _loadModel() async {
    try {
      print('Attempting to load TFLite model...');
      _interpreter =
          await Interpreter.fromAsset('assets/route_risk_model.tflite');
      print('✅ TFLite model loaded successfully!');
      final input = _interpreter!.getInputTensors()[0];
      final output = _interpreter!.getOutputTensors()[0];
      print('Input shape: ${input.shape}');
      print('Output shape: ${output.shape}');
    } catch (e, stack) {
      print('❌ Failed to load model: $e');
      print(stack);
    }
  }

  Future<void> _loadMotorcycleIcon() async {
    try {
      _motorcycleIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/icons/motorcycle.png',
      );
    } catch (e) {
      _motorcycleIcon =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
    if (mounted) setState(() {});
  }

  void _addStartEndMarkers() {
    if (startPoint != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: startPoint!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Start'),
        ),
      );
    }
    if (endPoint != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('end'),
          position: endPoint!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow:
              InfoWindow(title: widget.destinationName ?? 'Destination'),
        ),
      );
    }
  }

  void _startLiveUpdates() async {
    try {
      currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _updateCurrentMarker();
    } catch (e) {
      print('Location error: $e');
    }
    _locationTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        setState(() => currentPosition = pos);
        _updateCurrentMarker();
        mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(pos.latitude, pos.longitude),
              zoom: 17,
              bearing: pos.heading ?? 0.0,
              tilt: 45,
            ),
          ),
        );
      } catch (_) {}
    });
    _sensorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final r = Random();
      setState(() {
        heartRate = 72 + r.nextInt(38);
        temperature = 36.6 + r.nextDouble() * 0.9;
        stressLevel = r.nextInt(85);
        dangerAlert = r.nextDouble() > 0.88;
      });
    });
  }

  void _updateCurrentMarker() {
    if (currentPosition == null || _motorcycleIcon == null) return;
    markers.removeWhere((m) => m.markerId.value == 'current');
    markers.add(
      Marker(
        markerId: const MarkerId('current'),
        position: LatLng(currentPosition!.latitude, currentPosition!.longitude),
        icon: _motorcycleIcon!,
        rotation: currentPosition!.heading ?? 0.0,
        anchor: const Offset(0.5, 0.5),
        zIndex: 1000,
      ),
    );
    if (mounted) setState(() {});
  }

  // Temporary hardcoded high-risk route for testing
  Map<String, dynamic> generateRandomRouteDict(List<LatLng> routeSegments) {
    final r = Random();

    // Use first point of route as location, fallback to Colombo
    double lat =
        routeSegments.isNotEmpty ? routeSegments.first.latitude : 6.9271;
    double lng =
        routeSegments.isNotEmpty ? routeSegments.first.longitude : 79.8612;

    // Calculate total route distance in km
    double routeLengthKm = 0.0;
    for (int i = 0; i < routeSegments.length - 1; i++) {
      routeLengthKm += Geolocator.distanceBetween(
            routeSegments[i].latitude,
            routeSegments[i].longitude,
            routeSegments[i + 1].latitude,
            routeSegments[i + 1].longitude,
          ) /
          1000.0; // meters → km
    }

    // Estimate travel time in minutes (average speed 40 km/h for motorcycle in mixed conditions)
    double travelTimeMinutes = (routeLengthKm / 40.0) * 60.0;
    if (travelTimeMinutes < 10) travelTimeMinutes = 10; // minimum
    if (travelTimeMinutes > 180) travelTimeMinutes = 180; // cap at 3 hours

    // Random realistic environmental & traffic data
    return {
      'Location_Latitude': lat,
      'Location_Longitude': lng,
      'Temperature':
          24.0 + r.nextDouble() * 10.0, // 24–34°C (typical tropical range)
      'Humidity': 60.0 + r.nextDouble() * 30.0, // 60–90%
      'Wind_Speed': r.nextDouble() * 25.0, // 0–25 km/h
      'Precipitation': r.nextDouble() * 2.5, // 0–2.5 mm/h
      'Visibility': 3000 + r.nextDouble() * 12000, // 3–15 km
      'Traffic_Speed': 20.0 + r.nextDouble() * 50.0, // 20–70 km/h
      'Travel_Time_Estimate': travelTimeMinutes.roundToDouble(),
      'Weather_Condition':
          weatherConditions[r.nextInt(weatherConditions.length)],
      'Congestion_Level': congestionLevels[r.nextInt(congestionLevels.length)],
      'Road_Type': roadTypes[r.nextInt(roadTypes.length)],
    };
  }

  double? predictRouteRisk(Map<String, dynamic> routeDict) {
    if (_interpreter == null) {
      print('Warning: Model not loaded yet');
      return null;
    }

    try {
      List<double> inputNum = [];
      for (var col in numericalCols) {
        var value = routeDict[col];
        double numValue = 0.0;
        if (value is num) {
          numValue = value.toDouble();
        } else if (value is String) {
          numValue = double.tryParse(value) ?? 0.0;
        }
        double mean = numMeans[col] ?? 0.0;
        double scale = numScales[col] ?? 1.0;
        inputNum.add((numValue - mean) / scale);
      }

      List<double> inputCatVec = List.filled(catColumns.length, 0.0);
      for (var col in categoricalCols) {
        String? val = routeDict[col]?.toString().trim();
        if (val != null && val.isNotEmpty) {
          String key = '${col}_$val';
          int index = catColumns.indexOf(key);
          if (index != -1) {
            inputCatVec[index] = 1.0;
          }
        }
      }

      List<double> inputFlat = [...inputNum, ...inputCatVec];
      if (inputFlat.length != 27) {
        print('ERROR: Input length ${inputFlat.length}, expected 27');
        return null;
      }

      var input = [inputFlat];
      var output = List.generate(1, (_) => List<double>.filled(1, 0.0));

      _interpreter!.run(input, output);

      double prob = output[0][0].clamp(0.0, 1.0);
      print('Model prediction: ${(prob * 100).toStringAsFixed(1)}% risk');
      return prob;
    } catch (e, stack) {
      print('Inference error: $e');
      print(stack);
      return null;
    }
  }

  List<String> getSafetySuggestions(
      double prob, Map<String, dynamic> routeDict) {
    List<String> suggestions = [];
    bool isRisky = prob > 0.5;

    suggestions.add(
      'Predicted Risk Probability: ${(prob * 100).toStringAsFixed(1)}% → ${isRisky ? "Risky" : "Safe"}',
    );

    String weather = (routeDict['Weather_Condition'] as String?) ?? 'Unknown';
    String cong = (routeDict['Congestion_Level'] as String?) ?? 'Unknown';
    double precipitation =
        (routeDict['Precipitation'] as num?)?.toDouble() ?? 0.0;
    double visibility =
        (routeDict['Visibility'] as num?)?.toDouble() ?? 10000.0;
    String roadType = (routeDict['Road_Type'] as String?) ?? '';
    double travelTime =
        (routeDict['Travel_Time_Estimate'] as num?)?.toDouble() ?? 0.0;

    suggestions.add("• Weather: $weather");
    suggestions.add("• Traffic Congestion: $cong");

    if (isRisky) {
      suggestions.add(
          "***General Advice:*** Wear your helmet properly, avoid distractions, and stay hydrated.");

      if (['Rainy', 'Snowy', 'Foggy'].contains(weather)) {
        suggestions.add(
            "• Adverse weather: Reduce speed, increase following distance, and use appropriate lights.");
      }
      if (precipitation > 0.5) {
        suggestions.add(
            "• Precipitation detected: Roads may be slippery — brake gently.");
      }
      if (visibility < 5000) {
        suggestions.add("• Low visibility: Drive slowly and use headlights.");
      }
      if (cong == 'High') {
        suggestions.add(
            "• High congestion: Anticipate sudden stops and maintain safe distance.");
      }
      if (['Narrow paths', 'Heavy traffic', 'Busy urban', 'Poor lighting road']
          .contains(roadType)) {
        suggestions.add(
            "• Challenging road ($roadType): Stay extra vigilant; consider a safer alternative route.");
      }
      if (travelTime > 90) {
        suggestions
            .add("• Long travel time: Plan regular breaks to avoid fatigue.");
      }
    } else {
      suggestions.add(
          "Route appears Safe. Still follow basic safety: Wear helmet, obey traffic rules, and ride defensively.");
    }

    return suggestions;
  }

  void analyzeRoute(List<LatLng> routeSegments) {
    polylines.clear();
    safetyTips.clear();
    _predictedRisk = null;

    if (routeSegments.length < 2) {
      if (mounted) setState(() {});
      return;
    }

    Map<String, dynamic> routeDict = {};
    if (isDummyRoute && destKey != null && dummyData.containsKey(destKey)) {
      routeDict = Map.from(dummyData[destKey]?['features'] ?? {});
      if (!recentlyUsed) {
        safetyTips.add("Based on another member's journey data");
      }
    } else {
      routeDict = generateRandomRouteDict(routeSegments);
    }

    _predictedRisk = predictRouteRisk(routeDict);

    if (_predictedRisk != null) {
      safetyTips.addAll(getSafetySuggestions(_predictedRisk!, routeDict));
    } else {
      safetyTips.add('No AI risk prediction available');
    }

    if (recentlyUsed) {
      double baseRisk = _predictedRisk ?? 0.5;
      for (int i = 0; i < routeSegments.length - 1; i++) {
        double riskScore = calculateRiskScore(i, baseRisk);
        polylines.add(
          Polyline(
            polylineId: PolylineId('segment_$i'),
            points: [routeSegments[i], routeSegments[i + 1]],
            color: getRiskColor(riskScore),
            width: 10,
            jointType: JointType.round,
            zIndex: 10,
          ),
        );
      }
    } else {
      Color routeColor = getRiskColor(_predictedRisk ?? 0.5);
      polylines.add(
        Polyline(
          polylineId: const PolylineId('full_route'),
          points: routeSegments,
          color: routeColor,
          width: 10,
          jointType: JointType.round,
          zIndex: 10,
        ),
      );
    }

    if (mapController != null && routeSegments.isNotEmpty) {
      double minLat = routeSegments.map((p) => p.latitude).reduce(min);
      double maxLat = routeSegments.map((p) => p.latitude).reduce(max);
      double minLng = routeSegments.map((p) => p.longitude).reduce(min);
      double maxLng = routeSegments.map((p) => p.longitude).reduce(max);

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
      mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    }

    generateSafetyTips();
    if (mounted) setState(() {});
    _speakSafetyTips();
  }

  double calculateRiskScore(int segmentIndex, double baseRisk) {
    double riskScore = baseRisk;
    if (recentlyUsed && destKey == 'kaduwela') {
      if (pastDangerAlert == true) riskScore += 0.3;
      if (pastStressLevel != null && pastStressLevel! > 60) riskScore += 0.2;
      if (pastHeartRate != null && pastHeartRate! > 90) riskScore += 0.1;
      if (pastTemperature != null && pastTemperature! > 37.5) riskScore += 0.1;
    }
    riskScore += (Random().nextDouble() * 0.2 - 0.1);
    return riskScore.clamp(0.0, 1.0);
  }

  Color getRiskColor(double risk) {
    if (risk < 0.4) return Colors.green;
    if (risk < 0.7) return Colors.orange;
    return Colors.red;
  }

  void generateSafetyTips() {
    if (recentlyUsed &&
        destKey == 'kaduwela' &&
        dummyData['kaduwela'] != null) {
      final sensor =
          dummyData['kaduwela']!['sensorData'] as Map<String, dynamic>;
      pastHeartRate = sensor['heartRate'] as int?;
      pastTemperature = sensor['temperature'] as double?;
      pastStressLevel = sensor['stressLevel'] as int?;
      pastDangerAlert = sensor['dangerAlert'] as bool?;
      safetyTips.insert(0, 'This route was recently used by you');
      safetyTips.addAll([
        'Past ride data:',
        if (pastHeartRate != null) '• Heart Rate: $pastHeartRate bpm',
        if (pastTemperature != null) '• Temperature: $pastTemperature°C',
        if (pastStressLevel != null) '• Stress Level: $pastStressLevel%',
      ]);
      if (pastDangerAlert == true) {
        safetyTips
            .add('• Danger alert triggered in past ride - be extra careful');
      }
      safetyTips.add('High-risk zones marked in red — stay extra vigilant');
    } else {
      safetyTips.insert(0, 'This is a new route');
    }
  }

  void _speakSafetyTips() async {
    if (safetyTips.isNotEmpty) {
      String tipsText = safetyTips.join('. ');
      await flutterTts.speak(tipsText);
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _sensorTimer?.cancel();
    flutterTts.stop();
    _interpreter?.close();
    mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: initialPosition,
            onMapCreated: (controller) {
              if (mapController == null) {
                setState(() {
                  mapController = controller;
                });
              }
            },
            markers: markers,
            polylines: polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: true,
            compassEnabled: true,
            zoomControlsEnabled: true,
            trafficEnabled: true,
            mapToolbarEnabled: false,
          ),
          if (widget.startJourney)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 10)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Live Sensors',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.favorite,
                          color: heartRate > 100 ? Colors.red : Colors.pink,
                          size: 20),
                      Text(' $heartRate bpm',
                          style: const TextStyle(color: Colors.white)),
                    ]),
                    Row(children: [
                      Icon(Icons.thermostat,
                          color:
                              temperature > 37.5 ? Colors.orange : Colors.cyan,
                          size: 20),
                      Text(' ${temperature.toStringAsFixed(1)}°C',
                          style: const TextStyle(color: Colors.white)),
                    ]),
                    Row(children: [
                      Icon(Icons.psychology,
                          color: stressLevel > 65
                              ? Colors.deepOrange
                              : Colors.amber,
                          size: 20),
                      Text(' $stressLevel%',
                          style: const TextStyle(color: Colors.white)),
                    ]),
                  ],
                ),
              ),
            ),
          if (_predictedRisk != null || recentlyUsed)
            Positioned(
              bottom: showTips ? 220 : 140,
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 8)
                    ],
                  ),
                  child: recentlyUsed
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: const [
                            LegendItem(color: Colors.green, label: 'Low Risk'),
                            LegendItem(
                                color: Colors.orange, label: 'Medium Risk'),
                            LegendItem(color: Colors.red, label: 'High Risk'),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            LegendItem(
                              color: getRiskColor(_predictedRisk ?? 0.5),
                              label: 'Predicted Risk',
                            ),
                          ],
                        ),
                ),
              ),
            ),
          if (safetyTips.isNotEmpty)
            Positioned(
              bottom: showTips ? 160 : 80,
              left: 16,
              right: 16,
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => showTips = !showTips),
                  icon: Icon(
                      showTips ? Icons.keyboard_arrow_down : Icons.security,
                      size: 20),
                  label:
                      Text(showTips ? 'Hide Safety Tips' : 'View Safety Tips'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ),
            ),
          if (showTips && safetyTips.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 80,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.45,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12)],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.deepPurple,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.security, color: Colors.white),
                          const SizedBox(width: 10),
                          const Text('Safety Recommendations',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => setState(() => showTips = false),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: safetyTips.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ',
                                    style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.deepPurple)),
                                Expanded(
                                    child: Text(safetyTips[index],
                                        style: const TextStyle(fontSize: 15))),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const LegendItem({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 1),
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
