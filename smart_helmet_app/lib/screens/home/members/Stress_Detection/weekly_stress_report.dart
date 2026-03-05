// weekly_stress_report.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pdf/pdf.dart' as pdf_lib;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../services/auth_service.dart';

class WeeklyStressReport extends StatefulWidget {
  const WeeklyStressReport({super.key});

  @override
  State<WeeklyStressReport> createState() => _WeeklyStressReportState();
}

class _WeeklyStressReportState extends State<WeeklyStressReport> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _weeklyData = [];
  bool _isLoading = true;
  String _error = '';

  // Stats
  double avgStress = 0.0;
  int highStressDays = 0;
  Map<String, int> moodDistribution = {
    'Stressed': 0,
    'Neutral': 0,
    'Relaxed': 0
  };

  // Stress level distribution
  int highStressCount = 0;
  int moderateStressCount = 0;
  int lowStressCount = 0;

  // Daily averages for cleaner line chart
  List<MapEntry<String, double>> _dailyAverages = [];

  // Google Maps
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _fetchWeeklyData();
  }

  Future<void> _fetchWeeklyData() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final userId = auth.userId;

    if (userId == null) {
      setState(() {
        _error = "Please log in to view your personal weekly report.";
        _isLoading = false;
      });
      return;
    }

    try {
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      final query = _firestore
          .collection("stress_mood_readings")
          .where("userId", isEqualTo: userId)
          .where("createdAt",
              isGreaterThanOrEqualTo: Timestamp.fromDate(sevenDaysAgo))
          .orderBy("createdAt");

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        setState(() {
          _error = "No stress/mood data recorded in the past 7 days.";
          _isLoading = false;
        });
        return;
      }

      _weeklyData = snapshot.docs.map((doc) => doc.data()).toList();

      // ────────────────────────────────────────────────
      // Calculate statistics + daily averages
      // ────────────────────────────────────────────────
      Map<String, List<Map<String, dynamic>>> dailyGroups = {};
      for (var reading in _weeklyData) {
        final timestamp =
            (reading['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        final dayKey = DateFormat('yyyy-MM-dd').format(timestamp);
        dailyGroups.putIfAbsent(dayKey, () => []);
        dailyGroups[dayKey]!.add(reading);
      }

      double totalStress = 0.0;
      int totalDays = 0;
      _dailyAverages.clear();

      dailyGroups.forEach((day, readings) {
        double daySum = readings.fold(0.0,
            (sum, r) => sum + (r['stressScore'] as num? ?? 0.0).toDouble());
        double dayAvg = daySum / readings.length;

        totalStress += dayAvg;
        totalDays++;

        _dailyAverages.add(MapEntry(day, dayAvg));

        if (dayAvg > 0.7) highStressDays++;

        for (var r in readings) {
          final mood = r['currentMood'] as String? ?? 'Neutral';
          moodDistribution[mood] = (moodDistribution[mood] ?? 0) + 1;

          final stress = (r['stressScore'] as num?)?.toDouble() ?? 0.0;
          if (stress > 0.7)
            highStressCount++;
          else if (stress > 0.4)
            moderateStressCount++;
          else
            lowStressCount++;
        }
      });

      if (totalDays > 0) avgStress = totalStress / totalDays;

      // Build map markers
      _buildStressLocationMarkers();

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = "Error loading report: $e\n\n(Please check Firestore index.)";
        _isLoading = false;
      });
    }
  }

  void _buildStressLocationMarkers() {
    _markers.clear();

    for (var reading in _weeklyData) {
      final geo = reading['location'] as GeoPoint?;
      if (geo == null) continue;

      final lat = geo.latitude;
      final lng = geo.longitude;
      final stress = (reading['stressScore'] as num?)?.toDouble() ?? 0.0;
      final mood = reading['currentMood'] as String? ?? 'Neutral';
      final time = (reading['timestamp'] as String?) ?? '';

      BitmapDescriptor markerIcon = BitmapDescriptor.defaultMarkerWithHue(
        stress > 0.7
            ? BitmapDescriptor.hueRed
            : stress > 0.4
                ? BitmapDescriptor.hueOrange
                : BitmapDescriptor.hueGreen,
      );

      _markers.add(
        Marker(
          markerId: MarkerId(time),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(
            title: '${(stress * 100).toStringAsFixed(0)}% Stress • $mood',
            snippet: 'Time: ${time.substring(11, 16)}',
          ),
          icon: markerIcon,
        ),
      );
    }

    if (_weeklyData.isNotEmpty && _mapController != null) {
      final first = _weeklyData.first['location'] as GeoPoint?;
      if (first != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
              LatLng(first.latitude, first.longitude), 12),
        );
      }
    }
  }

  List<FlSpot> _getDailyStressSpots() {
    return _dailyAverages.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.value);
    }).toList();
  }

  List<PieChartSectionData> _getStressPieSections() {
    final total = highStressCount + moderateStressCount + lowStressCount;
    if (total == 0) return [];

    final highPct = (highStressCount / total * 100);
    final modPct = (moderateStressCount / total * 100);
    final lowPct = (lowStressCount / total * 100);

    return [
      PieChartSectionData(
        value: highStressCount.toDouble(),
        title: highStressCount > 0 ? '${highPct.toStringAsFixed(0)}%' : '',
        color: Colors.redAccent.withOpacity(0.9),
        radius: 90,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
        ),
      ),
      PieChartSectionData(
        value: moderateStressCount.toDouble(),
        title: moderateStressCount > 0 ? '${modPct.toStringAsFixed(0)}%' : '',
        color: Colors.orangeAccent.withOpacity(0.9),
        radius: 90,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
        ),
      ),
      PieChartSectionData(
        value: lowStressCount.toDouble(),
        title: lowStressCount > 0 ? '${lowPct.toStringAsFixed(0)}%' : '',
        color: Colors.greenAccent.withOpacity(0.9),
        radius: 90,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
        ),
      ),
    ];
  }

  Widget _buildStressPieLegend() {
    final total = highStressCount + moderateStressCount + lowStressCount;
    if (total == 0) return const SizedBox.shrink();

    return Column(
      children: [
        _legendItem(
            Colors.redAccent, 'High Stress (>70%)', highStressCount, total),
        _legendItem(Colors.orangeAccent, 'Moderate (40–70%)',
            moderateStressCount, total),
        _legendItem(
            Colors.greenAccent, 'Low/Relaxed (≤40%)', lowStressCount, total),
      ],
    );
  }

  Widget _legendItem(Color color, String label, int count, int total) {
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0.0';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 2)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$label: $count readings ($pct%)',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateAndDownloadPdf() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pdf_lib.PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Your Weekly Stress & Mood Report',
                style:
                    pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 20),
          pw.Text('Personal Report • Last 7 Days',
              style: pw.TextStyle(fontSize: 16)),
          pw.SizedBox(height: 20),
          pw.Text('Summary:',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Bullet(
              text: 'Average Stress Level: ${avgStress.toStringAsFixed(2)}'),
          pw.Bullet(text: 'High Stress Days: $highStressDays'),
          pw.SizedBox(height: 16),
          pw.Text('Stress Level Distribution:',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Bullet(text: 'High (>70%): $highStressCount readings'),
          pw.Bullet(text: 'Moderate (40–70%): $moderateStressCount readings'),
          pw.Bullet(text: 'Low/Relaxed (≤40%): $lowStressCount readings'),
          pw.SizedBox(height: 20),
          pw.Text('Key Locations & Stress Zones:',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          ..._weeklyData.map((r) {
            final geo = r['location'] as GeoPoint?;
            final stress = (r['stressScore'] as num?)?.toDouble() ?? 0.0;
            final mood = r['currentMood'] as String? ?? '—';
            final time = (r['timestamp'] as String?)?.substring(0, 19) ?? '—';
            return pw.Text(
              '• $time | ${stress.toStringAsFixed(2)} Stress | $mood | Lat: ${geo?.latitude.toStringAsFixed(4)}, Lng: ${geo?.longitude.toStringAsFixed(4)}',
            );
          }),
          pw.SizedBox(height: 20),
          pw.Text('Health Recommendations:',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Paragraph(text: _getHealthTips()),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename:
          'weekly_stress_report_${DateTime.now().toIso8601String().substring(0, 10)}.pdf',
    );
  }

  String _getHealthTips() {
    if (avgStress > 0.65 || highStressDays >= 4 || highStressCount > 10) {
      return "Your stress levels were significantly elevated this week, particularly in certain locations. "
          "Persistent high stress can impact physical and mental health. Consider consulting a healthcare professional "
          "if symptoms like anxiety, fatigue, headaches, or sleep disturbances continue. "
          "Immediate steps: practice 4-7-8 breathing in high-stress zones, take short walks, and prioritize recovery.";
    } else if (avgStress > 0.4) {
      return "Moderate stress levels detected — you're managing it reasonably well. "
          "To shift toward more relaxed states: incorporate 5–10 minutes of mindfulness daily, "
          "stay hydrated, reduce screen time before bed, and use calm locations for breaks.";
    } else {
      return "Outstanding! Your week was dominated by low stress and relaxation. "
          "This balance supports strong mental resilience. Continue your healthy routines — "
          "they're clearly working very effectively for you.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Weekly Report')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: Colors.grey),
              const SizedBox(height: 24),
              const Text(
                "Sign in to view your personal weekly report",
                style: TextStyle(fontSize: 18, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Weekly Stress Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _weeklyData.isNotEmpty ? _generateAndDownloadPdf : null,
            tooltip: 'Download PDF',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child:
                      Text(_error, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _fetchWeeklyData,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Summary Card
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Weekly Summary',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _statItem('Avg Stress',
                                        '${avgStress.toStringAsFixed(2)}'),
                                    _statItem(
                                        'High Days', '$highStressDays / 7'),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text('Mood Distribution:',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                Text(
                                  'Stressed: ${moodDistribution['Stressed']} • '
                                  'Neutral: ${moodDistribution['Neutral']} • '
                                  'Relaxed: ${moodDistribution['Relaxed']}',
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Professional Stress Trend Chart
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Daily Average Stress Trend',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 260,
                                  child: _dailyAverages.isEmpty
                                      ? const Center(
                                          child: Text('No data yet',
                                              style: TextStyle(
                                                  color: Colors.grey)))
                                      : LineChart(
                                          LineChartData(
                                            lineTouchData: LineTouchData(
                                              enabled: true,
                                              touchTooltipData:
                                                  LineTouchTooltipData(
                                                getTooltipColor:
                                                    (touchedSpot) => Colors
                                                        .black
                                                        .withOpacity(0.8),
                                                getTooltipItems:
                                                    (touchedSpots) {
                                                  return touchedSpots
                                                      .map((spot) {
                                                    final day = _dailyAverages[
                                                            spot.x.toInt()]
                                                        .key;
                                                    return LineTooltipItem(
                                                      '${DateFormat('MMM dd').format(DateTime.parse(day))}\n'
                                                      '${(spot.y * 100).toStringAsFixed(0)}% Stress',
                                                      const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 14),
                                                    );
                                                  }).toList();
                                                },
                                              ),
                                            ),
                                            gridData: FlGridData(
                                              show: true,
                                              drawVerticalLine: true,
                                              horizontalInterval: 0.2,
                                              verticalInterval: 1,
                                              getDrawingHorizontalLine:
                                                  (value) => FlLine(
                                                color: Colors.grey
                                                    .withOpacity(0.2),
                                                strokeWidth: 1,
                                              ),
                                              getDrawingVerticalLine: (value) =>
                                                  FlLine(
                                                color: Colors.grey
                                                    .withOpacity(0.1),
                                                strokeWidth: 1,
                                              ),
                                            ),
                                            titlesData: FlTitlesData(
                                              leftTitles: AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: true,
                                                  reservedSize: 40,
                                                  interval: 0.2,
                                                  getTitlesWidget:
                                                      (value, meta) => Text(
                                                    '${(value * 100).toInt()}%',
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey),
                                                  ),
                                                ),
                                              ),
                                              bottomTitles: AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: true,
                                                  reservedSize: 40,
                                                  interval: 1,
                                                  getTitlesWidget:
                                                      (value, meta) {
                                                    if (value.toInt() >=
                                                        _dailyAverages.length)
                                                      return const Text('');
                                                    final day = _dailyAverages[
                                                            value.toInt()]
                                                        .key;
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 8),
                                                      child: Text(
                                                        DateFormat('dd').format(
                                                            DateTime.parse(
                                                                day)),
                                                        style: const TextStyle(
                                                            fontSize: 12,
                                                            color: Colors.grey),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                              topTitles: const AxisTitles(
                                                  sideTitles: SideTitles(
                                                      showTitles: false)),
                                              rightTitles: const AxisTitles(
                                                  sideTitles: SideTitles(
                                                      showTitles: false)),
                                            ),
                                            borderData:
                                                FlBorderData(show: false),
                                            minX: 0,
                                            maxX: (_dailyAverages.length - 1)
                                                .toDouble(),
                                            minY: 0,
                                            maxY: 1.0,
                                            lineBarsData: [
                                              LineChartBarData(
                                                spots: _getDailyStressSpots(),
                                                isCurved: true,
                                                curveSmoothness: 0.4,
                                                color: Colors.redAccent,
                                                barWidth: 3.5,
                                                dotData: FlDotData(
                                                  show: true,
                                                  getDotPainter: (spot, percent,
                                                          barData, index) =>
                                                      FlDotCirclePainter(
                                                    radius: 5,
                                                    color: Colors.redAccent,
                                                    strokeColor: Colors.white,
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                                belowBarData: BarAreaData(
                                                  show: true,
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [
                                                      Colors.redAccent
                                                          .withOpacity(0.35),
                                                      Colors.redAccent
                                                          .withOpacity(0.05),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 12),
                                const Center(
                                  child: Text(
                                    'Daily average stress level • Higher = more stressed',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Locations Map
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Your Locations & Stress Zones',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                const Text(
                                  'Red = High Stress • Orange = Moderate • Green = Relaxed',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 13),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 320,
                                  child: _weeklyData.isEmpty || _markers.isEmpty
                                      ? const Center(
                                          child: Text(
                                              'No location data this week'))
                                      : ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: GoogleMap(
                                            initialCameraPosition:
                                                const CameraPosition(
                                              target: LatLng(7.2000, 79.8730),
                                              zoom: 11,
                                            ),
                                            markers: _markers,
                                            onMapCreated: (controller) {
                                              _mapController = controller;
                                              if (_weeklyData.isNotEmpty) {
                                                final first = _weeklyData
                                                        .first['location']
                                                    as GeoPoint?;
                                                if (first != null) {
                                                  controller.animateCamera(
                                                    CameraUpdate.newLatLngZoom(
                                                      LatLng(first.latitude,
                                                          first.longitude),
                                                      12,
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                            myLocationEnabled: false,
                                            zoomControlsEnabled: true,
                                            mapToolbarEnabled: false,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Professional Stress Level Pie Chart
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Stress Level Distribution This Week',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 280,
                                  child: highStressCount +
                                              moderateStressCount +
                                              lowStressCount ==
                                          0
                                      ? const Center(
                                          child: Text(
                                              'No stress level data recorded',
                                              style: TextStyle(
                                                  color: Colors.grey)))
                                      : PieChart(
                                          PieChartData(
                                            pieTouchData: PieTouchData(
                                              touchCallback:
                                                  (FlTouchEvent event,
                                                      pieTouchResponse) {
                                                // You can add tooltip logic here if desired
                                              },
                                            ),
                                            borderData:
                                                FlBorderData(show: false),
                                            sectionsSpace: 3,
                                            centerSpaceRadius: 50,
                                            sections: _getStressPieSections(),
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 20),
                                _buildStressPieLegend(),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Health Recommendations
                        Card(
                          elevation: 4,
                          color: avgStress > 0.6
                              ? Colors.orange.shade50
                              : Colors.green.shade50,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Health Recommendations',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                Text(
                                  _getHealthTips(),
                                  style: const TextStyle(
                                      height: 1.5, fontSize: 15),
                                ),
                                if (avgStress > 0.65 || highStressDays >= 4)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: const [
                                        Icon(Icons.medical_services,
                                            color: Colors.redAccent, size: 28),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            "Frequent high stress in certain locations may indicate environmental or situational triggers. "
                                            "Consider speaking to a healthcare professional if symptoms (anxiety, fatigue, headaches) persist.",
                                            style: TextStyle(
                                                color: Colors.redAccent,
                                                fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      ],
    );
  }
}
