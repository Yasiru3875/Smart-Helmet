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

  // Google Maps controller
  GoogleMapController? _mapController;

  // Markers for map (color-coded by stress)
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

      // Calculate stats
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

      dailyGroups.forEach((day, readings) {
        double dayAvg = readings
                .map((r) => (r['stressScore'] as num?)?.toDouble() ?? 0.0)
                .reduce((a, b) => a + b) /
            readings.length;

        totalStress += dayAvg;
        totalDays++;

        if (dayAvg > 0.7) highStressDays++;

        for (var r in readings) {
          final mood = r['currentMood'] as String? ?? 'Neutral';
          moodDistribution[mood] = (moodDistribution[mood] ?? 0) + 1;
        }
      });

      if (totalDays > 0) avgStress = totalStress / totalDays;

      // Build map markers
      _buildStressLocationMarkers();

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error =
            "Error loading report: $e\n\n(Please check if the Firestore index exists.)";
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

      Color markerColor;
      if (stress > 0.7) {
        markerColor = Colors.red;
      } else if (stress > 0.4) {
        markerColor = Colors.orange;
      } else {
        markerColor = Colors.green;
      }

      _markers.add(
        Marker(
          markerId: MarkerId(time),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(
            title: '${(stress * 100).toStringAsFixed(0)}% Stress • $mood',
            snippet: 'Time: ${time.substring(11, 16)}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            markerColor == Colors.red
                ? BitmapDescriptor.hueRed
                : markerColor == Colors.orange
                    ? BitmapDescriptor.hueOrange
                    : BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }

    // Center map on first point or Negombo default
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

  List<FlSpot> _getStressSpots() {
    List<FlSpot> spots = [];
    if (_weeklyData.isNotEmpty) {
      for (int i = 0; i < _weeklyData.length; i++) {
        final stress =
            (_weeklyData[i]['stressScore'] as num?)?.toDouble() ?? 0.0;
        spots.add(FlSpot(i.toDouble(), stress));
      }
    }
    return spots;
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
          pw.Bullet(text: 'Average Stress: ${avgStress.toStringAsFixed(2)}'),
          pw.Bullet(text: 'High Stress Days: $highStressDays'),
          pw.Bullet(
              text:
                  'Mood: Stressed ${moodDistribution['Stressed']}, Neutral ${moodDistribution['Neutral']}, Relaxed ${moodDistribution['Relaxed']}'),
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
    final highStressCount = moodDistribution['Stressed'] ?? 0;
    if (avgStress > 0.65 || highStressDays >= 4 || highStressCount > 10) {
      return "Your stress levels were elevated this week, especially in certain locations. "
          "If you felt anxious, had headaches, or poor sleep in those areas, consider consulting a doctor. "
          "Try deep breathing, short walks, or mindfulness when in high-stress zones.";
    } else if (avgStress > 0.4) {
      return "Moderate stress detected. Your body handled it well overall. "
          "To stay in the relaxed zone longer, maintain hydration, limit caffeine, and take 5-minute breaks in calm locations.";
    } else {
      return "Excellent! You stayed mostly relaxed this week. "
          "Keep protecting your mental health with regular rest and positive routines.";
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
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Summary • Last 7 Days',
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 16),
                                Text(
                                    'Avg Stress: ${avgStress.toStringAsFixed(2)}'),
                                Text('High Stress Days: $highStressDays'),
                                const SizedBox(height: 12),
                                Text('Mood Breakdown:',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                Text(
                                    'Stressed: ${moodDistribution['Stressed']} • '
                                    'Neutral: ${moodDistribution['Neutral']} • '
                                    'Relaxed: ${moodDistribution['Relaxed']}'),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Stress Trend Chart
                        const Text('Stress Trend Over Time',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        SizedBox(
                          height: 240,
                          child: _weeklyData.isEmpty
                              ? const Center(child: Text('No data yet'))
                              : LineChart(
                                  LineChartData(
                                    lineBarsData: [
                                      LineChartBarData(
                                        spots: _getStressSpots(),
                                        isCurved: true,
                                        color: Colors.redAccent,
                                        barWidth: 3,
                                        dotData: const FlDotData(show: false),
                                      ),
                                    ],
                                    gridData: const FlGridData(show: true),
                                    titlesData: const FlTitlesData(show: true),
                                    borderData: FlBorderData(show: true),
                                  ),
                                ),
                        ),

                        const SizedBox(height: 32),

                        // Locations Map – NEW FEATURE
                        const Text('Your Locations & Stress Zones',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        const Text(
                            'Red = High Stress • Orange = Moderate • Green = Relaxed',
                            style: TextStyle(color: Colors.grey, fontSize: 14)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 300,
                          child: _weeklyData.isEmpty || _markers.isEmpty
                              ? const Center(
                                  child: Text('No location data available'))
                              : GoogleMap(
                                  initialCameraPosition: const CameraPosition(
                                    target: LatLng(
                                        7.2000, 79.8730), // Negombo default
                                    zoom: 11,
                                  ),
                                  markers: _markers,
                                  onMapCreated: (controller) {
                                    _mapController = controller;
                                    if (_weeklyData.isNotEmpty) {
                                      final first = _weeklyData
                                          .first['location'] as GeoPoint?;
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

                        const SizedBox(height: 32),

                        // Health Tips
                        Card(
                          color: avgStress > 0.6
                              ? Colors.orange.shade50
                              : Colors.green.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Health Recommendations',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 12),
                                Text(
                                  _getHealthTips(),
                                  style: const TextStyle(height: 1.5),
                                ),
                                if (avgStress > 0.65 || highStressDays >= 4)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Row(
                                      children: const [
                                        Icon(Icons.medical_services,
                                            color: Colors.redAccent),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            "If stress symptoms (anxiety, fatigue, headaches) were frequent in certain locations, speak to a doctor.",
                                            style: TextStyle(
                                                color: Colors.redAccent),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Detailed Readings List
                        const Text('All Readings',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _weeklyData.length,
                          itemBuilder: (context, index) {
                            final r = _weeklyData[index];
                            final ts = (r['createdAt'] as Timestamp?)?.toDate();
                            final geo = r['location'] as GeoPoint?;
                            final stress =
                                (r['stressScore'] as num?)?.toDouble() ?? 0.0;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: stress > 0.7
                                      ? Colors.red
                                      : stress > 0.4
                                          ? Colors.orange
                                          : Colors.green,
                                  child: Text(
                                    (stress * 100).toStringAsFixed(0),
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 14),
                                  ),
                                ),
                                title: Text(r['currentMood'] as String? ?? '—'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ts != null
                                          ? DateFormat('MMM dd, HH:mm')
                                              .format(ts)
                                          : '—',
                                    ),
                                    if (geo != null)
                                      Text(
                                        'Location: ${geo.latitude.toStringAsFixed(5)}, ${geo.longitude.toStringAsFixed(5)}',
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.grey),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
