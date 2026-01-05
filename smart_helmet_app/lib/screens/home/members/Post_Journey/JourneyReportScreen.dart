import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:intl/intl.dart';
import '../../../../models/journey_model.dart';

class JourneyReportScreen extends StatefulWidget {
  final JourneyData journey;

  const JourneyReportScreen({super.key, required this.journey});

  @override
  State<JourneyReportScreen> createState() => _JourneyReportScreenState();
}

class _JourneyReportScreenState extends State<JourneyReportScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _prepareMapData();
  }

  void _prepareMapData() {
    // Create polyline from GPS track
    if (widget.journey.gpsTrack.isNotEmpty) {
      List<LatLng> routePoints = widget.journey.gpsTrack
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();

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
  }

  // Calculate safety score (0-100)
  double _calculateSafetyScore() {
    int score = 100;
    
    // Deduct points for risky turns
    score -= widget.journey.riskyTurns * 10;
    
    // Deduct points for sharp turns
    score -= widget.journey.sharpTurns * 3;
    
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
            _buildSafetyScoreHeader(safetyScore, duration),

            // 2. Risk Map (Heatmap)
            _buildRiskMap(),

            // 3. Turn Analysis Graph
            _buildTurnAnalysisGraph(),

            // 4. Event Breakdown
            _buildEventBreakdown(),

            // Additional Info
            _buildAdditionalInfo(),

            const SizedBox(height: 24),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[700]!, Colors.blue[900]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
                    ? LineChart(_createLineChartData())
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

  // 4. Event Breakdown
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
              const Divider(height: 24),
              _buildDetailRow('Total Events', widget.journey.turnEvents.length.toString()),
              _buildDetailRow('Start Time', DateFormat('HH:mm:ss').format(widget.journey.startTime)),
              _buildDetailRow('End Time', widget.journey.endTime != null 
                  ? DateFormat('HH:mm:ss').format(widget.journey.endTime!)
                  : 'N/A'),
              _buildDetailRow('GPS Points', widget.journey.gpsTrack.length.toString()),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.wb_sunny, color: Colors.orange[600], size: 20),
                  const SizedBox(width: 8),
                  const Text('Weather: Clear', style: TextStyle(fontSize: 14)),
                ],
              ),
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
}

// Custom painters for legend
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