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

  // User details
  String? _userName;
  int? _age;
  String? _gender;
  double? _heightCm;
  double? _weightKg;
  double? _bmi;
  String _bmiCategory = '';

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
      // Fetch user profile
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        setState(() {
          _error = "User profile not found.";
          _isLoading = false;
        });
        return;
      }

      _userName = userDoc['userName'] as String?;
      _age = userDoc['age'] as int?;
      _gender = userDoc['gender'] as String?;
      _heightCm = (userDoc['heightCm'] as num?)?.toDouble();
      _weightKg = (userDoc['weightKg'] as num?)?.toDouble();

      if (_heightCm != null && _weightKg != null && _heightCm! > 0) {
        _bmi = _weightKg! / ((_heightCm! / 100) * (_heightCm! / 100));
        if (_bmi! < 18.5) {
          _bmiCategory = 'Underweight';
        } else if (_bmi! < 25) {
          _bmiCategory = 'Normal';
        } else if (_bmi! < 30) {
          _bmiCategory = 'Overweight';
        } else {
          _bmiCategory = 'Obese';
        }
      }

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
      final geo = reading['currentLocation'] as GeoPoint?;
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
      final first = _weeklyData.first['currentLocation'] as GeoPoint?;
      if (first != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
              LatLng(first.latitude, first.longitude), 12),
        );
      }
    }
  }

  List<FlSpot> _getDailyStressSpots() {
    return _dailyAverages.asMap().entries.map((entry) {
      return FlSpot(
        entry.key.toDouble(), // index → x
        entry.value.value, // MapEntry.value → y (double)
      );
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

  List<BarChartGroupData> _getMoodBarGroups() {
    final stressed = moodDistribution['Stressed'] ?? 0;
    final neutral = moodDistribution['Neutral'] ?? 0;
    final relaxed = moodDistribution['Relaxed'] ?? 0;

    return [
      BarChartGroupData(
        x: 0,
        barRods: [
          BarChartRodData(
            toY: stressed.toDouble(),
            color: Colors.redAccent,
            width: 40,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
      BarChartGroupData(
        x: 1,
        barRods: [
          BarChartRodData(
            toY: neutral.toDouble(),
            color: Colors.orangeAccent,
            width: 40,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
      BarChartGroupData(
        x: 2,
        barRods: [
          BarChartRodData(
            toY: relaxed.toDouble(),
            color: Colors.greenAccent,
            width: 40,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    ];
  }

  Future<void> _generateAndDownloadPdf() async {
    final pdf = pw.Document();

    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final dateRange =
        '${DateFormat('MMM dd, yyyy').format(sevenDaysAgo)} - ${DateFormat('MMM dd, yyyy').format(now)}';

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
          pw.SizedBox(height: 8),
          pw.Text(
              'Personalized Report for: ${_userName ?? 'User'} (${_age ?? ''} years, ${_gender ?? ''})',
              style:
                  pw.TextStyle(fontSize: 16, color: pdf_lib.PdfColors.grey800)),
          pw.Text('Date Range: $dateRange',
              style:
                  pw.TextStyle(fontSize: 14, color: pdf_lib.PdfColors.grey600)),
          pw.SizedBox(height: 16),
          pw.Text('Profile Summary:',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Bullet(text: 'Height: ${_heightCm?.toStringAsFixed(0) ?? '—'} cm'),
          pw.Bullet(text: 'Weight: ${_weightKg?.toStringAsFixed(0) ?? '—'} kg'),
          pw.Bullet(
              text:
                  'BMI: ${_bmi?.toStringAsFixed(1) ?? '—'} (${_bmiCategory})'),
          pw.SizedBox(height: 20),
          pw.Text('Stress & Mood Summary:',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Bullet(
              text: 'Average Stress Level: ${avgStress.toStringAsFixed(2)}'),
          pw.Bullet(text: 'High Stress Days: $highStressDays / 7'),
          pw.Bullet(text: 'Total Readings: ${_weeklyData.length}'),
          pw.SizedBox(height: 16),
          pw.Text('Stress Level Distribution:',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Bullet(text: 'High (>70%): $highStressCount readings'),
          pw.Bullet(text: 'Moderate (40–70%): $moderateStressCount readings'),
          pw.Bullet(text: 'Low/Relaxed (≤40%): $lowStressCount readings'),
          pw.SizedBox(height: 16),
          pw.Text('Mood Distribution:',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Bullet(text: 'Stressed: ${moodDistribution['Stressed']} readings'),
          pw.Bullet(text: 'Neutral: ${moodDistribution['Neutral']} readings'),
          pw.Bullet(text: 'Relaxed: ${moodDistribution['Relaxed']} readings'),
          pw.SizedBox(height: 20),
          pw.Text('Key Locations & Stress Zones:',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          ..._weeklyData.map((r) {
            final geo = r['currentLocation'] as GeoPoint?;
            final stress = (r['stressScore'] as num?)?.toDouble() ?? 0.0;
            final mood = r['currentMood'] as String? ?? '—';
            final time = (r['timestamp'] as String?)?.substring(0, 19) ?? '—';
            return pw.Text(
              '• $time | ${stress.toStringAsFixed(2)} Stress | $mood | Lat: ${geo?.latitude.toStringAsFixed(4)}, Lng: ${geo?.longitude.toStringAsFixed(4)}',
            );
          }),
          pw.SizedBox(height: 20),
          pw.Text('Personalized Health Recommendations:',
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
    String baseTips = '';
    if (avgStress > 0.65 || highStressDays >= 4 || highStressCount > 10) {
      baseTips =
          "Your stress levels were significantly elevated this week, particularly in certain locations. "
          "Persistent high stress can impact physical and mental health. Consider consulting a healthcare professional "
          "if symptoms like anxiety, fatigue, headaches, or sleep disturbances continue. "
          "Immediate steps: practice 4-7-8 breathing in high-stress zones, take short walks, and prioritize recovery.";
    } else if (avgStress > 0.4) {
      baseTips =
          "Moderate stress levels detected — you're managing it reasonably well. "
          "To shift toward more relaxed states: incorporate 5–10 minutes of mindfulness daily, "
          "stay hydrated, reduce screen time before bed, and use calm locations for breaks.";
    } else {
      baseTips =
          "Outstanding! Your week was dominated by low stress and relaxation. "
          "This balance supports strong mental resilience. Continue your healthy routines — "
          "they're clearly working very effectively for you.";
    }

    // Incorporate BMI
    String bmiAdvice = '';
    if (_bmi != null) {
      if (_bmi! < 18.5) {
        bmiAdvice =
            "\n\nBMI Note: Your BMI indicates underweight. Consider a balanced diet with more calories and strength training to support overall health.";
      } else if (_bmi! >= 25) {
        bmiAdvice =
            "\n\nBMI Note: Your BMI indicates overweight. Incorporate regular exercise and a nutrient-rich diet to manage weight and reduce stress risks.";
      } else {
        bmiAdvice =
            "\n\nBMI Note: Your BMI is in the normal range — great job maintaining a healthy weight!";
      }
    }

    // Age/gender specific (general)
    String demoAdvice = '';
    if (_age != null && _gender != null) {
      if (_age! < 30 && _gender == 'Male') {
        demoAdvice =
            "\nAs a young adult male, focus on building healthy habits like regular physical activity to manage stress long-term.";
      } // Add more if needed for other demographics
    }

    return baseTips + bmiAdvice + demoAdvice;
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
                        // User Profile Card
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF3B2667), Color(0xFFBC78EC)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFBC78EC).withOpacity(0.4),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.person_outline, color: Colors.white, size: 28),
                                    ),
                                    const SizedBox(width: 16),
                                    const Text(
                                      'Patient Profile',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                _buildProfileRow('Name', _userName ?? '—'),
                                _buildProfileRow('Age', '${_age ?? '—'} yrs'),
                                _buildProfileRow('Gender', _gender ?? '—'),
                                _buildProfileRow('Height', '${_heightCm?.toStringAsFixed(0) ?? '—'} cm'),
                                _buildProfileRow('Weight', '${_weightKg?.toStringAsFixed(0) ?? '—'} kg'),
                                if (_bmi != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('BMI Index', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16)),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _bmiCategory == 'Normal'
                                                ? Colors.greenAccent.withOpacity(0.2)
                                                : Colors.orangeAccent.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: _bmiCategory == 'Normal' ? Colors.greenAccent : Colors.orangeAccent,
                                            ),
                                          ),
                                          child: Text(
                                            '${_bmi!.toStringAsFixed(1)} ($_bmiCategory)',
                                            style: TextStyle(
                                              color: _bmiCategory == 'Normal' ? Colors.greenAccent : Colors.orangeAccent,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Summary Card
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10)),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                                      child: Icon(Icons.analytics_rounded, color: Colors.blue.shade600),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('Weekly At a Glance',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E1E2C))),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(child: _buildStatCard('Avg Stress', '${(avgStress * 100).toStringAsFixed(0)}%', Icons.show_chart, Colors.purple)),
                                    const SizedBox(width: 16),
                                    Expanded(child: _buildStatCard('High Days', '$highStressDays / 7', Icons.warning_rounded, Colors.red)),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Mood Breakdown', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                                        children: [
                                          _buildMoodPill('Stressed', '${moodDistribution['Stressed']}', Colors.red.shade100, Colors.red.shade700),
                                          _buildMoodPill('Neutral', '${moodDistribution['Neutral']}', Colors.orange.shade100, Colors.orange.shade800),
                                          _buildMoodPill('Relaxed', '${moodDistribution['Relaxed']}', Colors.green.shade100, Colors.green.shade700),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Professional Stress Trend Chart
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E2C),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF1E1E2C).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10)),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                      child: const Icon(Icons.timeline_rounded, color: Colors.cyanAccent, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('Stress Trend Analysis',
                                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 32),
                                SizedBox(
                                  height: 240,
                                  child: _dailyAverages.isEmpty
                                      ? const Center(child: Text('Awaiting stress data...', style: TextStyle(color: Colors.white54)))
                                      : LineChart(
                                          LineChartData(
                                            lineTouchData: LineTouchData(
                                              enabled: true,
                                              touchTooltipData: LineTouchTooltipData(
                                                getTooltipColor: (_) => Colors.white.withOpacity(0.95),
                                                getTooltipItems: (touchedSpots) {
                                                  return touchedSpots.map((spot) {
                                                    final day = _dailyAverages[spot.x.toInt()].key;
                                                    return LineTooltipItem(
                                                      '${DateFormat('MMM dd').format(DateTime.parse(day))}\n',
                                                      const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold),
                                                      children: [
                                                        TextSpan(
                                                          text: '${(spot.y * 100).toStringAsFixed(0)}% Load',
                                                          style: const TextStyle(color: Color(0xFF1E1E2C), fontSize: 14, fontWeight: FontWeight.w900),
                                                        ),
                                                      ],
                                                    );
                                                  }).toList();
                                                },
                                              ),
                                            ),
                                            gridData: FlGridData(
                                              show: true,
                                              drawVerticalLine: false,
                                              horizontalInterval: 0.25,
                                              getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                                            ),
                                            titlesData: FlTitlesData(
                                              leftTitles: AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: true,
                                                  reservedSize: 36,
                                                  interval: 0.25,
                                                  getTitlesWidget: (value, meta) => Text(
                                                    '${(value * 100).toInt()}%',
                                                    style: const TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              ),
                                              bottomTitles: AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: true,
                                                  reservedSize: 30,
                                                  interval: 1,
                                                  getTitlesWidget: (value, meta) {
                                                    if (value.toInt() >= _dailyAverages.length) return const Text('');
                                                    final day = _dailyAverages[value.toInt()].key;
                                                    return Padding(
                                                      padding: const EdgeInsets.only(top: 8),
                                                      child: Text(
                                                        DateFormat('E').format(DateTime.parse(day)).toUpperCase(),
                                                        style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                            ),
                                            borderData: FlBorderData(show: false),
                                            minX: 0,
                                            maxX: (_dailyAverages.length - 1).toDouble(),
                                            minY: 0,
                                            maxY: 1.0,
                                            lineBarsData: [
                                              LineChartBarData(
                                                spots: _getDailyStressSpots(),
                                                isCurved: true,
                                                curveSmoothness: 0.35,
                                                color: Colors.cyanAccent,
                                                barWidth: 4,
                                                isStrokeCapRound: true,
                                                dotData: FlDotData(
                                                  show: true,
                                                  getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                                                    radius: 4,
                                                    color: Colors.white,
                                                    strokeColor: Colors.cyanAccent,
                                                    strokeWidth: 3,
                                                  ),
                                                ),
                                                belowBarData: BarAreaData(
                                                  show: true,
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [
                                                      Colors.cyanAccent.withOpacity(0.4),
                                                      Colors.transparent,
                                                    ],
                                                    stops: const [0.0, 0.9],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Mood Distribution Bar Chart
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Mood Distribution This Week',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 280,
                                  child: moodDistribution.values
                                          .every((v) => v == 0)
                                      ? const Center(
                                          child: Text('No mood data recorded',
                                              style: TextStyle(
                                                  color: Colors.grey)))
                                      : BarChart(
                                          BarChartData(
                                            alignment:
                                                BarChartAlignment.spaceEvenly,
                                            maxY: moodDistribution.values
                                                    .reduce(
                                                        (a, b) => a > b ? a : b)
                                                    .toDouble() +
                                                2, // Padding for labels
                                            barTouchData: BarTouchData(
                                              enabled: true,
                                              touchTooltipData:
                                                  BarTouchTooltipData(
                                                getTooltipColor: (group) =>
                                                    Colors.black
                                                        .withOpacity(0.8),
                                                getTooltipItem: (group,
                                                    groupIndex, rod, rodIndex) {
                                                  String label = '';
                                                  switch (group.x) {
                                                    case 0:
                                                      label = 'Stressed';
                                                      break;
                                                    case 1:
                                                      label = 'Neutral';
                                                      break;
                                                    case 2:
                                                      label = 'Relaxed';
                                                      break;
                                                  }
                                                  return BarTooltipItem(
                                                    '$label\n${rod.toY.toInt()} readings',
                                                    const TextStyle(
                                                        color: Colors.white),
                                                  );
                                                },
                                              ),
                                            ),
                                            titlesData: FlTitlesData(
                                              show: true,
                                              bottomTitles: AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: true,
                                                  reservedSize: 40,
                                                  getTitlesWidget:
                                                      (value, meta) {
                                                    switch (value.toInt()) {
                                                      case 0:
                                                        return const Text(
                                                            'Stressed',
                                                            style: TextStyle(
                                                                fontSize: 14));
                                                      case 1:
                                                        return const Text(
                                                            'Neutral',
                                                            style: TextStyle(
                                                                fontSize: 14));
                                                      case 2:
                                                        return const Text(
                                                            'Relaxed',
                                                            style: TextStyle(
                                                                fontSize: 14));
                                                      default:
                                                        return const Text('');
                                                    }
                                                  },
                                                ),
                                              ),
                                              leftTitles: AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: true,
                                                  reservedSize: 40,
                                                  interval: 1,
                                                  getTitlesWidget:
                                                      (value, meta) => Text(
                                                          value
                                                              .toInt()
                                                              .toString(),
                                                          style:
                                                              const TextStyle(
                                                                  fontSize:
                                                                      12)),
                                                ),
                                              ),
                                              topTitles: const AxisTitles(
                                                  sideTitles: SideTitles(
                                                      showTitles: false)),
                                              rightTitles: const AxisTitles(
                                                  sideTitles: SideTitles(
                                                      showTitles: false)),
                                            ),
                                            gridData: FlGridData(
                                              show: true,
                                              drawVerticalLine: false,
                                              horizontalInterval: 1,
                                              getDrawingHorizontalLine:
                                                  (value) => FlLine(
                                                color: Colors.grey
                                                    .withOpacity(0.2),
                                                strokeWidth: 1,
                                              ),
                                            ),
                                            borderData:
                                                FlBorderData(show: false),
                                            barGroups: _getMoodBarGroups(),
                                          ),
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
                                                final first = _weeklyData.first[
                                                        'currentLocation']
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
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10)),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12)),
                                      child: Icon(Icons.pie_chart_rounded, color: Colors.purple.shade600),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text('Stress Load Distribution',
                                          style: TextStyle(color: Color(0xFF1E1E2C), fontSize: 18, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 32),
                                SizedBox(
                                  height: 240,
                                  child: highStressCount + moderateStressCount + lowStressCount == 0
                                      ? const Center(child: Text('No stress level data recorded', style: TextStyle(color: Colors.grey)))
                                      : PieChart(
                                          PieChartData(
                                            pieTouchData: PieTouchData(
                                              touchCallback: (FlTouchEvent event, pieTouchResponse) {},
                                            ),
                                            borderData: FlBorderData(show: false),
                                            sectionsSpace: 4,
                                            centerSpaceRadius: 60,
                                            sections: _getStressPieSections(),
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 32),
                                _buildStressPieLegend(),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Health Recommendations
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: avgStress > 0.6
                                  ? [Colors.orange.shade50, Colors.red.shade50]
                                  : [Colors.green.shade50, Colors.teal.shade50],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: avgStress > 0.6 ? Colors.orange.shade200 : Colors.green.shade200,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(color: (avgStress > 0.6 ? Colors.orange : Colors.green).withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8)),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      avgStress > 0.6 ? Icons.warning_rounded : Icons.health_and_safety_rounded,
                                      color: avgStress > 0.6 ? Colors.deepOrange : Colors.teal.shade700,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('Health Recommendations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _getHealthTips(),
                                  style: TextStyle(height: 1.6, fontSize: 15, color: Colors.blueGrey.shade800),
                                ),
                                if (avgStress > 0.65 || highStressDays >= 4)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 20),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(color: Colors.red.shade100.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.medical_services, color: Colors.red.shade700, size: 24),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              "Frequent high stress in certain locations may indicate environmental or situational triggers. Consider speaking to a healthcare professional if symptoms persist.",
                                              style: TextStyle(color: Colors.red.shade900, fontSize: 14, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 60),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildProfileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildMoodPill(String label, String count, Color bgColor, Color textColor) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
          child: Text(
            count,
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
