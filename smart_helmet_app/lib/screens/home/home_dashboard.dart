// home_dashboard.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const String apiKey = 'AIzaSyBbZVI_sO637CROKwc3hjMOB4ZmsL12ikw';

class HomeDashboard extends StatefulWidget {
  final Function({
    required LatLng start,
    required LatLng end,
    required List<LatLng> route,
    required String destinationName,
  }) onStartJourney;

  // NEW: Callback to end journey from parent
  final VoidCallback? onEndJourney;

  // NEW: To know if journey is active (controlled by parent)
  final bool isJourneyActive;

  const HomeDashboard({
    super.key,
    required this.onStartJourney,
    this.onEndJourney,
    this.isJourneyActive = false,
  });

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
  bool _isJourneyStarted = false; // Local state synced with parent

  List<LatLng> _routePoints = [];

  Timer? _sensorTimer;
  Timer? _locationTimer;

  int heartRate = 78;
  double temperature = 36.8;
  int stressLevel = 32;
  bool dangerAlert = false;

  List<dynamic> _placeSuggestions = [];
  Timer? _debounceTimer;

  List<Map<String, dynamic>> _routes = [];
  int _selectedRouteIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadMotorcycleIcon();
    _getCurrentLocationAndSetup();
    _destinationController.addListener(_onDestinationChanged);

    // Sync with parent
    _isJourneyStarted = widget.isJourneyActive;
  }

  @override
  void didUpdateWidget(covariant HomeDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isJourneyActive != oldWidget.isJourneyActive) {
      setState(() {
        _isJourneyStarted = widget.isJourneyActive;
      });
    }
  }

  Future<void> _loadMotorcycleIcon() async {
    try {
      _motorcycleIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(60, 60)),
        'assets/icons/motorcycle.png',
      );
    } catch (_) {
      _motorcycleIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
    if (mounted) setState(() {});
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

    Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() => _currentPosition = pos);
    _addCurrentLocationMarker(pos);
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _addCurrentLocationMarker(Position pos) {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'current_location');
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(pos.latitude, pos.longitude),
          icon: _isJourneyStarted ? (_motorcycleIcon ?? BitmapDescriptor.defaultMarker) : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          rotation: pos.heading ?? 0.0,
          anchor: const Offset(0.5, 0.5),
          zIndex: 1000,
        ),
      );
    });
  }

  void _onDestinationChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), _fetchPlaceSuggestions);
  }

  Future<void> _fetchPlaceSuggestions() async {
    final input = _destinationController.text.trim();
    if (input.isEmpty) {
      setState(() => _placeSuggestions = []);
      return;
    }

    final url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$apiKey';
    final response = await http.get(Uri.parse(url));
    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['status'] == 'OK') {
      setState(() => _placeSuggestions = data['predictions']);
    } else {
      setState(() => _placeSuggestions = []);
    }
  }

  Future<void> _planRoute() async {
    if (_currentPosition == null || _destinationController.text.trim().isEmpty) {
      _showSnackBar('Please enter a destination');
      return;
    }

    final origin = '${_currentPosition!.latitude},${_currentPosition!.longitude}';
    final destination = Uri.encodeComponent(_destinationController.text.trim());

    final url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&alternatives=true&key=$apiKey';
    final response = await http.get(Uri.parse(url));
    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['status'] != 'OK') {
      _showSnackBar('Route not found. Check destination or internet.');
      return;
    }

    setState(() {
      _routes = List.from(data['routes']);
      _isRoutePlanned = true;
      _selectedRouteIndex = 0;
      _placeSuggestions = [];
    });

    _displayRoutes();
  }

  void _displayRoutes() {
    setState(() {
      _polylines.clear();
      for (int i = 0; i < _routes.length; i++) {
        final route = _routes[i];
        final points = route['overview_polyline']['points'];
        final routePoints = _decodePolyline(points);
        final color = i == _selectedRouteIndex ? Colors.blue[700]! : Colors.grey;
        final width = i == _selectedRouteIndex ? 8 : 4;

        _polylines.add(Polyline(
          polylineId: PolylineId('route_$i'),
          color: color,
          width: width,
          jointType: JointType.round,
          points: routePoints,
        ));

        if (i == _selectedRouteIndex) {
          _routePoints = routePoints;
          final dest = routePoints.last;
          _markers.add(Marker(
            markerId: const MarkerId('destination'),
            position: dest,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: _destinationController.text.trim()),
          ));

          final bounds = LatLngBounds(
            southwest: LatLng(min(_currentPosition!.latitude, dest.latitude), min(_currentPosition!.longitude, dest.longitude)),
            northeast: LatLng(max(_currentPosition!.latitude, dest.latitude), max(_currentPosition!.longitude, dest.longitude)),
          );
          _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
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
      _showSnackBar('Please set a route first');
      return;
    }

    widget.onStartJourney(
      start: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      end: _routePoints.last,
      route: _routePoints,
      destinationName: _destinationController.text.trim(),
    );

    setState(() => _isJourneyStarted = true);
  }

  void _endJourney() {
    // Call parent callback if provided
    widget.onEndJourney?.call();

    setState(() {
      _isJourneyStarted = false;
      _isRoutePlanned = false;
    });
    _locationTimer?.cancel();
    _sensorTimer?.cancel();
    _polylines.clear();
    _markers.removeWhere((m) => m.markerId.value == 'destination' || m.markerId.value == 'current_location');
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
    return Column(children: [
      Icon(icon, size: 26, color: color),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonPadding = screenWidth < 400 ? 24.0 : 40.0;
    final buttonFontSize = screenWidth < 400 ? 16.0 : 18.0;

    return Scaffold(
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo, strokeWidth: 3))
          : SafeArea(
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude), zoom: 16),
                    onMapCreated: (controller) => _mapController = controller,
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    tiltGesturesEnabled: true,
                    rotateGesturesEnabled: true,
                    polylines: _polylines,
                    markers: _markers,
                    padding: const EdgeInsets.only(top: 120, bottom: 90),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, left: 12, right: 12, bottom: 8),
                      child: Material(
                        elevation: 10,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            TextField(
                              controller: _destinationController,
                              textInputAction: TextInputAction.go,
                              onSubmitted: (_) => _planRoute(),
                              decoration: InputDecoration(
                                hintText: 'Search destination',
                                prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                                suffixIcon: IconButton(icon: const Icon(Icons.directions, color: Colors.indigo, size: 26), onPressed: _planRoute),
                                filled: true,
                                fillColor: Colors.grey[50],
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              ),
                            ),
                            if (_placeSuggestions.isNotEmpty)
                              Container(
                                height: 200,
                                color: Colors.white,
                                child: ListView.builder(
                                  itemCount: _placeSuggestions.length,
                                  itemBuilder: (context, index) {
                                    final s = _placeSuggestions[index];
                                    return ListTile(
                                      title: Text(s['description']),
                                      onTap: () {
                                        _destinationController.text = s['description'];
                                        _placeSuggestions = [];
                                        _planRoute();
                                      },
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: 12),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              ElevatedButton.icon(
                                onPressed: _isJourneyStarted ? null : _startJourney,
                                icon: const Icon(Icons.directions_bike, size: 26),
                                label: Text('START', style: TextStyle(fontSize: buttonFontSize, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[600], foregroundColor: Colors.white, padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton.icon(
                                onPressed: _isJourneyStarted ? _endJourney : null, // Enabled when journey active
                                icon: const Icon(Icons.stop, size: 22),
                                label: Text('END', style: TextStyle(fontSize: buttonFontSize)),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red[600], foregroundColor: Colors.white, padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                              ),
                            ]),
                            if (_routes.isNotEmpty)
                              SizedBox(
                                height: 50,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _routes.length,
                                  itemBuilder: (context, index) {
                                    final r = _routes[index];
                                    final summary = '${r['legs'][0]['distance']['text']} - ${r['legs'][0]['duration']['text']}';
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: ChoiceChip(label: Text(summary), selected: _selectedRouteIndex == index, onSelected: (s) => s ? _selectRoute(index) : null),
                                    );
                                  },
                                ),
                              ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  if (_isJourneyStarted)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 140,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(color: Colors.blue[900], borderRadius: BorderRadius.circular(30), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)]),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.directions_bike, color: Colors.white, size: 28),
                            SizedBox(width: 10),
                            Text('JOURNEY ACTIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          ]),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, -2))]),
                      child: SafeArea(top: false, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        _buildSensorItem(Icons.favorite, '$heartRate bpm', heartRate > 100 ? Colors.red : Colors.pinkAccent),
                        _buildSensorItem(Icons.thermostat, '${temperature.toStringAsFixed(1)}°C', temperature > 37.5 ? Colors.orange : Colors.cyan),
                        _buildSensorItem(Icons.psychology, '$stressLevel%', stressLevel > 65 ? Colors.deepOrange : Colors.amber),
                        _buildSensorItem(dangerAlert ? Icons.warning_amber : Icons.shield, dangerAlert ? 'ALERT' : 'SAFE', dangerAlert ? Colors.red : Colors.green),
                      ])),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}