// ============================================================
// JourneyReportScreen.dart  – IT22608086 Post-Journey Component
// Full post-ride report with COMPLETE RIDE VISUALIZATION MAP:
//   • Blue polyline  = full GPS route from start to end
//   • 🟢 Green pin   = Journey Start location
//   • 🔴 Rose pin    = Journey End / Destination
//   • 🔴 Red marker  = Risky Turn danger zone
//   • 🟠 Orange marker = Sharp Turn warning zone
//   • 🟡 Yellow marker = Harsh Brake danger zone
//   • 🔵 Azure marker  = Moderate Brake zone
//   • 🟣 Violet marker = EEG Stress Peak location
//   • 🔵 Cyan marker   = Critical multi-factor event
// Tap any marker to see details (time, reading, location).
// Filter toggles let rider show/hide each danger type.
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
  bool _dangerZonesLoaded = false;

  @override
  void initState() {
    super.initState();
    _prepareMapData();
  }

  /// Placeholder for danger zone loading - removed DangerZoneService dependency
  Future<void> _loadDangerZones() async {
    // Danger zone loading disabled - DangerZoneService not available
    setState(() {
      _dangerZonesLoaded = true;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  // All GPS points available for map display (gpsTrack OR reconstructed from events)
  List<LatLng> _allMapPoints = [];

  void _prepareMapData() {
    List<LatLng> routePoints = [];
    
    // Create polyline from GPS track
    if (widget.journey.gpsTrack.isNotEmpty) {
      routePoints = widget.journey.gpsTrack
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();
    } else {
      // FALLBACK: Reconstruct route from turnEvents + brakingEvents GPS coordinates
      // (gpsTrack is not saved to Firebase to conserve bandwidth, but event coordinates ARE saved)
      final List<LatLng> eventPoints = [];
      for (final event in widget.journey.turnEvents) {
        if (event.latitude != 0.0 && event.longitude != 0.0) {
          eventPoints.add(LatLng(event.latitude, event.longitude));
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
          routePoints.add(LatLng(lean.latitude, lean.longitude));
        }
      }
    }
    
    // Create polyline from available points
    if (routePoints.isNotEmpty) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints,
          color: Colors.blue,
          width: 5,
        ),
      );
    }

    // Add markers for risky turn events
    for (int i = 0; i < widget.journey.turnEvents.length; i++) {
      final event = widget.journey.turnEvents[i];
      if (event.severity == 'risky') {
        _markers.add(
          Marker(
            markerId: MarkerId('risk_$i'),
            position: LatLng(event.latitude, event.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: 'Risky Turn',
              snippet: '${event.turnRate.toStringAsFixed(1)}°/s',
            ),
          ),
        );
      }
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

  Color get _scoreColor {
    if (widget.journey.riskScore >= 80) return Colors.green;
    if (widget.journey.riskScore >= 60) return Colors.orange;
    if (widget.journey.riskScore >= 40) return Colors.deepOrange;
    return Colors.red;
  }

  String _getScoreLabel(double safetyScore) {
    if (safetyScore >= 80) return 'Excellent';
    if (safetyScore >= 60) return 'Good';
    if (safetyScore >= 40) return 'Fair';
    return 'Poor';
  }

  Color _getScoreColor(double safetyScore) {
    if (safetyScore >= 80) return Colors.green;
    if (safetyScore >= 60) return Colors.orange;
    if (safetyScore >= 40) return Colors.deepOrange;
    return Colors.red;
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journey Report'),
        backgroundColor: Colors.blue[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Share feature coming soon!')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Download PDF coming soon!')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. Safety Score Header
            _buildScoreHeader(),

            // 2. Risk Map (Heatmap)
            _buildRiskMap(),

            // 3. Turn Analysis Graph
            _buildTurnAnalysisGraph(),

            // 4. Event Breakdown
            _buildEventBreakdown(),

            // 5. Danger Zone Log
            _buildDangerZoneLog(),

            // Additional Info
            _buildAdditionalInfo(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── 1. Score Header ──────────────────────────────────────
  Widget _buildScoreHeader() {
    final score = _calculateSafetyScore();
    final scoreColor = _getScoreColor(score);
    final scoreLabel = _getScoreLabel(score);
    final duration = widget.journey.endTime != null
        ? widget.journey.endTime!.difference(widget.journey.startTime)
        : Duration.zero;

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
              CircularPercentIndicator(
                radius: 70,
                lineWidth: 12,
                percent: score / 100,
                center: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      score.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      scoreLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                progressColor: scoreColor,
                backgroundColor: Colors.white24,
                circularStrokeCap: CircularStrokeCap.round,
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
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      Icons.calendar_today,
                      DateFormat('MMM dd, yyyy').format(widget.journey.startTime),
                    ),
                    _buildInfoRow(
                      Icons.access_time,
                      DateFormat('HH:mm').format(widget.journey.startTime),
                    ),
                    _buildInfoRow(
                      Icons.timer,
                      '${duration.inMinutes} min',
                    ),
                    _buildInfoRow(
                      Icons.straighten,
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 14, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // 2. Risk Map (Heatmap)
  Widget _buildRiskMap() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.map, color: Colors.blue[700], size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Risk Heatmap',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 300,
              child: widget.journey.gpsTrack.isNotEmpty
                  ? GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          widget.journey.gpsTrack.first.latitude,
                          widget.journey.gpsTrack.first.longitude,
                        ),
                        zoom: 14,
                      ),
                      onMapCreated: (controller) {
                        _mapController = controller;
                        // Fit bounds to show entire route
                        if (widget.journey.gpsTrack.length > 1) {
                          double minLat = widget.journey.gpsTrack
                              .map((p) => p.latitude)
                              .reduce((a, b) => a < b ? a : b);
                          double maxLat = widget.journey.gpsTrack
                              .map((p) => p.latitude)
                              .reduce((a, b) => a > b ? a : b);
                          double minLon = widget.journey.gpsTrack
                              .map((p) => p.longitude)
                              .reduce((a, b) => a < b ? a : b);
                          double maxLon = widget.journey.gpsTrack
                              .map((p) => p.longitude)
                              .reduce((a, b) => a > b ? a : b);
                          
                          _mapController?.animateCamera(
                            CameraUpdate.newLatLngBounds(
                              LatLngBounds(
                                southwest: LatLng(minLat, minLon),
                                northeast: LatLng(maxLat, maxLon),
                              ),
                              50,
                            ),
                          );
                        }
                      },
                      markers: _markers,
                      polylines: _polylines,
                      mapType: MapType.normal,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.map_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            'No GPS data available',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildMapLegend(Colors.blue, 'Route'),
                  const SizedBox(width: 20),
                  _buildMapLegend(Colors.red, 'Risk Events'),
                ],
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
          width: 20,
          height: 4,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  // 3. Turn Analysis Graph
  Widget _buildTurnAnalysisGraph() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.show_chart, color: Colors.blue[700], size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Turn Analysis',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 250,
                child: widget.journey.turnEvents.isNotEmpty
                    ? LineChart(_turnChartData())
                    : Center(
                        child: Text(
                          'No turn data available',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildGraphLegend(Colors.blue, 'Gyro Z'),
                  const SizedBox(width: 20),
                  _buildGraphLegend(Colors.red, 'Risk Threshold (150°/s)', isDashed: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dangerHeader(String title, Color color, int count) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(6),
      border: Border(left: BorderSide(color: color, width: 4)),
    ),
    child: Row(children: [
      Expanded(child: Text(title,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    ]),
  );

  Widget _eventRow(IconData icon, Color color, String reading,
      DateTime time, double lat, double lng) =>
      Padding(
        padding: const EdgeInsets.only(left: 10, bottom: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(reading,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              Row(children: [
                Icon(Icons.access_time, size: 11, color: Colors.grey[500]),
                const SizedBox(width: 3),
                Text(DateFormat('HH:mm:ss').format(time),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(width: 10),
                Icon(Icons.location_on, size: 11, color: Colors.grey[500]),
                const SizedBox(width: 3),
                Expanded(
                  child: Text('${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ),
              ]),
            ]),
          ),
        ]),
      );


  // ── 5. Turn Rate Chart ───────────────────────────────────
  Widget _buildTurnChart() {
    if (widget.journey.turnEvents.isEmpty) return const SizedBox();
    return _section(
      icon: Icons.show_chart,
      title: 'Turn Rate Over Time',
      child: Column(children: [
        SizedBox(height: 220, child: LineChart(_turnChartData())),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _chartLegend(Colors.blue, 'Turn Rate (°/s)'),
          _chartLegend(Colors.orange, 'Sharp ≥100°/s', dashed: true),
          _chartLegend(Colors.red, 'Risky ≥150°/s', dashed: true),
        ]),
      ]),
    );
  }


  LineChartData _turnChartData() {
    final spots = widget.journey.turnEvents.map((e) {
      final min = e.timestamp.difference(widget.journey.startTime).inSeconds / 60.0;
      return FlSpot(min, e.turnRate.abs());
    }).toList();
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 50,
        verticalInterval: 5,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.grey[300]!,
            strokeWidth: 1,
          );
        },
        getDrawingVerticalLine: (value) {
          return FlLine(
            color: Colors.grey[300]!,
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
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
                style: const TextStyle(fontSize: 10),
              );
            },
          ),
          axisNameWidget: const Text(
            'Time',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
                style: const TextStyle(fontSize: 10),
              );
            },
          ),
          axisNameWidget: const Text(
            'Gyro Z',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey[300]!),
      ),
      minX: 0,
      maxX: spots.isNotEmpty ? spots.map((e) => e.x).reduce((a, b) => a > b ? a : b) : 10,
      minY: 0,
      maxY: 200,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.blue,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: Colors.blue.withOpacity(0.1),
          ),
        ),
      ],
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: 150,
            color: Colors.red,
            strokeWidth: 2,
            dashArray: [5, 5],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              padding: const EdgeInsets.only(right: 5, bottom: 5),
              style: const TextStyle(color: Colors.red, fontSize: 10),
              labelResolver: (line) => 'Risk',
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
          size: const Size(20, 4),
          painter: isDashed ? DashedLinePainter(color) : SolidLinePainter(color),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  // ── 7. Event Breakdown Cards ─────────────────────────────
  Widget _buildEventBreakdown() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.analytics, color: Colors.blue[700], size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Event Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildEventCard(
                    'Sharp Turns',
                    widget.journey.sharpTurns.toString(),
                    Icons.turn_sharp_right,
                    Colors.orange,
                  ),
                  _buildEventCard(
                    'Risky Turns',
                    widget.journey.riskyTurns.toString(),
                    Icons.warning,
                    Colors.red,
                  ),
                  _buildEventCard(
                    'Avg Speed',
                    '${widget.journey.averageSpeed.toStringAsFixed(1)} km/h',
                    Icons.speed,
                    Colors.blue,
                  ),
                  _buildEventCard(
                    'Max Speed',
                    '${widget.journey.maxSpeed.toStringAsFixed(1)} km/h',
                    Icons.flash_on,
                    Colors.purple,
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

  Widget _buildEventCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: (MediaQuery.of(context).size.width - 76) / 2,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Additional Info
  Widget _buildAdditionalInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Additional Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
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

  // Helper widget for section headers
  Widget _section({required IconData icon, required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.blue[700], size: 24),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget for chart legend items
  Widget _chartLegend(Color color, String label, {bool dashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dashed
            ? CustomPaint(
                size: const Size(20, 4),
                painter: DashedLinePainter(color),
              )
            : Container(
                width: 20,
                height: 4,
                color: color,
              ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
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