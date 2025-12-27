// member4.dart (Final Updated Version)
import 'dart:async';
// member4.dart (Updated with Custom Motorcycle Icon)

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:flutter_tts/flutter_tts.dart';
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
  bool showTips = false;

  List<String> safetyTips = [];

  final CameraPosition initialPosition = const CameraPosition(
    target: LatLng(6.9271, 79.8612), // Colombo
    zoom: 12,
  );

  late FlutterTts flutterTts;

  // Live sensor data
  int heartRate = 78;
  double temperature = 36.8;
  int stressLevel = 32;
  bool dangerAlert = false;

  int? pastHeartRate;
  double? pastTemperature;
  int? pastStressLevel;
  bool? pastDangerAlert;

  String? weather;
  String? traffic;

  Timer? _sensorTimer;
  Timer? _locationTimer;

  String? destKey;

  // Custom motorcycle icon
  BitmapDescriptor? _motorcycleIcon;

  @override
  void initState() {
    super.initState();

    // Android optimization
    if (defaultTargetPlatform == TargetPlatform.android) {
      final GoogleMapsFlutterPlatform mapsImplementation = GoogleMapsFlutterPlatform.instance;
      if (mapsImplementation is GoogleMapsFlutterAndroid) {
        mapsImplementation.useAndroidViewSurface = true;
      }
    }

    flutterTts = FlutterTts();

    // Load custom motorcycle icon
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
      recentlyUsed = Random().nextBool();
    }

    if (isPredefined) {
      startPoint = widget.predefinedStart;
      endPoint = widget.predefinedEnd;
      _addStartEndMarkers();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        analyzeRoute(widget.predefinedRoute!);
      });
    }

    if (widget.startJourney) {
      _startLiveUpdates();
    }
  }

  Future<void> _loadMotorcycleIcon() async {
    try {
      _motorcycleIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/icons/motorcycle.png',
      );
    } catch (e) {
      // Fallback if asset not found
      _motorcycleIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
    if (mounted) setState(() {});
  }

  void _addStartEndMarkers() {
    markers.add(
      Marker(
        markerId: const MarkerId('start'),
        position: startPoint!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Start'),
      ),
    );

    markers.add(
      Marker(
        markerId: const MarkerId('end'),
        position: endPoint!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: widget.destinationName ?? 'Destination'),
      ),
    );
  }

  void _startLiveUpdates() async {
    currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    _updateCurrentMarker();

    _locationTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      try {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
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
        icon: _motorcycleIcon!, // Custom motorcycle icon
        rotation: currentPosition!.heading ?? 0.0, // Rotates with direction
        anchor: const Offset(0.5, 0.5), // Center of image
        zIndex: 1000,
      ),
    );

    setState(() {}); // Ensure UI updates
  }

  void analyzeRoute(List<LatLng> routeSegments) {
    polylines.clear();
    safetyTips.clear();

    for (int i = 0; i < routeSegments.length - 1; i++) {
      double riskScore = calculateRiskScore(i);

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

    generateSafetyTips();
    _zoomToFitRoute();
    setState(() {});

    _speakSafetyTips();
  }

  void _zoomToFitRoute() {
    if (startPoint == null || endPoint == null || mapController == null) return;

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(min(startPoint!.latitude, endPoint!.latitude), min(startPoint!.longitude, endPoint!.longitude)),
      northeast: LatLng(max(startPoint!.latitude, endPoint!.latitude), max(startPoint!.longitude, endPoint!.longitude)),
    );

    mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  double calculateRiskScore(int segmentIndex) {
    double baseRisk = 0.3 + Random().nextDouble() * 0.5;

    if (recentlyUsed && destKey == 'kaduwela') {
      if (segmentIndex % 4 == 0 || segmentIndex % 7 == 2) baseRisk += 0.4;
      baseRisk += 0.2;
    } else if (!recentlyUsed && destKey == 'malabe') {
      baseRisk *= 0.6;
    }

    return baseRisk.clamp(0.0, 1.0);
  }

  Color getRiskColor(double risk) {
    if (risk < 0.4) return Colors.green;
    if (risk < 0.7) return Colors.orange;
    return Colors.red;
  }

  void generateSafetyTips() {
    safetyTips.add('Wear helmet properly at all times');

    if (recentlyUsed && destKey == 'kaduwela') {
      final sensor = dummyData['kaduwela']!['sensorData'];
      pastHeartRate = sensor['heartRate'];
      pastTemperature = sensor['temperature'];
      pastStressLevel = sensor['stressLevel'];
      pastDangerAlert = sensor['dangerAlert'];

      safetyTips.addAll([
        'This route was recently used by you',
        'Past ride data:',
        '• Heart Rate: $pastHeartRate bpm',
        '• Temperature: $pastTemperature°C',
        '• Stress Level: $pastStressLevel%',
        if (pastDangerAlert!) '• Danger alert triggered in past ride',
        'High-risk zones marked in red — stay extra vigilant',
      ]);
    } else if (!recentlyUsed && destKey == 'malabe') {
      final data = dummyData['malabe']!;
      weather = data['weather'];
      traffic = data['traffic'];

      safetyTips.addAll([
        'This is a new route',
        'Current conditions:',
        '• Weather: $weather',
        '• Traffic: $traffic',
        'Generally low-risk route',
      ]);
    } else {
      safetyTips.add(recentlyUsed
          ? 'Familiar route — known danger zones highlighted'
          : 'New route — proceed with standard caution');
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
            onMapCreated: (controller) => mapController = controller,
            markers: markers,
            polylines: polylines,
            myLocationEnabled: false, // Disable default blue dot
            myLocationButtonEnabled: true,
            compassEnabled: true,
            zoomControlsEnabled: true,
            trafficEnabled: true,
            mapToolbarEnabled: false,
          ),

          // Live Sensor Overlay
          if (widget.startJourney)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Live Sensors', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.favorite, color: heartRate > 100 ? Colors.red : Colors.pink, size: 20),
                      Text(' $heartRate bpm', style: const TextStyle(color: Colors.white)),
                    ]),
                    Row(children: [
                      Icon(Icons.thermostat, color: temperature > 37.5 ? Colors.orange : Colors.cyan, size: 20),
                      Text(' ${temperature.toStringAsFixed(1)}°C', style: const TextStyle(color: Colors.white)),
                    ]),
                    Row(children: [
                      Icon(Icons.psychology, color: stressLevel > 65 ? Colors.deepOrange : Colors.amber, size: 20),
                      Text(' $stressLevel%', style: const TextStyle(color: Colors.white)),
                    ]),
                  ],
                ),
              ),
            ),

          // Legend
          Positioned(
            bottom: showTips ? 220 : 140,
            left: 16,
            right: 16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: const [
                    LegendItem(color: Colors.green, label: 'Low Risk'),
                    LegendItem(color: Colors.orange, label: 'Medium Risk'),
                    LegendItem(color: Colors.red, label: 'High Risk'),
                  ],
                ),
              ),
            ),
          ),

          // View/Hide Tips Button
          if (safetyTips.isNotEmpty)
            Positioned(
              bottom: showTips ? 160 : 80,
              left: 16,
              right: 16,
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => showTips = !showTips),
                  icon: Icon(showTips ? Icons.keyboard_arrow_down : Icons.security, size: 20),
                  label: Text(showTips ? 'Hide Safety Tips' : 'View Safety Tips'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ),
            ),

          // Safety Tips Panel
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
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.security, color: Colors.white),
                          const SizedBox(width: 10),
                          const Text('Safety Recommendations', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
                                const Text('• ', style: TextStyle(fontSize: 18, color: Colors.deepPurple)),
                                Expanded(child: Text(safetyTips[index], style: const TextStyle(fontSize: 15))),
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
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}