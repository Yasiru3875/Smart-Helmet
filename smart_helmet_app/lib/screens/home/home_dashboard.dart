// screens/home/home_dashboard.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const String apiKey =
    'AIzaSyBbZVI_sO637CROKwc3hjMOB4ZmsL12ikw'; // Replace with your actual API key

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

  BitmapDescriptor? _motorcycleIcon;

  bool _isRoutePlanned = false;
  bool _isJourneyStarted = false;

  List<LatLng> _routePoints = [];

  Timer? _sensorTimer;
  Timer? _locationTimer;

  // Dummy sensor data
  int heartRate = 78;
  double temperature = 36.8;
  int stressLevel = 32;
  bool dangerAlert = false;

  // For place suggestions
  List<dynamic> _placeSuggestions = [];
  Timer? _debounceTimer;

  // For multiple routes
  List<Map<String, dynamic>> _routes = [];
  int _selectedRouteIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadMotorcycleIcon();
    _getCurrentLocationAndSetup();
    _destinationController.addListener(_onDestinationChanged);
  }

  Future<void> _loadMotorcycleIcon() async {
    try {
      _motorcycleIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(60, 60)),
        'assets/icons/motorcycle.png',
      );
    } catch (_) {
      _motorcycleIcon =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
    setState(() {});
  }

  Future<void> _getCurrentLocationAndSetup() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Please enable location services');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) {
      _showSnackBar('Location permissions are permanently denied');
      return;
    }

    Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = pos;
    });

    _addCurrentLocationMarker(pos);
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _addCurrentLocationMarker(Position pos) {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'current_location');
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(pos.latitude, pos.longitude),
          icon: _isJourneyStarted
              ? _motorcycleIcon!
              : BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure),
          rotation: pos.heading ?? 0.0,
          anchor: const Offset(0.5, 0.5),
          zIndex: 1000,
        ),
      );
    });
  }

  void _onDestinationChanged() {
    _debounceTimer?.cancel();
    _debounceTimer =
        Timer(const Duration(milliseconds: 300), _fetchPlaceSuggestions);
  }

  Future<void> _fetchPlaceSuggestions() async {
    final input = _destinationController.text.trim();
    if (input.isEmpty) {
      setState(() => _placeSuggestions = []);
      return;
    }

    final url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['status'] == 'OK') {
      setState(() {
        _placeSuggestions = data['predictions'];
      });
    } else {
      setState(() => _placeSuggestions = []);
    }
  }

  Future<void> _planRoute() async {
    if (_currentPosition == null ||
        _destinationController.text.trim().isEmpty) {
      _showSnackBar('Please enter a destination');
      return;
    }

    final origin =
        '${_currentPosition!.latitude},${_currentPosition!.longitude}';
    final destination = Uri.encodeComponent(_destinationController.text.trim());

    final url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&alternatives=true&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['status'] != 'OK') {
      _showSnackBar('Route not found. Check destination or internet.');
      return;
    }

    setState(() {
      _routes = List.from(data['routes']);
      _isRoutePlanned = true;
      _selectedRouteIndex = 0; // Default to first (shortest) route
      _placeSuggestions = []; // Clear suggestions
    });

    _displayRoutes();
  }

  void _displayRoutes() {
    setState(() {
      _polylines.clear();
      for (int i = 0; i < _routes.length; i++) {
        final route = _routes[i];
        final String points = route['overview_polyline']['points'];
        final List<LatLng> routePoints = _decodePolyline(points);
        final Color color =
            i == _selectedRouteIndex ? Colors.blue[700]! : Colors.grey;
        final int width = i == _selectedRouteIndex ? 8 : 4;

        _polylines.add(
          Polyline(
            polylineId: PolylineId('route_$i'),
            color: color,
            width: width,
            jointType: JointType.round,
            points: routePoints,
          ),
        );

        if (i == _selectedRouteIndex) {
          _routePoints = routePoints;
          final LatLng destinationLatLng = routePoints.last;
          _markers.add(
            Marker(
              markerId: const MarkerId('destination'),
              position: destinationLatLng,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed),
              infoWindow: InfoWindow(title: _destinationController.text.trim()),
            ),
          );

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

          _mapController
              ?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
        }
      }
    });
  }

  void _selectRoute(int index) {
    setState(() {
      _selectedRouteIndex = index;
      _markers.removeWhere((m) => m.markerId.value == 'destination');
    });
    _displayRoutes();
  }

  void _startJourney() {
    if (!_isRoutePlanned) {
      _showSnackBar(
          'Please set a route first by searching and tapping the directions icon');
      return;
    }

    setState(() => _isJourneyStarted = true);

    _locationTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_isJourneyStarted || !mounted) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        setState(() => _currentPosition = pos);
        _addCurrentLocationMarker(pos);

        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(pos.latitude, pos.longitude),
              zoom: 18.5,
              bearing: pos.heading ?? 0.0,
              tilt: 60,
            ),
          ),
        );
      } catch (_) {}
    });

    _sensorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isJourneyStarted || !mounted) return;
      final r = Random();
      setState(() {
        heartRate = 72 + r.nextInt(38);
        temperature = 36.6 + r.nextDouble() * 0.9;
        stressLevel = r.nextInt(85);
        dangerAlert = r.nextDouble() > 0.88;
      });
    });
  }

  void _endJourney() {
    setState(() {
      _isJourneyStarted = false;
      _isRoutePlanned = false;
    });
    _locationTimer?.cancel();
    _sensorTimer?.cancel();
    _polylines.clear();
    _markers.removeWhere((m) => m.markerId.value == 'destination');
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
    _debounceTimer?.cancel();
    _destinationController.removeListener(_onDestinationChanged);
    _locationTimer?.cancel();
    _sensorTimer?.cancel();
    _destinationController.dispose();
    super.dispose();
  }

  Widget _buildSensorItem(IconData icon, String value, Color color) {
    return Column(
      children: [
        Icon(icon, size: 26, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonPadding = screenWidth < 400 ? 24.0 : 40.0; // Responsive padding
    final buttonFontSize = screenWidth < 400 ? 16.0 : 18.0;

    return Scaffold(
      body: _currentPosition == null
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.indigo,
                strokeWidth: 3,
              ),
            )
          : SafeArea(
              child: Stack(
                children: [
                  // Full-screen Google Map
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(_currentPosition!.latitude,
                          _currentPosition!.longitude),
                      zoom: 16,
                    ),
                    onMapCreated: (controller) {
                      _mapController = controller;
                    },
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    tiltGesturesEnabled: true,
                    rotateGesturesEnabled: true,
                    polylines: _polylines,
                    markers: _markers,
                    padding: const EdgeInsets.only(
                        top: 120, bottom: 90), // Adjusted for no overflow
                  ),

                  // Top Control Panel - Compact & Responsive
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 8,
                        left: 12,
                        right: 12,
                        bottom: 8,
                      ),
                      child: Material(
                        elevation: 10,
                        borderRadius: BorderRadius.circular(16),
                        shadowColor: Colors.black45,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Search + Directions Icon
                              TextField(
                                controller: _destinationController,
                                textInputAction: TextInputAction.go,
                                onSubmitted: (_) => _planRoute(),
                                decoration: InputDecoration(
                                  hintText: 'Search destination',
                                  prefixIcon: const Icon(Icons.search,
                                      color: Colors.indigo),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.directions,
                                        color: Colors.indigo, size: 26),
                                    onPressed: _planRoute,
                                    tooltip: 'Plan Route',
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                ),
                              ),
                              if (_placeSuggestions.isNotEmpty)
                                Container(
                                  height: 200,
                                  color: Colors.white,
                                  child: ListView.builder(
                                    itemCount: _placeSuggestions.length,
                                    itemBuilder: (context, index) {
                                      final suggestion =
                                          _placeSuggestions[index];
                                      return ListTile(
                                        title: Text(suggestion['description']),
                                        onTap: () {
                                          _destinationController.text =
                                              suggestion['description'];
                                          _placeSuggestions = [];
                                          _planRoute();
                                        },
                                      );
                                    },
                                  ),
                                ),
                              const SizedBox(height: 12),

                              // Responsive START and END buttons
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _isJourneyStarted
                                        ? null
                                        : _startJourney,
                                    icon: const Icon(Icons.directions_bike,
                                        size: 26),
                                    label: Text(
                                      'START',
                                      style: TextStyle(
                                          fontSize: buttonFontSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green[600],
                                      foregroundColor: Colors.white,
                                      elevation: 8,
                                      padding: EdgeInsets.symmetric(
                                          horizontal: buttonPadding,
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(30)),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  ElevatedButton.icon(
                                    onPressed:
                                        _isJourneyStarted ? _endJourney : null,
                                    icon: const Icon(Icons.stop, size: 22),
                                    label: Text('END',
                                        style: TextStyle(
                                            fontSize: buttonFontSize)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red[600],
                                      foregroundColor: Colors.white,
                                      elevation: 6,
                                      padding: EdgeInsets.symmetric(
                                          horizontal: buttonPadding,
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(30)),
                                    ),
                                  ),
                                ],
                              ),
                              if (_routes.isNotEmpty)
                                SizedBox(
                                  height: 50,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _routes.length,
                                    itemBuilder: (context, index) {
                                      final route = _routes[index];
                                      final summary = route['legs'][0]
                                              ['distance']['text'] +
                                          ' - ' +
                                          route['legs'][0]['duration']['text'];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: ChoiceChip(
                                          label: Text(summary),
                                          selected:
                                              _selectedRouteIndex == index,
                                          onSelected: (selected) {
                                            if (selected) _selectRoute(index);
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Navigation Active Badge
                  if (_isJourneyStarted)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 140,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.blue[900],
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: const [
                              BoxShadow(color: Colors.black38, blurRadius: 8)
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.directions_bike,
                                  color: Colors.white, size: 28),
                              SizedBox(width: 10),
                              Text(
                                'JOURNEY ACTIVE',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Bottom Sensor Bar
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black38,
                              blurRadius: 8,
                              offset: Offset(0, -2))
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildSensorItem(
                                Icons.favorite,
                                '$heartRate bpm',
                                heartRate > 100
                                    ? Colors.red
                                    : Colors.pinkAccent),
                            _buildSensorItem(
                                Icons.thermostat,
                                '${temperature.toStringAsFixed(1)}°C',
                                temperature > 37.5
                                    ? Colors.orange
                                    : Colors.cyan),
                            _buildSensorItem(
                                Icons.psychology,
                                '$stressLevel%',
                                stressLevel > 65
                                    ? Colors.deepOrange
                                    : Colors.amber),
                            _buildSensorItem(
                              dangerAlert ? Icons.warning_amber : Icons.shield,
                              dangerAlert ? 'ALERT' : 'SAFE',
                              dangerAlert ? Colors.red : Colors.green,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
