import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../../../models/journey_model.dart';
import '../../../../services/journey_service.dart';
import 'dummy_data.dart';

class Member4Page extends StatefulWidget {
  final LatLng? predefinedStart;
  final LatLng? predefinedEnd;
  final List<LatLng>? predefinedRoute;
  final String? destinationName;
  final bool isJourneyActive;

  const Member4Page({
    super.key,
    this.predefinedStart,
    this.predefinedEnd,
    this.predefinedRoute,
    this.destinationName,
    this.isJourneyActive = false,
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

  // Past Journey Risk Zones
  final JourneyService _journeyService = JourneyService();
  final Set<Circle> riskCircles = {};
  List<TurnEvent> pastTurnEvents = [];
  List<BrakingEvent> pastBrakingEvents = [];
  final Set<String> warnedEventIds = {};

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

  // API keys
  static const String weatherApiKey = '1eb3f1d65286d7b8c7fee767600fb7bf';
  static const String googleApiKey = 'AIzaSyBbZVI_sO637CROKwc3hjMOB4ZmsL12ikw';

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

  bool _historyDataLoaded = false;
  int _totalJourneysInDB = 0;
  String _historyFetchError = '';
  List<String> _availableDestinations = [];
  Completer<void>? _historyCompleter;

  @override
  void initState() {
    super.initState();
    _historyDataLoaded = false;
    _historyCompleter = Completer<void>();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final GoogleMapsFlutterPlatform mapsImplementation =
          GoogleMapsFlutterPlatform.instance;
      if (mapsImplementation is GoogleMapsFlutterAndroid) {
        mapsImplementation.useAndroidViewSurface = true;
      }
    }
    flutterTts = FlutterTts();
    _loadMotorcycleIcon();

    // Initialize state markers and route info
    _syncJourneyData();

    _loadModel().then((_) {
      // Logic handled in _syncJourneyData
    });

    // Load past risky events to visualize risk zones - only when journey is active
    if (widget.isJourneyActive) {
      _historyCompleter = Completer<void>();
      _loadPastRiskyEvents().then((_) {
        if (_historyCompleter != null && !_historyCompleter!.isCompleted) {
          _historyCompleter!.complete();
        }
        print("[DangerZone] _loadPastRiskyEvents completes. Total circles: ${riskCircles.length}");
      });

      // Fetch and display the latest specific journey - only when journey is active
      _fetchAndDisplayLatestJourney();
    }

    if (widget.isJourneyActive) {
      _startLiveUpdates(); // only start live location & sensors if journey active
    }
  }

  Future<void> _fetchAndDisplayLatestJourney() async {
    try {
      final latestJourney = await _journeyService.getLatestJourney();
      if (latestJourney != null && mounted) {
        setState(() {
          _displayJourneyData(latestJourney);
        });
      }
    } catch (e) {
      print("[DangerZone] Error fetching latest journey: $e");
    }
  }

  Future<void> _displayJourneyData(JourneyData journey) async {
    print("[DangerZone] Displaying journey data for ID: ${journey.id}");
    // 1. Clear previous analysis if any
    // 1. Clear only historical markers/polylines to preserve planned route
    polylines.removeWhere((p) => p.polylineId.value == 'fetched_route');
    markers.removeWhere((m) => m.markerId.value.startsWith('event_'));
    
    // We keep 'current', 'start', 'end', 'full_route', 'segment_X' markers/polylines
    
    safetyTips.clear();
    _historyDataLoaded = true;
    
    if (mounted) {
      setState(() {
        safetyTips.add("🔍 Fetching road-bound route for history...");
      });
    }

    // 2. Extract points for route (use GPS track if available, else turn events)
    List<LatLng> routePoints = [];
    if (journey.gpsTrack.isNotEmpty) {
      print("[DangerZone] Using ${journey.gpsTrack.length} points from GPS track");
      routePoints = journey.gpsTrack.map((p) => LatLng(p.latitude, p.longitude)).toList();
    } else if (journey.turnEvents.isNotEmpty) {
      print("[DangerZone] GPS track empty. Reconstructing route from turn events...");
      
      // Use the first and last turn events as origin/destination for Directions API
      // to get a user-friendly road-following path.
      try {
        LatLng start = LatLng(journey.turnEvents.first.latitude, journey.turnEvents.first.longitude);
        LatLng end = LatLng(journey.turnEvents.last.latitude, journey.turnEvents.last.longitude);
        
        // If they are the same point, try the strings
        if (start == end && journey.startLocation != null && journey.destination != null) {
           // Directions API handles strings too if we modify _fetchTrafficAwareRoute
           // but for now let's hope the coords are different or just use them.
        }

        routePoints = await _fetchTrafficAwareRoute(start, end);
        print("[DangerZone] Successfully reconstructed path with ${routePoints.length} points");
      } catch (e) {
        print("[DangerZone] Path reconstruction failed: $e. Falling back to discrete points.");
        routePoints = journey.turnEvents.map((e) => LatLng(e.latitude, e.longitude)).toList();
      }
    } else {
       print("[DangerZone] WARNING: No GPS points OR turn events found for this journey!");
    }

    if (routePoints.isNotEmpty) {
      // 3. Add Polyline
      polylines.add(
        Polyline(
          polylineId: const PolylineId('fetched_route'),
          points: routePoints,
          color: journey.dangerPrediction == 'DANGEROUS' ? Colors.orange : Colors.deepPurple,
          width: 8, // Thicker than planned route
          jointType: JointType.round,
          zIndex: 20, // Higher than planned route
        ),
      );

      // 3.1 Removed START and END markers to avoid confusion with current journey destination
      // 3.2 Removed event markers (turn/braking) - only risk circles will be shown for fetched zones
      // This keeps the map clean and rider focused on current destination

      // 4. Center Camera to encompass EVERYTHING
      _fitMapToAllRoutes();
    }

    // 6. Generate Safety Tips based on fetched data
    _generateSafetyTipsFromData(journey);
    
    // Trigger UI refresh explicitly
    if (mounted) setState(() {});

    // 7. Voice warnings only when near danger zones (removed startup voice)
  }

  void _fitMapToPoints(List<LatLng> points) {
    if (mapController == null || points.isEmpty) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  void _fitMapToAllRoutes() {
    if (mapController == null || (polylines.isEmpty && markers.isEmpty)) return;
    
    List<LatLng> allPoints = [];
    for (var poly in polylines) {
      allPoints.addAll(poly.points);
    }
    for (var marker in markers) {
      // Don't include the 'current' motorcycle marker in the bounds if it's far away
      if (marker.markerId.value != 'current') {
        allPoints.add(marker.position);
      }
    }
    
    if (allPoints.isNotEmpty) {
      _fitMapToPoints(allPoints);
    }
  }

  void _generateSafetyTipsFromData(JourneyData journey) {
    setState(() {
      safetyTips.clear();
      
      // 1. Context Header
      safetyTips.add("✅ RIDE HISTORY: ${journey.startLocation?.split(',').first ?? 'Origin'} to ${journey.destination?.split(',').first ?? 'Destination'}");
      // safetyTips.add("Journey ID: ${journey.id}");
      safetyTips.add("----------------------------");

      // 2. Exact Location Data
      safetyTips.add("📍 Start: ${journey.startLocation ?? 'Unknown Location'}");
      safetyTips.add("📍 End: ${journey.destination ?? 'Unknown Location'}");
      safetyTips.add("----------------------------");

      // 3. Performance Data (Directly from Firestore)
      safetyTips.add("Performance Summary:");
      safetyTips.add("• Prediction: ${journey.dangerPrediction?.toUpperCase() ?? 'NORMAL'}");
      safetyTips.add("• Total Distance: ${journey.totalDistance.toStringAsFixed(3)} km");
      safetyTips.add("• Avg Speed: ${journey.averageSpeed.toStringAsFixed(1)} km/h");
      safetyTips.add("• Max Speed: ${journey.maxSpeed.toStringAsFixed(1)} km/h");
      safetyTips.add("• Max Turn Rate: ${journey.maxTurnRate.toStringAsFixed(1)}");
      safetyTips.add("• Risky Turns: ${journey.riskyTurns}");
      safetyTips.add("• Braking Events: ${journey.totalBrakingEvents}");
      safetyTips.add("----------------------------");

      // 4. Data-Driven Advice
      if (journey.dangerPrediction == 'DANGEROUS' || journey.riskyTurns > 0) {
        safetyTips.add("⚠️ HISTORY WARNING:");
        safetyTips.add("Your previous ride had ${journey.riskyTurns} risky turns and reached a turn rate of ${journey.maxTurnRate.toStringAsFixed(1)}.");
        safetyTips.add("Recommended: Reduce speed at intersections and avoid sudden maneuvers.");
      } else {
        safetyTips.add("Safe history recorded. Continue following standard safety rules.");
      }
      
      safetyTips.add("• Review the orange/red markers on the map for risk locations from your history.");
    });
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

  Future<void> _loadPastRiskyEvents() async {
    print("[DangerZone] ENTERED _loadPastRiskyEvents");

    // Clear previous data
    pastTurnEvents.clear();
    pastBrakingEvents.clear();
    warnedEventIds.clear();
    riskCircles.clear();

    try {
      if (mounted) setState(() => _historyFetchError = '');
      print("[DangerZone] Fetching journeys from Firebase...");
      final allJourneys = await _journeyService.getAllJourneys();
      
      if (mounted) {
        setState(() {
          _totalJourneysInDB = allJourneys.length;
        });
      }
      
      print("[DangerZone] Received ${allJourneys.length} total journeys from Firebase");

      // ── Filter journeys that match the current route ──
      // Match by destination/start location keywords
      final currentDest = (widget.destinationName ?? '').toLowerCase();
      
      List<JourneyData> matchingJourneys;
      
      if (currentDest.isEmpty) {
        // No destination set — show ALL past risky events
        matchingJourneys = allJourneys;
        print("[DangerZone] No destination set. Using all ${matchingJourneys.length} journeys");
      } else {
        if (allJourneys.isNotEmpty) {
          final dbDestinations = allJourneys.map((j) => "${j.startLocation} -> ${j.destination}").toSet().toList();
          if (mounted) {
            setState(() {
              _availableDestinations = dbDestinations;
            });
          }
        }

        // Try to find journeys where either destination matches OR start matches (if destination is ambiguous)
        matchingJourneys = allJourneys.where((journey) {
          final journeyDest = (journey.destination ?? '').toLowerCase();
          final journeyStart = (journey.startLocation ?? '').toLowerCase();
          
          bool destMatch = _routeKeywordsMatch(currentDest, journeyDest);
          bool startMatch = _routeKeywordsMatch(currentDest, journeyStart);
          
          // Debug matching
          print("[DangerZone] Checking match for '$currentDest': DB_Dest: '$journeyDest' (M: $destMatch), DB_Start: '$journeyStart' (M: $startMatch)");
          
          return destMatch || startMatch;
        }).toList();
        
        if (matchingJourneys.isEmpty) {
          print("[DangerZone] NO MATCH for '$currentDest'. Records in DB: ${_availableDestinations.join(' | ')}");
        }
        
        print("[DangerZone] Filtered to ${matchingJourneys.length} journeys matching destination '$currentDest'");

        // ── Identify the latest matching journey for detailed display ──
        if (matchingJourneys.isNotEmpty) {
          // Sort to get the most recent journey
          matchingJourneys.sort((a, b) => b.startTime.compareTo(a.startTime));
          final latestMatch = matchingJourneys.first;
          print("[DangerZone] Latest matching journey found: ${latestMatch.id} from ${latestMatch.startTime}");
          
          if (mounted) {
            await _displayJourneyData(latestMatch);
          }
        }
      }

      // ── Extract risk events from matching journeys ──
      for (var journey in matchingJourneys) {
        print("[DangerZone] Processing journey: ${journey.startLocation} → ${journey.destination} (${journey.turnEvents.length} turns, ${journey.brakingEvents.length} brakes)");
        
        // Collect severe turns
        for (var turn in journey.turnEvents) {
          if (turn.severity == 'risky' || turn.severity == 'sharp') {
            pastTurnEvents.add(turn);
            Color color = turn.severity == 'sharp' ? Colors.red : Colors.orange;
            _createRiskCircle(turn.latitude, turn.longitude, color);
            print("[DangerZone] ⚠ Turn at ${turn.latitude}, ${turn.longitude} (${turn.severity})");
          }
        }
        // Collect severe brakes
        for (var brake in journey.brakingEvents) {
          if (brake.severity == 'emergency' || brake.severity == 'hard') {
            pastBrakingEvents.add(brake);
            _createRiskCircle(brake.latitude, brake.longitude, Colors.redAccent);
            print("[DangerZone] 🛑 Brake at ${brake.latitude}, ${brake.longitude} (${brake.severity})");
          }
        }
      }

      print("[DangerZone] Total: ${pastTurnEvents.length} turns, ${pastBrakingEvents.length} brakes, ${riskCircles.length} circles");

      if (_historyCompleter != null && !_historyCompleter!.isCompleted) {
        _historyCompleter!.complete();
      }

      if (mounted) {
        setState(() {});
        print("[DangerZone] Map updated with ${riskCircles.length} risk circles");
      }
    } catch (e) {
      print('[DangerZone] Error loading past risky events: $e');
      if (mounted) setState(() => _historyFetchError = e.toString());
      if (_historyCompleter != null && !_historyCompleter!.isCompleted) {
        _historyCompleter!.complete();
      }
    }
  }

  /// Check if two location strings share meaningful keywords (city/area names)
  bool _routeKeywordsMatch(String location1, String location2) {
    if (location1.isEmpty || location2.isEmpty) return false;
    
    // Extract meaningful words (skip common words like "Sri Lanka", commas, etc.)
    final skipWords = {'sri', 'lanka', 'road', 'street', 'avenue', 'lane', 'no', 'the', 'and', 'city', 'area'};
    
    // Split by common delimiters: space, comma, hyphen, slash, dot
    final delimiters = RegExp(r'[\s,\-\/\.]');
    
    final words1 = location1
        .toLowerCase()
        .split(delimiters)
        .where((w) => w.length > 2 && !skipWords.contains(w))
        .toSet();
    
    final words2 = location2
        .toLowerCase()
        .split(delimiters)
        .where((w) => w.length > 2 && !skipWords.contains(w))
        .toSet();
    
    final intersection = words1.intersection(words2);
    
    // Check for substring match as well (e.g. "Malabe" matches "Malabe, Sri Lanka")
    bool substringMatch = location1.toLowerCase().contains(location2.toLowerCase()) || 
                          location2.toLowerCase().contains(location1.toLowerCase());
    
    bool directMatch = location1.toLowerCase().trim() == location2.toLowerCase().trim();

    if (intersection.isNotEmpty || substringMatch || directMatch) {
      print("[DangerZone] Match found! Keywords: $intersection, Substring: $substringMatch, Direct: $directMatch");
    }
    
    return intersection.isNotEmpty || substringMatch || directMatch;
  }

  /// Check if any of a journey's risk events are near the current planned route
  bool _journeyOverlapsRoute(JourneyData journey, List<LatLng> route) {
    const double proximityThresholdKm = 0.5; // 500 meters
    
    for (var turn in journey.turnEvents) {
      for (var routePoint in route) {
        double dist = Geolocator.distanceBetween(
          turn.latitude, turn.longitude,
          routePoint.latitude, routePoint.longitude,
        );
        if (dist < proximityThresholdKm * 1000) return true;
      }
    }
    for (var brake in journey.brakingEvents) {
      for (var routePoint in route) {
        double dist = Geolocator.distanceBetween(
          brake.latitude, brake.longitude,
          routePoint.latitude, routePoint.longitude,
        );
        if (dist < proximityThresholdKm * 1000) return true;
      }
    }
    return false;
  }

  void _createRiskCircle(double lat, double lng, Color color) {
    String circleIdStr = 'risk_${lat}_$lng';
    riskCircles.add(
      Circle(
        circleId: CircleId(circleIdStr),
        center: LatLng(lat, lng),
        radius: 25, // 25 meters - fits road width
        fillColor: color.withOpacity(0.5),
        strokeColor: color,
        strokeWidth: 3,
        zIndex: 10,
      ),
    );
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

  @override
  void didUpdateWidget(covariant Member4Page oldWidget) {
    super.didUpdateWidget(oldWidget);

    final routeChanged =
        !listEquals(widget.predefinedRoute, oldWidget.predefinedRoute);
    final nameChanged = widget.destinationName != oldWidget.destinationName;
    final activeChanged = widget.isJourneyActive != oldWidget.isJourneyActive;

    if (routeChanged || nameChanged || activeChanged) {
      print(
          "[DangerZone] Props changed → syncing (active: ${widget.isJourneyActive}, dest: ${widget.destinationName})");

      if (nameChanged || routeChanged) {
        _historyDataLoaded = false;
        _historyCompleter = Completer<void>();
      }

      _syncJourneyData();
      
      // Re-filter risk zones when destination changes
      if (nameChanged || routeChanged) {
        print("[DangerZone] Destination/route changed → reloading risk zones");
        _loadPastRiskyEvents().then((_) {
          if (_historyCompleter != null && !_historyCompleter!.isCompleted) {
            _historyCompleter!.complete();
          }
        });
      }

      if (widget.isJourneyActive && !oldWidget.isJourneyActive) {
        print("[DangerZone] Journey STARTED → starting live updates");
        _startLiveUpdates();
      } else if (!widget.isJourneyActive && oldWidget.isJourneyActive) {
        print("[DangerZone] Journey ENDED → cleaning up");
        _stopLiveUpdatesAndClearMap();
      }
    }
  }

  void _stopLiveUpdatesAndClearMap() {
    _locationTimer?.cancel();
    _sensorTimer?.cancel();
    _locationTimer = null;
    _sensorTimer = null;

    setState(() {
      // Clear live position marker
      markers.removeWhere((m) => m.markerId.value == 'current');
      currentPosition = null;

      // Optional: keep start/end markers if you want, or clear everything
      // markers.clear();   ← only if you want full reset

      // Clear polylines & risk state (recommended when journey ends)
      polylines.clear();
      safetyTips.clear();
      _predictedRisk = null;
      showTips = false;
    });

    // Optional: move camera back to initial position or Colombo
    mapController?.animateCamera(
      CameraUpdate.newCameraPosition(initialPosition),
    );

    print("[DangerZone] Cleanup complete – map & sensors reset");
  }

  void _syncJourneyData() {
    setState(() {
      isPredefined =
          widget.predefinedRoute != null && widget.predefinedRoute!.isNotEmpty;

      final destLower = (widget.destinationName ?? '').toLowerCase();
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

      // Ensure start/end points are reflected in state
      startPoint = widget.predefinedStart;
      endPoint = widget.predefinedEnd;

      // Always add start/end markers if points exist
      _addStartEndMarkers();
    });

    // Only analyze when journey is active
    if (widget.isJourneyActive) {
      if (isPredefined && widget.predefinedRoute != null) {
        print("[DangerZone] Using provided predefined route (${widget.predefinedRoute!.length} pts)");
        analyzeRoute(widget.predefinedRoute!);
      } else if (widget.predefinedStart != null && widget.predefinedEnd != null) {
        print("[DangerZone] No route points provided. Fetching road-bound path from API...");
        _fetchTrafficAwareRoute(widget.predefinedStart!, widget.predefinedEnd!).then((points) {
          if (mounted) {
            print("[DangerZone] Fetched planned route with ${points.length} points");
            analyzeRoute(points);
          }
        }).catchError((e) {
          print("[DangerZone] Failed to fetch planned route: $e");
        });
      } else {
        print("[DangerZone] Warning: Journey active but NO route or start/end points!");
      }
    } else {
      print("[DangerZone] Journey inactive → skipping analysis");
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
        _checkProximityToRiskZones(pos);
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
        temperature = 36.8 + r.nextDouble() * 0.9;
        stressLevel = r.nextInt(85);
        dangerAlert = r.nextDouble() > 0.88;
      });
    });
  }

  void _checkProximityToRiskZones(Position currentPos) {
    if (!widget.isJourneyActive) return;

    final double warningDistance = 100.0; // 100 meters

    // Check Turn Events
    for (var turn in pastTurnEvents) {
      String eventId = 'turn_\${turn.timestamp.millisecondsSinceEpoch}';
      if (!warnedEventIds.contains(eventId)) {
        double distance = Geolocator.distanceBetween(
          currentPos.latitude,
          currentPos.longitude,
          turn.latitude,
          turn.longitude,
        );
        if (distance <= warningDistance) {
          warnedEventIds.add(eventId);
          _triggerAudioWarning(
              "Warning: Approaching a zone where a \${turn.severity} turn occurred previously.");
        }
      }
    }

    // Check Braking Events
    for (var brake in pastBrakingEvents) {
      String eventId = 'brake_\${brake.timestamp.millisecondsSinceEpoch}';
      if (!warnedEventIds.contains(eventId)) {
        double distance = Geolocator.distanceBetween(
          currentPos.latitude,
          currentPos.longitude,
          brake.latitude,
          brake.longitude,
        );
        if (distance <= warningDistance) {
          warnedEventIds.add(eventId);
          _triggerAudioWarning(
              "Warning: Approaching a zone where \${brake.severity} braking occurred previously.");
        }
      }
    }
  }

  Future<void> _triggerAudioWarning(String message) async {
    print("[DangerZone] TTS Warning triggered: \$message");
    await flutterTts.speak(message);
  }

  void _stopLiveUpdates() {
    _locationTimer?.cancel();
    _sensorTimer?.cancel();
    setState(() {
      currentPosition = null;
      markers.removeWhere((m) => m.markerId.value == 'current');
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

  Future<Map<String, dynamic>> _fetchWeatherData(double lat, double lng) async {
    final url = Uri.parse(
      'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lng&appid=$weatherApiKey&units=metric',
    );
    try {
      final response = await http.get(url);
      print('Weather URL: $url');
      print('Weather response code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Safely extract values (handle int or double)
        double temp = (data['main']['temp'] is num)
            ? (data['main']['temp'] as num).toDouble()
            : 25.0;
        double humidity = (data['main']['humidity'] is num)
            ? (data['main']['humidity'] as num).toDouble()
            : 70.0;
        double windSpeed = (data['wind']['speed'] is num)
            ? (data['wind']['speed'] as num).toDouble()
            : 5.0;
        double precipitation = (data['rain']?['1h'] is num)
            ? (data['rain']['1h'] as num).toDouble()
            : 0.0;
        double visibility = (data['visibility'] is num)
            ? (data['visibility'] as num).toDouble()
            : 10000.0;

        String weatherMain =
            data['weather'][0]['main'].toString().toLowerCase();
        String weatherCond = weatherMain;
        if (weatherCond.contains('cloud'))
          weatherCond = 'Cloudy';
        else if (weatherCond.contains('rain') ||
            weatherCond.contains('drizzle'))
          weatherCond = 'Rainy';
        else if (weatherCond.contains('snow'))
          weatherCond = 'Snowy';
        else if (weatherCond.contains('mist') || weatherCond.contains('fog'))
          weatherCond = 'Foggy';
        else if (weatherCond.contains('clear'))
          weatherCond = 'Clear';
        else
          weatherCond = 'Cloudy'; // fallback

        return {
          'Temperature': temp,
          'Humidity': humidity,
          'Wind_Speed': windSpeed,
          'Precipitation': precipitation,
          'Visibility': visibility,
          'Weather_Condition': weatherCond,
        };
      } else {
        print('Weather API error: ${response.body}');
        throw Exception('API failed');
      }
    } catch (e) {
      print('Weather fetch failed: $e');
      // Return empty → triggers fallback without crash
      return {};
    }
  }

  Future<List<LatLng>> _fetchTrafficAwareRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?origin=${start.latitude},${start.longitude}&destination=${end.latitude},${end.longitude}&key=$googleApiKey&departure_time=now&traffic_model=best_guess',
    );
    final response = await http.get(url);
    print('Directions URL: $url');
    print('Directions response code: ${response.statusCode}');
    print('Directions response body: ${response.body}'); // Full debug

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'OK') {
        final route = data['routes'][0];
        final polyline = route['overview_polyline']['points'];
        return decodePolyline(polyline);
      } else {
        throw Exception('API status: ${data['status']}');
      }
    } else {
      throw Exception('HTTP error: ${response.statusCode} - ${response.body}');
    }
  }

  List<LatLng> decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int shift = 0, result = 0, byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  Future<Map<String, dynamic>> generateRandomRouteDict(
      List<LatLng> routeSegments) async {
    final r = Random();

    // Use first point of route as location, fallback to Colombo
    double lat =
        routeSegments.isNotEmpty ? routeSegments.first.latitude : 6.9271;
    double lng =
        routeSegments.isNotEmpty ? routeSegments.first.longitude : 79.8612;

    // Fetch real-time weather for starting point
    Map<String, dynamic> weatherData = {};
    try {
      weatherData = await _fetchWeatherData(lat, lng);
    } catch (e) {
      // Fallback to defaults if API fails
      weatherData = {
        'Temperature': 24.0 + r.nextDouble() * 10.0,
        'Humidity': 60.0 + r.nextDouble() * 30.0,
        'Wind_Speed': r.nextDouble() * 25.0,
        'Precipitation': r.nextDouble() * 2.5,
        'Visibility': 3000 + r.nextDouble() * 12000,
        'Weather_Condition':
            weatherConditions[r.nextInt(weatherConditions.length)],
      };
      safetyTips.add("Weather data fallback (API error)");
    }

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

    // Fetch live traffic ETA (duration in traffic)
    double travelTimeMinutes = 30.0; // Default
    double trafficSpeed = 40.0; // Default km/h
    String congestionLevel = 'Medium'; // Default
    try {
      LatLng start = routeSegments.first;
      LatLng end = routeSegments.last;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?origin=${start.latitude},${start.longitude}&destination=${end.latitude},${end.longitude}&key=$googleApiKey&departure_time=now&traffic_model=best_guess',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          travelTimeMinutes = data['routes'][0]['legs'][0]
                  ['duration_in_traffic']['value'] /
              60.0; // seconds to minutes
          trafficSpeed = routeLengthKm /
              (travelTimeMinutes / 60.0); // km/h based on live ETA
          congestionLevel = trafficSpeed < 30
              ? 'High'
              : (trafficSpeed < 50 ? 'Medium' : 'Low');
        }
      } else {
        print('Traffic API error: ${response.body}');
      }
    } catch (e) {
      safetyTips.add("Traffic data fallback (API error)");
      travelTimeMinutes = (routeLengthKm / 40.0) * 60.0; // Fallback estimate
      trafficSpeed = 40.0;
      congestionLevel = 'Medium';
    }

    if (travelTimeMinutes < 10) travelTimeMinutes = 10;
    if (travelTimeMinutes > 180) travelTimeMinutes = 180;

    return {
      'Location_Latitude': lat,
      'Location_Longitude': lng,
      'Temperature': weatherData['Temperature'],
      'Humidity': weatherData['Humidity'],
      'Wind_Speed': weatherData['Wind_Speed'],
      'Precipitation': weatherData['Precipitation'],
      'Visibility': weatherData['Visibility'],
      'Traffic_Speed': trafficSpeed,
      'Travel_Time_Estimate': travelTimeMinutes.roundToDouble(),
      'Weather_Condition': weatherData['Weather_Condition'],
      'Congestion_Level': congestionLevel,
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
        if (col == 'Location_Latitude' || col == 'Location_Longitude') {
          inputNum.add(0.0); // Neutral value — removes location bias
          continue;
        }
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

    // Add real-time weather summary at the top
    double temp = (routeDict['Temperature'] as num?)?.toDouble() ?? 25.0;
    String weather = routeDict['Weather_Condition'] as String? ?? 'Unknown';
    suggestions.add("Current Weather: $weather, ${temp.toStringAsFixed(1)}°C");

    suggestions.add(
      'Predicted Risk Probability: ${(prob * 100).toStringAsFixed(1)}% → ${isRisky ? "Risky" : "Safe"}',
    );

    String cong = (routeDict['Congestion_Level'] as String?) ?? 'Unknown';
    double precipitation =
        (routeDict['Precipitation'] as num?)?.toDouble() ?? 0.0;
    double visibility =
        (routeDict['Visibility'] as num?)?.toDouble() ?? 10000.0;
    String roadType = (routeDict['Road_Type'] as String?) ?? '';
    double travelTime =
        (routeDict['Travel_Time_Estimate'] as num?)?.toDouble() ?? 0.0;

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

  Future<void> analyzeRoute(List<LatLng> routeSegments) async {
    // Wait for history load to at least ATTEMPT to finish if it's running
    if (_historyCompleter != null) {
      print("[DangerZone] analyzeRoute waiting for history loader...");
      await _historyCompleter!.future;
    }

    // Note: We don't return early anymore because we want both routes visible
    // but we will only clear and add TIPS if history is not loaded.
    
    if (!_historyDataLoaded) {
      polylines.clear(); // Only clear simulation polylines if no history
      safetyTips.clear();
    }
    _predictedRisk = null;

    if (routeSegments.length < 2) {
      if (mounted) setState(() {});
      return;
    }

    // Fetch real-time weather for the starting point
    Map<String, dynamic> weatherData = {};
    try {
      double startLat = routeSegments.first.latitude;
      double startLng = routeSegments.first.longitude;
      weatherData = await _fetchWeatherData(startLat, startLng);
      print('Real-time weather fetched: ${weatherData['Weather_Condition']}');
    } catch (e) {
      weatherData = {}; // Fallback handled in dict generation
      safetyTips.add('Weather data unavailable - using estimates');
    }

    if (recentlyUsed && destKey != null && dummyData.containsKey(destKey)) {
      Map<String, dynamic> routeDict =
          Map.from(dummyData[destKey]?['features'] ?? {});
      if (!recentlyUsed) {
        safetyTips.add("Based on another member's journey data");
      }
      _predictedRisk = predictRouteRisk(routeDict);
      
      // Re-check flag before modifying state after async calls
      if (_historyDataLoaded) return;

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
      if (_predictedRisk != null) {
        safetyTips.addAll(getSafetySuggestions(_predictedRisk!, routeDict));
      } else {
        safetyTips.add('No AI risk prediction available');
      }
    } else {
      // New route: per-segment analysis for safe/risky parts
      int highRiskCount = 0;
      
      if (!_historyDataLoaded && mounted) {
        setState(() {
          safetyTips.add("🔍 Analyzing route segments...");
        });
      }

      for (int i = 0; i < routeSegments.length - 1; i++) {
        // Small delay to make the "little by little" effect visible
        await Future.delayed(const Duration(milliseconds: 100));
        
        if (!mounted) return;

        Map<String, dynamic> segmentDict = await generateRandomRouteDict(
            [routeSegments[i], routeSegments[i + 1]]);
        segmentDict.addAll(weatherData); // Apply real weather

        double? segmentRisk = predictRouteRisk(segmentDict);
        Color segmentColor = getRiskColor(segmentRisk ?? 0.5);

        setState(() {
          polylines.add(
            Polyline(
              polylineId: PolylineId('segment_$i'),
              points: [routeSegments[i], routeSegments[i + 1]],
              color: segmentColor,
              width: 10,
              jointType: JointType.round,
              zIndex: 10,
            ),
          );
          
          if (!_historyDataLoaded && i % 3 == 0) {
            // Update status periodically
            int progress = ((i / (routeSegments.length - 1)) * 100).round();
             safetyTips.removeWhere((t) => t.startsWith("🔍 Analyzing"));
             safetyTips.add("🔍 Analyzing route: $progress%");
          }
        });

        if (segmentRisk != null && segmentRisk > 0.7) highRiskCount++;
      }

      if (!_historyDataLoaded) {
          safetyTips.removeWhere((t) => t.startsWith("🔍 Analyzing"));
      }

      // Overall risk as average
      _predictedRisk =
          highRiskCount / (routeSegments.length - 1); // Simple average example

      if (_predictedRisk != null && !_historyDataLoaded) {
        safetyTips.addAll(getSafetySuggestions(_predictedRisk!, weatherData));
        if (highRiskCount > 0) {
          safetyTips.add(
              'There are $highRiskCount high-risk segments - proceed with caution');
          // Voice warnings only when near danger zones (removed startup voice)
        } else {
          safetyTips.add('All segments appear safe');
          // Voice warnings only when near danger zones (removed startup voice)
        }
      } else if (_predictedRisk == null && !_historyDataLoaded) {
        safetyTips.add('No AI risk prediction available');
      }
    }

    // Improved camera fitting to encompass EVERYTHING
    _fitMapToAllRoutes();

    if (!_historyDataLoaded) {
      generateSafetyTips();
      if (mounted) setState(() {});
      // Voice warnings only when near danger zones (removed startup voice)
    } else {
      print("[DangerZone] analyzeRoute FINISHED but skipped tips because history is loaded");
      if (mounted) setState(() {});
    }
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
      safetyTips.insert(0, '# TRACE: History Check Failed');
      safetyTips.add('----------------------------');
      safetyTips.add('DB Status: $_totalJourneysInDB records in "(default)"');
      safetyTips.add('Search Target: "${(widget.destinationName ?? 'None')}"');
      
      if (_historyFetchError.isNotEmpty) {
        safetyTips.add('❌ ERROR: $_historyFetchError');
      }

      if (_totalJourneysInDB > 0) {
        if (_availableDestinations.isNotEmpty) {
          safetyTips.add('Routes found in Database (${_availableDestinations.length}):');
          for (var d in _availableDestinations.take(5)) {
            safetyTips.add('• $d');
          }
        } else {
          safetyTips.add('⚠️ Matching list is empty? (Logic Issue)');
        }
      } else {
        safetyTips.add('⚠️ NO RECORDS FOUND IN FIREBASE (default)');
        safetyTips.add('Note: Check if Firestore contains "journeys" collection');
      }
      safetyTips.add('----------------------------');
    }
  }

  void _speakSafetyTips() async {
    // Voice warnings only when near danger zones - disabled startup voice
    // if (safetyTips.isNotEmpty) {
    //   String tipsText = safetyTips.join('. ');
    //   await flutterTts.speak(tipsText);
    // }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _sensorTimer?.cancel();
    _locationTimer = null;
    _sensorTimer = null;
    flutterTts.stop();
    _interpreter?.close();
    mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset:
          false, // ← prevents keyboard from pushing map up
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
            circles: riskCircles,
            myLocationEnabled: false,
            myLocationButtonEnabled: true,
            compassEnabled: true,
            zoomControlsEnabled: true,
            trafficEnabled: true, // Show live traffic layer on map
            mapToolbarEnabled: false,
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.deepPurple,
              child: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () {
                print("[DangerZone] Manual refresh triggered");
                _loadPastRiskyEvents();
                _fetchAndDisplayLatestJourney();
              },
            ),
          ),
          if (widget.isJourneyActive)
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
          if (widget.isJourneyActive)
            Positioned(
              bottom: showTips ? 220 : 140,
              right: 16,
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
