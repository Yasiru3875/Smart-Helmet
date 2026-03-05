// weekly_report_page.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../services/auth_service.dart'; // ← adjust path if needed

class WeeklyReportPage extends StatefulWidget {
  const WeeklyReportPage({super.key});

  @override
  State<WeeklyReportPage> createState() => _WeeklyReportPageState();
}

class _WeeklyReportPageState extends State<WeeklyReportPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late String userId;

  List<DailySummary> _dailyData = [];
  bool _isLoading = true;
  String _error = '';

  String? _userName;
  int? _age;
  String? _gender;
  double? _heightCm;
  double? _weightKg;
  double? _bmi;
  String _bmiCategory = '';

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  String _periodLabel = "Last 7 Days";

  @override
  void initState() {
    super.initState();

    // Get real user ID from AuthService (assuming you have Provider setup)
    final auth = Provider.of<AuthService>(context, listen: false);
    userId = auth.userId!;

    if (userId.isEmpty) {
      // Fallback or show error
      Future.microtask(() {
        if (mounted) {
          setState(() {
            _error = "Not logged in — cannot load profile";
            _isLoading = false;
          });
        }
      });
      return;
    }

    _fetchUserProfile();
    _fetchReportData();
  }

  Future<void> _fetchReportData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final snapshot = await _firestore
          .collection("health_readings")
          .where("userId", isEqualTo: userId)
          .where("createdAt",
              isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
          .where("createdAt", isLessThanOrEqualTo: Timestamp.fromDate(_endDate))
          .orderBy("createdAt")
          .get();

      final rawData = snapshot.docs.map((doc) => doc.data()).toList();

      final Map<DateTime, List<Map<String, dynamic>>> grouped = {};
      for (var reading in rawData) {
        final ts = (reading['createdAt'] as Timestamp?)?.toDate() ??
            DateTime.tryParse(reading['timestamp'] ?? '');
        if (ts == null) continue;
        final day = DateTime(ts.year, ts.month, ts.day);
        grouped.putIfAbsent(day, () => []).add(reading);
      }

      final List<DailySummary> summaries = [];
      DateTime current = _startDate;
      while (!current.isAfter(_endDate)) {
        final dayKey = DateTime(current.year, current.month, current.day);
        final readings = grouped[dayKey] ?? [];

        double sumHR = 0,
            sumTemp = 0,
            minHR = double.infinity,
            maxHR = 0,
            minTemp = double.infinity,
            maxTemp = 0;
        int highRiskCount = 0;

        for (var r in readings) {
          final hr = (r['heartRate'] as num?)?.toDouble() ?? 0;
          final temp = (r['bodyTemperature'] as num?)?.toDouble() ?? 0;
          sumHR += hr;
          sumTemp += temp;
          if (hr > 0) {
            minHR = hr < minHR ? hr : minHR;
            maxHR = hr > maxHR ? hr : maxHR;
          }
          if (temp > 0) {
            minTemp = temp < minTemp ? temp : minTemp;
            maxTemp = temp > maxTemp ? temp : maxTemp;
          }
          final risk = (r['riskLevel'] as String? ?? '').toLowerCase();
          if (risk.contains('high')) highRiskCount++;
        }

        final count = readings.length;
        final avgHR = count > 0 ? sumHR / count : 0.0;
        final avgTemp = count > 0 ? sumTemp / count : 0.0;
        final highRiskPercent = count > 0 ? (highRiskCount / count) * 100 : 0.0;

        summaries.add(DailySummary(
          date: dayKey,
          avgHR: avgHR,
          avgTemp: avgTemp,
          minHR: minHR.isFinite ? minHR : 0,
          maxHR: maxHR,
          minTemp: minTemp.isFinite ? minTemp : 0,
          maxTemp: maxTemp,
          readingsCount: count,
          highRiskPercent: highRiskPercent,
        ));

        current = current.add(const Duration(days: 1));
      }

      if (mounted) {
        setState(() {
          _dailyData = summaries;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectPeriod(String type) async {
    DateTime now = DateTime.now();

    switch (type) {
      case 'weekly':
        _startDate = now.subtract(const Duration(days: 7));
        _endDate = now;
        _periodLabel = "Last 7 Days";
        break;
      case 'monthly':
        _startDate = DateTime(now.year, now.month - 1, now.day);
        _endDate = now;
        _periodLabel = "Last 30 Days";
        break;
      case 'custom':
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
        );
        if (picked != null && mounted) {
          _startDate = picked.start;
          _endDate = picked.end;
          _periodLabel =
              "${DateFormat('MMM d').format(_startDate)} – ${DateFormat('MMM d, yyyy').format(_endDate)}";
        }
        break;
    }
    await _fetchReportData();
  }

  // ==================== HEALTH STATUS & RECOMMENDATIONS ====================
  String _getHealthStatus() {
    final validDays = _dailyData.where((d) => d.readingsCount > 0).toList();
    final avgHR = validDays.isEmpty
        ? 0.0
        : validDays.fold<double>(0, (s, d) => s + d.avgHR) / validDays.length;
    final avgTemp = validDays.isEmpty
        ? 0.0
        : validDays.fold<double>(0, (s, d) => s + d.avgTemp) / validDays.length;
    final highRiskDays = _dailyData.where((d) => d.highRiskPercent > 30).length;

    if (highRiskDays > 3 || avgHR > 100 || avgHR < 50 || avgTemp > 37.8) {
      return "Poor - Immediate Medical Attention Recommended";
    } else if (highRiskDays > 1 || avgHR > 90 || avgTemp > 37.2) {
      return "Fair - Monitor Closely & Consult Doctor";
    } else {
      return "Good - Excellent Progress!";
    }
  }

  Color _getHealthStatusColor() {
    final status = _getHealthStatus();
    if (status.contains("Poor")) return Colors.red;
    if (status.contains("Fair")) return Colors.orange;
    return Colors.green;
  }

  List<String> _getRecommendations() {
    final validDays = _dailyData.where((d) => d.readingsCount > 0).toList();
    final avgHR = validDays.isEmpty
        ? 0.0
        : validDays.fold<double>(0, (s, d) => s + d.avgHR) / validDays.length;
    final avgTemp = validDays.isEmpty
        ? 0.0
        : validDays.fold<double>(0, (s, d) => s + d.avgTemp) / validDays.length;
    final highRiskDays = _dailyData.where((d) => d.highRiskPercent > 30).length;

    final List<String> recs = [
      "Stay hydrated - drink 2.5-3 L of water daily",
      "Engage in 30 minutes of moderate exercise",
      "Maintain 7-9 hours of quality sleep",
      "Eat a balanced diet rich in fruits and vegetables",
      "Practice stress management (meditation/yoga)",
    ];

    if (avgHR > 90) recs.add("Reduce caffeine and screen time before bed");
    if (avgTemp > 37.2) recs.add("Monitor temperature twice daily and rest");
    if (highRiskDays > 1) recs.add("Schedule a doctor visit within 48 hours");
    if (avgHR < 55) recs.add("Ensure adequate nutrition and rest");

    return recs;
  }

  Future<void> _fetchUserProfile() async {
    try {
      print("Fetching profile for userId: $userId"); // ← Debug 1

      final userDoc = await _firestore.collection('users').doc(userId).get();

      print("Document exists? ${userDoc.exists}"); // ← Debug 2

      if (userDoc.exists && mounted) {
        final data = userDoc.data()!;

        print("Raw profile data: $data"); // ← Debug 3 — see actual fields

        setState(() {
          _userName =
              data['userName'] as String? ?? data['username'] as String?;
          _age = data['age'] as int?;
          _gender = data['gender'] as String?;
          _heightCm = (data['heightCm'] as num?)?.toDouble();
          _weightKg = (data['weightKg'] as num?)?.toDouble();

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
          } else {
            _bmi = null;
            _bmiCategory = '';
          }

          print(
              "Profile loaded → Name: $_userName, Age: $_age, BMI: $_bmi ($_bmiCategory)");
        });
      } else {
        print("No profile document found for $userId");
        if (mounted) {
          setState(() {
            _userName = null;
            _age = null;
            // etc. — already null by default
          });
        }
      }
    } catch (e, stack) {
      print("Profile fetch error: $e");
      print("Stack trace: $stack");
      // Optional UI feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not load profile: $e")),
        );
      }
    }
  }

  Future<Uint8List> _generatePdfBytes() async {
    final pdf = pw.Document();

    final status = _getHealthStatus();
    final recs = _getRecommendations();

    final overallAvgHR = _getOverallAvgHR();
    final overallAvgTemp = _getOverallAvgTemp();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) => [
          // ──────────────── HEADER ────────────────
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 20),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 2),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Smart Helmet',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.Text(
                      'Health Summary Report',
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Date Created',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey600,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      DateFormat('MMM dd, yyyy').format(DateTime.now()),
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Period',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey600,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      _periodLabel,
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 30),

          // ──────────────── NEW: USER PROFILE SECTION ────────────────
          pw.Text(
            'Patient Profile',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey800,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
            columnWidths: {
              0: pw.FixedColumnWidth(120),
              1: pw.FlexColumnWidth(),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(12),
                    child: pw.Text(
                      'Name',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(12),
                    child: pw.Text(_userName ?? '—'),
                  ),
                ],
              ),
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Text('Age',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Text(_age != null ? '$_age years' : '—'),
                ),
              ]),
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Text('Gender',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Text(_gender ?? '—'),
                ),
              ]),
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Text('Height',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Text(
                    _heightCm != null
                        ? '${_heightCm!.toStringAsFixed(0)} cm'
                        : '—',
                  ),
                ),
              ]),
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Text('Weight',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Text(
                    _weightKg != null
                        ? '${_weightKg!.toStringAsFixed(0)} kg'
                        : '—',
                  ),
                ),
              ]),
              if (_bmi != null)
                pw.TableRow(children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(12),
                    child: pw.Text('BMI',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(12),
                    child:
                        pw.Text('${_bmi!.toStringAsFixed(1)} ($_bmiCategory)'),
                  ),
                ]),
            ],
          ),

          pw.SizedBox(height: 30),

          // ──────────────── OVERALL AVERAGES ────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  children: [
                    pw.Text('Average Heart Rate',
                        style: pw.TextStyle(
                            color: PdfColors.grey700, fontSize: 12)),
                    pw.SizedBox(height: 8),
                    pw.Text('${overallAvgHR.toStringAsFixed(0)} BPM',
                        style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.red600)),
                  ],
                ),
                pw.Container(width: 1, height: 40, color: PdfColors.grey300),
                pw.Column(
                  children: [
                    pw.Text('Average Temperature',
                        style: pw.TextStyle(
                            color: PdfColors.grey700, fontSize: 12)),
                    pw.SizedBox(height: 8),
                    pw.Text('${overallAvgTemp.toStringAsFixed(1)} °C',
                        style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue600)),
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 30),

          // ──────────────── HEALTH STATUS ────────────────
          pw.Text(
            'Health Assessment',
            style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey800),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Text(status,
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ),

          pw.SizedBox(height: 30),

          // ──────────────── RECOMMENDATIONS ────────────────
          pw.Text(
            'Recommendations',
            style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey800),
          ),
          pw.SizedBox(height: 12),
          ...recs.map((rec) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      margin: const pw.EdgeInsets.only(top: 4, right: 8),
                      width: 6,
                      height: 6,
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.green500,
                        shape: pw.BoxShape.circle,
                      ),
                    ),
                    pw.Expanded(
                      child:
                          pw.Text(rec, style: const pw.TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              )),

          pw.SizedBox(height: 30),

          // ──────────────── DAILY SUMMARY TABLE ────────────────
          pw.Text(
            'Daily Readings Summary',
            style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey800),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey600),
            cellAlignment: pw.Alignment.center,
            cellStyle: const pw.TextStyle(fontSize: 10),
            rowDecoration: const pw.BoxDecoration(
              border:
                  pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200)),
            ),
            headers: [
              'Date',
              'Avg HR',
              'Min HR',
              'Max HR',
              'Avg Temp',
              'Readings'
            ],
            data: _dailyData
                .map((d) => [
                      DateFormat('MMM dd').format(d.date),
                      d.avgHR.toStringAsFixed(0),
                      d.minHR.toStringAsFixed(0),
                      d.maxHR.toStringAsFixed(0),
                      d.avgTemp.toStringAsFixed(1),
                      d.readingsCount.toString(),
                    ])
                .toList(),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir;
    }
    return await getApplicationDocumentsDirectory();
  }

  Future<void> _downloadReport() async {
    try {
      final bytes = await _generatePdfBytes();
      final dir = await _getDownloadDirectory();
      final fileName =
          'health_report_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
      final file = File("${dir.path}/$fileName");
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report saved to ${file.path}'),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving PDF: $e')),
        );
      }
    }
  }

  Future<void> _sharePdf() async {
    try {
      final bytes = await _generatePdfBytes();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'health_report_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing PDF: $e')),
        );
      }
    }
  }

  double _getOverallAvgHR() {
    final valid = _dailyData.where((d) => d.avgHR > 0);
    return valid.isEmpty
        ? 0
        : valid.fold<double>(0, (s, d) => s + d.avgHR) / valid.length;
  }

  double _getOverallAvgTemp() {
    final valid = _dailyData.where((d) => d.avgTemp > 0);
    return valid.isEmpty
        ? 0
        : valid.fold<double>(0, (s, d) => s + d.avgTemp) / valid.length;
  }

  Color _getRiskBackgroundColor() {
    final status = _getHealthStatus();
    if (status.contains("Poor")) return Colors.red.shade50;
    if (status.contains("Fair")) return Colors.orange.shade50;
    return Colors.green.shade50;
  }

  @override
  Widget build(BuildContext context) {
    final validDays = _dailyData.where((d) => d.readingsCount > 0).toList();
    final avgHR = validDays.isEmpty
        ? 0.0
        : validDays.fold<double>(0, (s, d) => s + d.avgHR) / validDays.length;
    final avgTemp = validDays.isEmpty
        ? 0.0
        : validDays.fold<double>(0, (s, d) => s + d.avgTemp) / validDays.length;
    final highRiskDays = _dailyData.where((d) => d.highRiskPercent > 30).length;

    final healthStatus = _getHealthStatus();
    final statusColor = _getHealthStatusColor();

    return Scaffold(
      backgroundColor: _getRiskBackgroundColor(),
      appBar: AppBar(
        title: const Text(
          "Health Summary Report",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: "Download to Storage",
            onPressed: _downloadReport,
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: "Share PDF Report",
            onPressed: _sharePdf,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_periodLabel,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip("Weekly", () => _selectPeriod('weekly')),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                          "Monthly", () => _selectPeriod('monthly')),
                      const SizedBox(width: 8),
                      _buildFilterChip("Custom", () => _selectPeriod('custom')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ← NEW: Profile summary appears here (clean & professional)
                _buildProfileSummary(),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(
                        child: Text("Error: $_error",
                            style: const TextStyle(color: Colors.red)))
                    : _dailyData.isEmpty
                        ? const Center(
                            child: Text("No data for selected period"))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // HEALTH STATUS CARD (Professional Highlight)
                                _buildHealthStatusCard(
                                    healthStatus, statusColor),

                                const SizedBox(height: 24),

                                // Summary Cards
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildSummaryCard(
                                        "Avg HR",
                                        "${avgHR.toStringAsFixed(0)} BPM",
                                        Icons.favorite_rounded,
                                        Colors.red,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildSummaryCard(
                                        "Avg Temp",
                                        "${avgTemp.toStringAsFixed(1)}°C",
                                        Icons.thermostat_rounded,
                                        Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildSummaryCard(
                                        "High Risk Days",
                                        "$highRiskDays/${_dailyData.length}",
                                        Icons.warning_rounded,
                                        Colors.orange,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildSummaryCard(
                                        "Total Readings",
                                        _dailyData
                                            .fold<int>(0,
                                                (s, d) => s + d.readingsCount)
                                            .toString(),
                                        Icons.analytics_rounded,
                                        Colors.indigo,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 32),

                                // Trend Charts
                                _buildTrendCard("Heart Rate Trend", true),
                                const SizedBox(height: 24),
                                _buildTrendCard("Temperature Trend", false),
                                const SizedBox(height: 32),

                                // General Tips
                                _buildTipsSection(),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSummary() {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_rounded,
                  color: Colors.indigo.shade700,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  "User Profile",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.indigo.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildProfileRow("Name", _userName ?? "—"),
            _buildProfileRow("Age", _age != null ? "$_age years" : "—"),
            _buildProfileRow("Gender", _gender ?? "—"),
            _buildProfileRow(
              "Height",
              _heightCm != null ? "${_heightCm!.toStringAsFixed(0)} cm" : "—",
            ),
            _buildProfileRow(
              "Weight",
              _weightKg != null ? "${_weightKg!.toStringAsFixed(0)} kg" : "—",
            ),
            if (_bmi != null)
              _buildProfileRow(
                "BMI",
                "${_bmi!.toStringAsFixed(1)} ($_bmiCategory)",
                valueColor: _bmiCategory == 'Normal'
                    ? Colors.green.shade700
                    : _bmiCategory == 'Underweight' ||
                            _bmiCategory == 'Overweight'
                        ? Colors.orange.shade700
                        : Colors.red.shade700,
                isBold: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileRow(String label, String value,
      {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w500,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthStatusCard(String status, Color statusColor) {
    final recs = _getRecommendations();

    return Card(
      elevation: 6,
      shadowColor: statusColor.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [statusColor.withOpacity(0.05), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border.all(color: statusColor.withOpacity(0.2), width: 1.5),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.health_and_safety_rounded,
                      color: statusColor, size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Overall Health Status",
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status.split(" - ").first,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (status.contains(" - "))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  status.split(" - ").last,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                Icon(Icons.lightbulb_circle,
                    color: Colors.amber.shade600, size: 24),
                const SizedBox(width: 8),
                const Text(
                  "Personalized Recommendations",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...recs.map((rec) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            size: 12, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          rec,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade800,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onTap) {
    final bool active = (label == "Weekly" && _periodLabel.contains("7")) ||
        (label == "Monthly" && _periodLabel.contains("30")) ||
        (label == "Custom" && !_periodLabel.contains("Days"));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(
          label,
          style: TextStyle(
            fontWeight: active ? FontWeight.bold : FontWeight.w600,
            color: active ? Colors.indigo.shade800 : Colors.grey.shade700,
          ),
        ),
        backgroundColor: active ? Colors.indigo.shade100 : Colors.grey.shade100,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: active ? Colors.indigo.shade300 : Colors.transparent,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onPressed: onTap,
        elevation: active ? 2 : 0,
      ),
    );
  }

  Widget _buildSummaryCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(fontSize: 13.5, color: Colors.grey)),
            Text(
              value,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendCard(String title, bool isHR) {
    final spots = _dailyData
        .asMap()
        .entries
        .where((e) => (isHR ? e.value.avgHR : e.value.avgTemp) > 0)
        .map((e) {
      return FlSpot(e.key.toDouble(), isHR ? e.value.avgHR : e.value.avgTemp);
    }).toList();

    if (spots.isEmpty) return const SizedBox();

    final color = isHR ? Colors.red : Colors.blue;
    final trend = _getTrendArrow(isHR);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                Text(
                  trend,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: trend.contains('↑')
                        ? Colors.red
                        : trend.contains('↓')
                            ? Colors.green
                            : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= _dailyData.length)
                            return const Text('');
                          return Text(
                            DateFormat('d').format(_dailyData[i].date),
                            style: const TextStyle(fontSize: 11),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: true, reservedSize: 40)),
                  ),
                  minX: 0,
                  maxX: (_dailyData.length - 1).toDouble(),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: color,
                      barWidth: 4,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: Colors.white,
                            strokeWidth: 0,
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
      ),
    );
  }

  String _getTrendArrow(bool isHR) {
    if (_dailyData.length < 2) return "→";
    final last = isHR ? _dailyData.last.avgHR : _dailyData.last.avgTemp;
    final prev = isHR
        ? _dailyData[_dailyData.length - 2].avgHR
        : _dailyData[_dailyData.length - 2].avgTemp;
    if (last > prev + 2) return "↑";
    if (last < prev - 2) return "↓";
    return "→";
  }

  Widget _buildTipsSection() {
    const tips = [
      "Stay consistent with daily readings",
      "Track trends over time for better insights",
      "Consult your doctor for personalized advice",
    ];

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Pro Tips",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...tips.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_rounded,
                          size: 20, color: Colors.amber),
                      const SizedBox(width: 12),
                      Expanded(
                          child:
                              Text(t, style: const TextStyle(fontSize: 14.5))),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class DailySummary {
  final DateTime date;
  final double avgHR, avgTemp, minHR, maxHR, minTemp, maxTemp;
  final int readingsCount;
  final double highRiskPercent;

  DailySummary({
    required this.date,
    required this.avgHR,
    required this.avgTemp,
    required this.minHR,
    required this.maxHR,
    required this.minTemp,
    required this.maxTemp,
    required this.readingsCount,
    required this.highRiskPercent,
  });
}
