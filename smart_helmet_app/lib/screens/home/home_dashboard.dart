// screens/home/home_dashboard.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:smart_helmet_app/models/journey_model.dart';
import 'package:smart_helmet_app/providers/journey_provider.dart';
import 'package:smart_helmet_app/services/journey_service.dart';
import 'package:smart_helmet_app/screens/home/members/Post_Journey/member3_page.dart';

const String apiKey =
    'AIzaSyBbZVI_sO637CROKwc3hjMOB4ZmsL12ikw'; // Replace with your real Google Maps API key

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  GoogleMapController? _mapController;
  Position? _currentPosition;

  final TextEditingController _destinationController = TextEditingController();

  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};

  bool _isRoutePlanned = false;
  bool _isJourneyStarted = false;

  List<LatLng> _routePoints = [];

  Timer? _sensorTimer;
  Timer? _locationTimer;

  // Dummy live sensor values
  int heartRate = 78;
  double temperature = 36.8;
  int stressLevel = 32;
  bool dangerAlert = false;

  // Journey tracking
  final JourneyService _journeyService = JourneyService();
  DateTime? _journeyStartTime;
  double _totalDistance = 0.0;
  Position? _lastPosition;
  List<double> _speedReadings = [];

  @override
  void initState() {
    super.initState();
    _getCurrentLocationAndSetup();
  }

  Future<void> _getCurrentLocationAndSetup() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location services')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = pos;
    });

    _addCurrentLocationMarker(pos);

    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 16),
        ),
      );
    }
  }

  void _addCurrentLocationMarker(Position pos) {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'current_location');
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(pos.latitude, pos.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ), // Safe blue marker
          rotation: pos.heading ?? 0.0,
          anchor: const Offset(0.5, 0.5),
          zIndex: 999,
        ),
      );
    });
  }

  Future<void> _planRoute() async {
    if (_currentPosition == null ||
        _destinationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a destination')),
      );
      return;
    }

    final origin =
        '${_currentPosition!.latitude},${_currentPosition!.longitude}';
    final destination = Uri.encodeComponent(_destinationController.text.trim());

    final url =
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=$origin&destination=$destination&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['status'] != 'OK') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find route. Check destination or API key.'),
        ),
      );
      return;
    }

    final String points = data['routes'][0]['overview_polyline']['points'];
    _routePoints = _decodePolyline(points);
    final LatLng destinationLatLng = _routePoints.last;

    setState(() {
      _isRoutePlanned = true;
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          color: Colors.blue[800]!,
          width: 8,
          points: _routePoints,
        ),
      );

      _markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destinationLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: _destinationController.text.trim()),
        ),
      );
    });

    final bounds = LatLngBounds(
      southwest: LatLng(
        min(_currentPosition!.latitude, destinationLatLng.latitude),
        min(_currentPosition!.longitude, destinationLatLng.longitude),
      ),
      northeast: LatLng(
        max(_currentPosition!.latitude, destinationLatLng.latitude),
        max(_currentPosition!.longitude, destinationLatLng.longitude),
      ),
    );

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  void _startJourney() {
    if (!_isRoutePlanned) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please set a route first')));
      return;
    }

    // Initialize journey tracking
    final journeyProvider = Provider.of<JourneyProvider>(context, listen: false);
    String? startLocation = _currentPosition != null 
        ? '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}'
        : null;
    journeyProvider.startJourney(startLocation, _destinationController.text.trim());
    
    _journeyStartTime = DateTime.now();
    _totalDistance = 0.0;
    _lastPosition = _currentPosition;
    _speedReadings = [];

    setState(() => _isJourneyStarted = true);

    _locationTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_isJourneyStarted) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        
        // Calculate distance traveled
        if (_lastPosition != null) {
          double distanceInMeters = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            pos.latitude,
            pos.longitude,
          );
          _totalDistance += distanceInMeters / 1000; // Convert to km
          _speedReadings.add(pos.speed * 3.6); // Convert m/s to km/h
        }
        _lastPosition = pos;
        
        setState(() => _currentPosition = pos);
        _addCurrentLocationMarker(pos);

        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(pos.latitude, pos.longitude),
              zoom: 18.5,
              bearing: pos.heading ?? 0.0,
              tilt: 65,
            ),
          ),
        );
      } catch (e) {
        // Ignore occasional location errors
      }
    });

    _sensorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isJourneyStarted) return;
      final r = Random();
      setState(() {
        heartRate = 72 + r.nextInt(38);
        temperature = 36.6 + r.nextDouble() * 0.9;
        stressLevel = r.nextInt(85);
        dangerAlert = r.nextDouble() > 0.88;
      });
    });
  }

  Future<void> _endJourney() async {
    // Get the journey provider and end the journey
    final journeyProvider = Provider.of<JourneyProvider>(context, listen: false);
    final completedJourney = journeyProvider.endJourney();
    
    JourneyData? savedJourney;
    
    // Save to Firebase
    if (completedJourney != null) {
      try {
        // Create final journey with distance and speed data
        savedJourney = JourneyData(
          id: completedJourney.id,
          startTime: completedJourney.startTime,
          endTime: completedJourney.endTime,
          startLocation: completedJourney.startLocation,
          destination: completedJourney.destination,
          sharpTurns: completedJourney.sharpTurns,
          riskyTurns: completedJourney.riskyTurns,
          averageSpeed: _speedReadings.isNotEmpty 
              ? _speedReadings.reduce((a, b) => a + b) / _speedReadings.length 
              : 0.0,
          totalDistance: _totalDistance,
          turnEvents: completedJourney.turnEvents,
          sensorReadings: completedJourney.sensorReadings,
        );
        
        await _journeyService.saveJourney(savedJourney);
        
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save journey: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    
    setState(() {
      _isJourneyStarted = false;
      _isRoutePlanned = false;
    });
    _locationTimer?.cancel();
    _sensorTimer?.cancel();
    _polylines.clear();
    _markers.removeWhere((m) => m.markerId.value == 'destination');
    
    // Reset journey tracking variables
    _journeyStartTime = null;
    _totalDistance = 0.0;
    _lastPosition = null;
    _speedReadings = [];
    
    // Navigate to Member3Page with the completed journey
    if (mounted && savedJourney != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Member3Page(completedJourney: savedJourney),
        ),
      );
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _sensorTimer?.cancel();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Compact sensor sidebar
                Container(
                  width: 70,
                  color: Colors.black87,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.favorite,
                        size: 34,
                        color: heartRate > 100 ? Colors.red : Colors.pinkAccent,
                      ),
                      Text(
                        '$heartRate',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Icon(
                        Icons.thermostat,
                        size: 34,
                        color: temperature > 37.5 ? Colors.orange : Colors.cyan,
                      ),
                      Text(
                        '${temperature.toStringAsFixed(1)}°',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Icon(
                        Icons.psychology,
                        size: 34,
                        color: stressLevel > 65
                            ? Colors.deepOrange
                            : Colors.amber,
                      ),
                      Text(
                        '$stressLevel%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Icon(
                        dangerAlert ? Icons.warning_amber : Icons.shield,
                        size: 34,
                        color: dangerAlert ? Colors.red : Colors.green,
                      ),
                    ],
                  ),
                ),

                // Map + Controls
                Expanded(
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          ),
                          zoom: 16,
                        ),
                        onMapCreated: (controller) {
                          _mapController = controller;
                          // Re-center after map is ready
                          _mapController?.animateCamera(
                            CameraUpdate.newCameraPosition(
                              CameraPosition(
                                target: LatLng(
                                  _currentPosition!.latitude,
                                  _currentPosition!.longitude,
                                ),
                                zoom: 16,
                              ),
                            ),
                          );
                        },
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        polylines: _polylines,
                        markers: _markers,
                        tiltGesturesEnabled: true,
                        rotateGesturesEnabled: true,
                      ),

                      // Top control card
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 10,
                        left: 16,
                        right: 16,
                        child: Card(
                          elevation: 10,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _destinationController,
                                  decoration: InputDecoration(
                                    hintText: 'Where are you going?',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.directions),
                                      onPressed: _planRoute,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onSubmitted: (_) => _planRoute(),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _isJourneyStarted
                                          ? null
                                          : _planRoute,
                                      icon: const Icon(Icons.route),
                                      label: const Text('SET ROUTE'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                          255,
                                          0,
                                          12,
                                          78,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _isJourneyStarted
                                          ? null
                                          : _startJourney,
                                      icon: const Icon(
                                        Icons.navigation,
                                        size: 28,
                                      ),
                                      label: const Text('START'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green[600],
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 30,
                                          vertical: 16,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _isJourneyStarted
                                          ? _endJourney
                                          : null,
                                      icon: const Icon(Icons.stop),
                                      label: const Text('END'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Navigation active badge
                      if (_isJourneyStarted)
                        Positioned(
                          top: 190,
                          left: 20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[900],
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.navigation,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'NAVIGATION ON',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
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
              ],
            ),
    );
  }
}
