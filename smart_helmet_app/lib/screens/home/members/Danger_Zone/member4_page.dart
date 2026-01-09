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
        temperature = 36.8 + r.nextDouble() * 0.9;
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
    polylines.clear();
    safetyTips.clear();
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
      for (int i = 0; i < routeSegments.length - 1; i++) {
        Map<String, dynamic> segmentDict = await generateRandomRouteDict(
            [routeSegments[i], routeSegments[i + 1]]);
        segmentDict.addAll(weatherData); // Apply real weather

        double? segmentRisk = predictRouteRisk(segmentDict);
        Color segmentColor = getRiskColor(segmentRisk ?? 0.5);

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

        if (segmentRisk != null && segmentRisk > 0.7) highRiskCount++;
      }

      // Overall risk as average
      _predictedRisk =
          highRiskCount / (routeSegments.length - 1); // Simple average example

      if (_predictedRisk != null) {
        safetyTips.addAll(getSafetySuggestions(_predictedRisk!, weatherData));
        if (highRiskCount > 0) {
          safetyTips.add(
              'There are $highRiskCount high-risk segments - proceed with caution');
          await flutterTts
              .speak('Caution: $highRiskCount high-risk segments ahead.');
        } else {
          safetyTips.add('All segments appear safe');
          await flutterTts.speak('Route is safe. Enjoy your ride.');
        }
      } else {
        safetyTips.add('No AI risk prediction available');
      }
    }

    // Improved camera fitting
    if (mapController != null && routeSegments.isNotEmpty) {
      double minLat =
          routeSegments.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
      double maxLat =
          routeSegments.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
      double minLng =
          routeSegments.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
      double maxLng =
          routeSegments.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 80),
        );
      });
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
            trafficEnabled: true, // Show live traffic layer on map
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
