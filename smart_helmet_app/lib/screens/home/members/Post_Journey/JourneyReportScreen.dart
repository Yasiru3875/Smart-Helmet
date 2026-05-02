import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:intl/intl.dart';
import '../../../../models/journey_model.dart';
import '../../../../services/post_journey.dart';

class JourneyReportScreen extends StatefulWidget {
  final JourneyData journey;

  const JourneyReportScreen({super.key, required this.journey});

  @override
  State<JourneyReportScreen> createState() => _JourneyReportScreenState();
}

class _JourneyReportScreenState extends State<JourneyReportScreen> {
  GoogleMapController? _mapController;
  Set<Marker>  _markers  = {};
  Set<Polyline> _polylines = {};
  Set<Circle>  _circles  = {};

  final DangerZoneService _dangerZoneService = DangerZoneService();
  bool _dangerZonesLoaded = false;

  @override
  void initState() {
    super.initState();
    _prepareMapData();
    _loadDangerZones();
  }

  /// Runs the TFLite danger zone model over all sensor readings and
  /// renders the results as coloured circles on the heatmap.
  Future<void> _loadDangerZones() async {
    final zones = await _dangerZoneService.analyseRide(widget.journey);
    if (!mounted) return;
    final Set<Circle> circles = {};
    for (int i = 0; i < zones.length; i++) {
      final zone = zones[i];
      // Colour: red for high-confidence, orange for moderate
      final color = zone.dangerScore >= 0.80
          ? Colors.red
          : zone.dangerScore >= 0.65
              ? Colors.orange
              : Colors.amber;
      circles.add(Circle(
        circleId: CircleId('dz_$i'),
        center: zone.center,
        radius: zone.radiusMeters,
        fillColor: color.withOpacity(0.25),
        strokeColor: color.withOpacity(0.7),
        strokeWidth: 2,
        zIndex: 5,
        consumeTapEvents: true,
        onTap: () {
          _mapController?.showMarkerInfoWindow(MarkerId('dz_info_$i'));
        },
      ));
      // Invisible marker for the tap info window
      _markers.add(Marker(
        markerId: MarkerId('dz_info_$i'),
        position: zone.center,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          zone.dangerScore >= 0.80
              ? BitmapDescriptor.hueRed
              : BitmapDescriptor.hueOrange,
        ),
        infoWindow: InfoWindow(
          title: '⚠ ${zone.label}',
          snippet: 'Risk score: ${(zone.dangerScore * 100).toStringAsFixed(0)}%',
        ),
        visible: false,   // hidden — shown only via tap on circle
      ));
    }
    setState(() {
      _circles = circles;
      _dangerZonesLoaded = true;
    });
  }

  @override
  void dispose() {
    _dangerZoneService.dispose();
    super.dispose();
  }

  // All GPS points available for map display (gpsTrack OR reconstructed from events)
  List<LatLng> _allMapPoints = [];

  void _prepareMapData() {
    // Build route points from gpsTrack if available
    if (widget.journey.gpsTrack.isNotEmpty) {
      _allMapPoints = widget.journey.gpsTrack
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();
    } else {
      // FALLBACK: Reconstruct route from turnEvents + brakingEvents GPS coordinates
      // (gpsTrack is not saved to Firebase to conserve bandwidth, but event coordinates ARE saved)
      final List<LatLng> eventPoints = [];
      for (final event in widget.journey.turnEvents) {
        if (event.latitude != 0.0 && event.longitude != 0.0) {
          eventPoints.add(LatLng(event.l
          atitude, event.longitude));
        }
      }
      for (final brake in widget.journey.brakingEvents) {
        if (brake.latitude != 0.0 && brake.longitude != 0.0) {
          eventPoints.add(LatLng(brake.latitude, brake.longitude));
        }
      }
      _allMapPoints = eventPoints;
      debugPrint("📍 No gpsTrack, reconstructed ${_allMapPoints.length} map points from events");
    }

    // Also add lean event coordinates for route reconstruction
    if (widget.journey.gpsTrack.isEmpty) {
      for (final lean in widget.journey.leanEvents) {
        if (lean.latitude != 0.0 && lean.longitude != 0.0) {
          _allMapPoints.add(LatLng(lean.latitude, lean.longitude));
        }
      }
    }
    // Create polyline from available points
    if (_allMapPoints.isNotEmpty) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: _allMapPoints,
          color: Colors.blueAccent,
          width: 5,
        ),
      );
    }

    // 🔴 Risky turn markers (red)
    for (int i = 0; i < widget.journey.turnEvents.length; i++) {
      final event = widget.journey.turnEvents[i];
      final bool isRisky = event.severity == 'risky';
      if (event.latitude == 0.0 && event.longitude == 0.0) continue;
      _markers.add(
        Marker(
          markerId: MarkerId('turn_$i'),
          position: LatLng(event.latitude, event.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isRisky ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: isRisky ? '🔴 Risky Turn' : '🟠 Sharp Turn',
            snippet: '${event.turnRate.toStringAsFixed(1)}°/s',
          ),
        ),
      );
    }

    // 🟣 Braking event markers (violet)
    for (int i = 0; i < widget.journey.brakingEvents.length; i++) {
      final brake = widget.journey.brakingEvents[i];
      if (brake.latitude == 0.0 && brake.longitude == 0.0) continue;
      _markers.add(
        Marker(
          markerId: MarkerId('brake_$i'),
          position: LatLng(brake.latitude, brake.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(
            title: brake.severity == 'emergency' ? '🟣 Emergency Brake' : '🟣 Hard Brake',
            snippet: '${brake.speedBefore.toStringAsFixed(1)} km/h → decel ${brake.deceleration.toStringAsFixed(2)}g',
          ),
        ),
      );
    }

    // 🩷 Lean event markers (magenta)
    for (int i = 0; i < widget.journey.leanEvents.length; i++) {
      final lean = widget.journey.leanEvents[i];
      if (lean.latitude == 0.0 && lean.longitude == 0.0) continue;
      _markers.add(
        Marker(
          markerId: MarkerId('lean_$i'),
          position: LatLng(lean.latitude, lean.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(330), // magenta
          infoWindow: InfoWindow(
            title: lean.severity == 'critical' ? '🩷 Critical Lean' : '🩷 Risky Lean',
            snippet: '${lean.leanAngle.toStringAsFixed(1)}° lean',
          ),
        ),
      );
    }
  }

  // Calculate safety score (0-100)
  double _calculateSafetyScore() {
    int score = 100;
    
    // Deduct points for risky turns
    score -= widget.journey.riskyTurns * 10;
    
    // Deduct points for sharp turns
    score -= widget.journey.sharpTurns * 3;
    
    // Deduct points for critical lean events (8 per critical lean)
    score -= widget.journey.leanEvents
        .where((e) => e.severity == 'critical').length * 8;
    
    // Deduct points for risky lean events (4 per risky lean)
    score -= widget.journey.leanEvents
        .where((e) => e.severity == 'risky').length * 4;
    
    // Deduct points for high average speed
    if (widget.journey.averageSpeed > 60) {
      score -= ((widget.journey.averageSpeed - 60) / 2).round();
    }
    
    return score.clamp(0, 100).toDouble();
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  String _getScoreLabel(double score) {
    if (score >= 80) return 'Safe';
    if (score >= 50) return 'Moderate';
    return 'Risky';
  }

  @override
  Widget build(BuildContext context) {
    final safetyScore = _calculateSafetyScore();
    final duration = widget.journey.endTime != null
        ? widget.journey.endTime!.difference(widget.journey.startTime)
        : Duration.zero;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Journey Report', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.blue[700],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.blueAccent),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Share feature coming soon!'), backgroundColor: Colors.blueGrey),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.blueAccent),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Download PDF coming soon!'), backgroundColor: Colors.blueGrey),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. Safety Score Header
            _buildSafetyScoreHeader(safetyScore, duration),
            
            // 2. AI Danger Prediction Output
            _buildDangerPredictionWidget(),

            // 3. Risk Map (Heatmap)
            _buildRiskMap(),

            // 4. Event Breakdown
            _buildEventBreakdown(),

            // 5. Danger Zone Log
            _buildDangerZoneLog(),

            // Additional Info
            _buildAdditionalInfo(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // 1. Safety Score Header
  Widget _buildSafetyScoreHeader(double score, Duration duration) {
    final scoreColor = _getScoreColor(score);
    final scoreLabel = _getScoreLabel(score);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1), Color(0xFF1A237E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Circular Progress Indicator
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: scoreColor.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                  ),
                  CircularPercentIndicator(
                    radius: 70,
                    lineWidth: 16,
                    animation: true,
                    animationDuration: 1200,
                    percent: score / 100,
                    center: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          score.toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            color: scoreColor,
                          ),
                        ),
                        Text(
                          scoreLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    progressColor: scoreColor,
                    backgroundColor: const Color(0xFFE8EAF6),
                    circularStrokeCap: CircularStrokeCap.round,
                  ),
                ],
              ),
              const SizedBox(width: 24),
              
              // Journey Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.journey.destination ?? 'Journey',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      Icons.calendar_today_rounded,
                      DateFormat('MMM dd, yyyy').format(widget.journey.startTime),
                    ),
                    _buildInfoRow(
                      Icons.access_time_rounded,
                      DateFormat('HH:mm').format(widget.journey.startTime),
                    ),
                    _buildInfoRow(
                      Icons.timer_outlined,
                      '${duration.inMinutes} min',
                    ),
                    _buildInfoRow(
                      Icons.straighten_rounded,
                      '${widget.journey.totalDistance.toStringAsFixed(1)} km',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white.withOpacity(0.8)),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(fontSize: 14, color: Colors.white70, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
  
  // 1.5. AI Danger Prediction Output Widget
  Widget _buildDangerPredictionWidget() {
    final prediction = widget.journey.dangerPrediction ?? 'SAFE';

    IconData icon;
    Color color;
    String displayText;

    if (prediction.contains('DANGEROUS')) {
      icon = Icons.warning_amber_rounded;
      color = Colors.redAccent;
      displayText = 'DANGEROUS';
    } else if (prediction.contains('MODERATE')) {
      icon = Icons.warning_outlined;
      color = Colors.orangeAccent;
      displayText = 'MODERATE RISK';
    } else {
      icon = Icons.check_circle_outline;
      color = Colors.greenAccent;
      displayText = 'SAFE';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Danger Assessment',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayText,
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 2. Risk Map (Heatmap)
  Widget _buildRiskMap() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 3,
        color: Colors.white,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.map_rounded, color: Colors.blueAccent, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Risk Heatmap',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E1E2E)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey[200]),
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              child: SizedBox(
                height: 300,
                child: _allMapPoints.isNotEmpty
                    ? Stack(
                        children: [
                          GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: _allMapPoints.first,
                              zoom: 14,
                            ),
                            onMapCreated: (controller) {
                              _mapController = controller;
                              // Set Map Style for Dark Mode
                              _setMapStyle();
                              
                              // Fit bounds to show entire route
                              if (_allMapPoints.length > 1) {
                                double minLat = _allMapPoints
                                    .map((p) => p.latitude)
                                    .reduce((a, b) => a < b ? a : b);
                                double maxLat = _allMapPoints
                                    .map((p) => p.latitude)
                                    .reduce((a, b) => a > b ? a : b);
                                double minLon = _allMapPoints
                                    .map((p) => p.longitude)
                                    .reduce((a, b) => a < b ? a : b);
                                double maxLon = _allMapPoints
                                    .map((p) => p.longitude)
                                    .reduce((a, b) => a > b ? a : b);
                                
                                Future.delayed(const Duration(milliseconds: 500), () {
                                  _mapController?.animateCamera(
                                    CameraUpdate.newLatLngBounds(
                                      LatLngBounds(
                                        southwest: LatLng(minLat, minLon),
                                        northeast: LatLng(maxLat, maxLon),
                                      ),
                                      50,
                                    ),
                                  );
                                });
                              }
                            },
                            markers: _markers,
                            polylines: _polylines,
                            circles: _circles,
                            mapType: MapType.normal,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            zoomGesturesEnabled: true,
                            scrollGesturesEnabled: true,
                            tiltGesturesEnabled: true,
                            rotateGesturesEnabled: true,
                            // CRITICAL: Allows Map to claim gestures inside SingleChildScrollView
                            gestureRecognizers: {
                              Factory<OneSequenceGestureRecognizer>(
                                () => EagerGestureRecognizer(),
                              ),
                            },
                          ),
                    // Map Legend
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Wrap(
                                spacing: 14,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  _buildMapLegend(Colors.blueAccent, 'Route'),
                                  _buildMapLegend(Colors.orangeAccent, 'Sharp Turn'),
                                  _buildMapLegend(Colors.redAccent, 'Risky Turn'),
                                  _buildMapLegend(Colors.purpleAccent, 'Braking'),
                                  _buildMapLegend(const Color(0xFFE040FB), 'Lean'),
                                  _buildMapLegend(Colors.red.withOpacity(0.5), 'Danger Zone'),
                                ],
                              ),
                            ),
                          ),
                          if (!_dangerZonesLoaded)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white70,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map_outlined, size: 56, color: Colors.grey[600]),
                            const SizedBox(height: 16),
                            const Text(
                              'No GPS data available',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
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

  void _setMapStyle() {
    // Use default (light) map style
    _mapController?.setMapStyle(null);
  }

  Widget _buildMapLegend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.5), blurRadius: 4, spreadRadius: 1),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // 3. Turn Analysis Graph
  Widget _buildTurnAnalysisGraph() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 3,
        color: Colors.white,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.show_chart_rounded, color: Colors.purpleAccent, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Turn Analysis',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E1E2E)),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 250,
                child: widget.journey.turnEvents.isNotEmpty
                    ? LineChart(_createLineChartData())
                    : Center(
                        child: Text(
                          'No turn data available',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildGraphLegend(Colors.blueAccent, 'Gyro Z'),
                  const SizedBox(width: 24),
                  _buildGraphLegend(Colors.redAccent, 'Risk Threshold', isDashed: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  LineChartData _createLineChartData() {
    List<FlSpot> spots = [];
    
    for (int i = 0; i < widget.journey.turnEvents.length; i++) {
      final event = widget.journey.turnEvents[i];
      final minutes = event.timestamp.difference(widget.journey.startTime).inMinutes.toDouble();
      spots.add(FlSpot(minutes, event.turnRate.abs()));
    }

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 50,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.grey[200]!,
            strokeWidth: 1,
            dashArray: [5, 5],
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 5,
            getTitlesWidget: (value, meta) {
              return Text(
                '${value.toInt()}m',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 50,
            reservedSize: 42,
            getTitlesWidget: (value, meta) {
              return Text(
                '${value.toInt()}°/s',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: false,
      ),
      minX: 0,
      maxX: spots.isNotEmpty ? spots.map((e) => e.x).reduce((a, b) => a > b ? a : b) : 10,
      minY: 0,
      maxY: 200,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.blueAccent,
          barWidth: 4,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 4,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: Colors.blueAccent,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                Colors.blueAccent.withOpacity(0.3),
                Colors.blueAccent.withOpacity(0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: 150,
            color: Colors.redAccent,
            strokeWidth: 2,
            dashArray: [8, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              padding: const EdgeInsets.only(right: 5, bottom: 5),
              style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
              labelResolver: (line) => 'HIGH RISK',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraphLegend(Color color, String label, {bool isDashed = false}) {
    return Row(
      children: [
        CustomPaint(
          size: const Size(24, 4),
          painter: isDashed ? DashedLinePainter(color) : SolidLinePainter(color),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  // 4. Event Breakdown
  Widget _buildEventBreakdown() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 3,
        color: Colors.white,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.analytics_rounded, color: Colors.orangeAccent, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Event Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E1E2E)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Event Cards — 2 per row
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildEventCard('Sharp Turns', widget.journey.sharpTurns.toString(), Icons.turn_sharp_right_rounded, Colors.orangeAccent)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildEventCard('Risky Turns', widget.journey.riskyTurns.toString(), Icons.warning_rounded, Colors.redAccent)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _buildEventCard('Braking Events', widget.journey.totalBrakingEvents.toString(), Icons.stop_circle_outlined, Colors.purpleAccent)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildEventCard('Max Turn Rate', widget.journey.maxTurnRate.toStringAsFixed(1), Icons.rotate_90_degrees_ccw_rounded, Colors.deepOrangeAccent, suffix: '°/s')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _buildEventCard('Avg Speed', widget.journey.averageSpeed.toStringAsFixed(1), Icons.speed_rounded, Colors.lightBlueAccent, suffix: ' km/h')),
                      const SizedBox(width: 14),
                      Expanded(child: _buildEventCard('Max Speed', widget.journey.maxSpeed.toStringAsFixed(1), Icons.flash_on_rounded, Colors.amberAccent, suffix: ' km/h')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _buildEventCard('Lean Events', widget.journey.leanEvents.length.toString(), Icons.screen_rotation_alt_rounded, const Color(0xFFE040FB))),
                      const SizedBox(width: 14),
                      Expanded(child: Container()), // placeholder for alignment
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventCard(String label, String value, IconData icon, Color color, {String suffix = ''}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (suffix.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 2),
                  child: Text(
                    suffix,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // Additional Info
  Widget _buildAdditionalInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 3,
        color: Colors.white,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.info_outline_rounded, color: Colors.tealAccent, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Additional Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E1E2E)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.grey[200], height: 1),
              const SizedBox(height: 16),
              _buildDetailRow('Start Time',
                  DateFormat('HH:mm:ss').format(widget.journey.startTime)),
              _buildDetailRow(
                  'End Time',
                  widget.journey.endTime != null
                      ? DateFormat('HH:mm:ss').format(widget.journey.endTime!)
                      : 'N/A'),
              _buildDetailRow(
                  'Duration',
                  widget.journey.endTime != null
                      ? '${widget.journey.endTime!.difference(widget.journey.startTime).inMinutes} min'
                      : 'N/A'),
              _buildDetailRow(
                  'Total Distance',
                  '${widget.journey.totalDistance.toStringAsFixed(2)} km'),
              _buildDetailRow(
                  'Avg Speed',
                  '${widget.journey.averageSpeed.toStringAsFixed(1)} km/h'),
              _buildDetailRow(
                  'Max Speed',
                  '${widget.journey.maxSpeed.toStringAsFixed(1)} km/h'),
              _buildDetailRow(
                  'Max Turn Rate',
                  '${widget.journey.maxTurnRate.toStringAsFixed(1)} °/s'),
              _buildDetailRow(
                  'Sharp Turns', widget.journey.sharpTurns.toString()),
              _buildDetailRow(
                  'Risky Turns', widget.journey.riskyTurns.toString()),
              _buildDetailRow(
                  'Braking Events',
                  widget.journey.totalBrakingEvents.toString()),
              _buildDetailRow(
                  'Lean Events',
                  widget.journey.leanEvents.length.toString()),
              _buildDetailRow(
                  'Total Events',
                  (widget.journey.turnEvents.length +
                          widget.journey.brakingEvents.length +
                          widget.journey.leanEvents.length)
                      .toString()),
              _buildDetailRow(
                  'GPS Points', widget.journey.gpsTrack.length.toString()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1E1E2E))),
        ],
      ),
    );
  }

  // 5. Danger Zone Log — chronological list of all danger events
  Widget _buildDangerZoneLog() {
    // Gather all events into a single sortable list
    final List<Map<String, dynamic>> allEvents = [];

    for (final turn in widget.journey.turnEvents) {
      allEvents.add({
        'time': turn.timestamp,
        'type': 'turn',
        'severity': turn.severity,
        'detail': '${turn.turnRate.toStringAsFixed(1)}°/s',
        'icon': Icons.turn_sharp_right_rounded,
        'color': turn.severity == 'risky' ? Colors.redAccent : Colors.orangeAccent,
      });
    }
    for (final brake in widget.journey.brakingEvents) {
      allEvents.add({
        'time': brake.timestamp,
        'type': 'brake',
        'severity': brake.severity,
        'detail': '${brake.deceleration.toStringAsFixed(2)}g @ ${brake.speedBefore.toStringAsFixed(0)} km/h',
        'icon': Icons.stop_circle_outlined,
        'color': Colors.purpleAccent,
      });
    }
    for (final lean in widget.journey.leanEvents) {
      allEvents.add({
        'time': lean.timestamp,
        'type': 'lean',
        'severity': lean.severity,
        'detail': '${lean.leanAngle.toStringAsFixed(1)}° lean',
        'icon': Icons.screen_rotation_alt_rounded,
        'color': const Color(0xFFE040FB),
      });
    }

    // Sort by time
    allEvents.sort((a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));

    if (allEvents.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 3,
        color: Colors.white,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Danger Zone Log',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E1E2E)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.grey[200], height: 1),
              const SizedBox(height: 8),
              ...allEvents.map((event) {
                final time = event['time'] as DateTime;
                final String label;
                if (event['type'] == 'turn') {
                  label = event['severity'] == 'risky' ? 'Risky Turn' : 'Sharp Turn';
                } else if (event['type'] == 'brake') {
                  label = event['severity'] == 'emergency' ? 'Emergency Brake' : 'Hard Brake';
                } else {
                  label = event['severity'] == 'critical' ? 'Critical Lean' : 'Risky Lean';
                }

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey[100]!, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: (event['color'] as Color).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(event['icon'] as IconData, color: event['color'] as Color, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: event['color'] as Color,
                            )),
                            Text(event['detail'] as String, style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            )),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (event['color'] as Color).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          DateFormat('HH:mm:ss').format(time),
                          style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class SolidLinePainter extends CustomPainter {
  final Color color;
  SolidLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DashedLinePainter extends CustomPainter {
  final Color color;
  DashedLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    double dashWidth = 3;
    double dashSpace = 3;
    double startX = 0;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, size.height / 2),
        Offset(startX + dashWidth, size.height / 2),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}