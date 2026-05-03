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
import '../../../../services/emotion_aggregator_service.dart'; // 🆕 emotion analytics
import 'package:firebase_auth/firebase_auth.dart';

class WeeklyReportPage extends StatefulWidget {
  final bool isEmbedded;
  const WeeklyReportPage({super.key, this.isEmbedded = false});

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
  String _selectedPeriodType = 'weekly'; // Track selected type
  int _totalRides = 0; // Track unique rides

  // 🆕 Emotion analytics data
  final EmotionAggregatorService _emotionAggregator = EmotionAggregatorService();
  List<Map<String, dynamic>> _emotionDailyData = [];
  bool _emotionDataLoading = true;

  @override
  void initState() {
    super.initState();

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final rawId = auth.userId;
      
      if (rawId == null || rawId.isEmpty) {
        _error = "Authentication required. Please log in.";
        _isLoading = false;
        return;
      }
      
      userId = rawId;
      debugPrint("DEBUG: WeeklyReportPage initialized for userId: $userId");
      _fetchUserProfile();
      _fetchReportData();
      _fetchEmotionData();
    } catch (e) {
      debugPrint("DEBUG: Error in initState: $e");
      _isLoading = false;
    }
  }

  Future<void> _fetchReportData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      if (userId.isEmpty) {
        throw "User ID is missing. Please log in again.";
      }

      debugPrint("DEBUG: Fetching all health_readings for $userId (Memory Filtering)");

      // Fetch all readings for this user (Simplified query to avoid composite index requirements)
      final snapshot = await _firestore
          .collection("health_readings")
          .where("userId", isEqualTo: userId)
          .get();

      debugPrint("DEBUG: Found ${snapshot.docs.length} total docs for user.");

      final rawData = snapshot.docs.map((doc) => doc.data()).toList();
      
      // Normalize _startDate and _endDate for day-level comparison
      final startDay = DateTime(_startDate.year, _startDate.month, _startDate.day);
      final endDay = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

      // Filter by date range in memory
      final filteredData = rawData.where((reading) {
        DateTime? ts;
        if (reading['createdAt'] != null) {
          final dynamic createdAt = reading['createdAt'];
          if (createdAt is Timestamp) {
            ts = createdAt.toDate();
          } else if (createdAt is String) {
            ts = DateTime.tryParse(createdAt);
          }
        } else if (reading['timestamp'] != null) {
          ts = DateTime.tryParse(reading['timestamp'].toString());
        }
        
        if (ts == null) return false;
        
        // Use normalized dates for comparison to be inclusive of the full days
        return !ts.isBefore(startDay) && !ts.isAfter(endDay);
      }).toList();

      debugPrint("DEBUG: ${filteredData.length} readings satisfy the range: $startDay to $endDay");

      final Map<DateTime, List<Map<String, dynamic>>> grouped = {};
      for (var reading in filteredData) {
        DateTime? ts;
        if (reading['createdAt'] != null) {
          ts = (reading['createdAt'] as Timestamp).toDate();
        } else if (reading['timestamp'] != null) {
          ts = DateTime.tryParse(reading['timestamp'].toString());
        }
        if (ts == null) continue;
        final day = DateTime(ts.year, ts.month, ts.day);
        grouped.putIfAbsent(day, () => []).add(reading);
      }

      final List<DailySummary> summaries = [];
      DateTime current = DateTime(_startDate.year, _startDate.month, _startDate.day);
      DateTime end = DateTime(_endDate.year, _endDate.month, _endDate.day);

      while (!current.isAfter(end)) {
        final dayKey = current;
        final readings = grouped[dayKey] ?? [];

        double sumHR = 0, sumTemp = 0;
        double minHR = double.infinity, maxHR = 0;
        double minTemp = double.infinity, maxTemp = 0;
        int highRiskCount = 0;

        int hrCount = 0, tempCount = 0;

        for (var r in readings) {
          final hr = (r['heartRate'] as num?)?.toDouble() ?? 0;
          final temp = (r['bodyTemperature'] as num?)?.toDouble() ?? 0;
          
          if (hr > 0) {
            sumHR += hr;
            hrCount++;
            minHR = hr < minHR ? hr : minHR;
            maxHR = hr > maxHR ? hr : maxHR;
          }
          if (temp > 0) {
            sumTemp += temp;
            tempCount++;
            minTemp = temp < minTemp ? temp : minTemp;
            maxTemp = temp > maxTemp ? temp : maxTemp;
          }
          final risk = (r['riskLevel'] as String? ?? '').toLowerCase();
          if (risk.contains('high')) highRiskCount++;
        }

        final count = readings.length;
        final summary = DailySummary(
          date: dayKey,
          avgHR: hrCount > 0 ? sumHR / hrCount : 0.0,
          avgTemp: tempCount > 0 ? sumTemp / tempCount : 0.0,
          minHR: minHR.isFinite ? minHR : 0,
          maxHR: maxHR,
          minTemp: minTemp.isFinite ? minTemp : 0,
          maxTemp: maxTemp,
          readingsCount: count,
          highRiskPercent: count > 0 ? (highRiskCount / count) * 100 : 0.0,
        );
        summaries.add(summary);
        if (summary.readingsCount > 0) {
          debugPrint("DEBUG: Day ${DateFormat('MM-dd').format(dayKey)} has ${summary.readingsCount} readings. AvgHR: ${summary.avgHR}");
        }

        current = current.add(const Duration(days: 1));
      }

      // Calculate total unique rides in this period
      final Set<String> uniqueRideIds = {};
      for (var r in filteredData) {
        if (r['rideId'] != null) {
          uniqueRideIds.add(r['rideId'].toString());
        }
      }

      if (mounted) {
        setState(() {
          _dailyData = summaries;
          _totalRides = uniqueRideIds.length;
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint("FATAL ERROR in _fetchReportData: $e");
      debugPrint("Stack: $stack");
      if (mounted) {
        setState(() {
          _error = "Failed to load report: $e";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectPeriod(String type) async {
    DateTime now = DateTime.now();

    setState(() => _selectedPeriodType = type);

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
        } else {
          // If cancelled, don't change type back or fetch
          return;
        }
        break;
    }
    await _fetchReportData();
    await _fetchEmotionData();
  }

  // 🆕 Emotion Data Fetching
  Future<void> _fetchEmotionData() async {
    if (!mounted) return;
    
    setState(() => _emotionDataLoading = true);
    
    try {
      if (userId.isEmpty) {
        throw "User ID is missing for emotion data.";
      }

      debugPrint("DEBUG: Fetching emotion data for $userId");
      
      // First aggregate the emotion data
      await _emotionAggregator.aggregateWeek(userId: userId);
      
      // Then fetch the last 7 days of emotion summaries
      final data = await _emotionAggregator.getLast7Days(userId);
      
      setState(() {
        _emotionDailyData = data;
        _emotionDataLoading = false;
      });
      
      debugPrint("DEBUG: Loaded ${data.length} days of emotion data");
    } catch (e) {
      debugPrint("❌ Error fetching emotion data: $e");
      setState(() => _emotionDataLoading = false);
    }
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
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Vital Health Monitoring Report',
                          style: pw.TextStyle(
                              fontSize: 24,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue900)),
                      pw.Text(
                          'Period: ${DateFormat('MMM dd, yyyy').format(_startDate)} - ${DateFormat('MMM dd, yyyy').format(_endDate)}',
                          style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey800)),
                    ],
                  ),
                  pw.Text(DateFormat('MMM dd, yyyy').format(DateTime.now()),
                      style:
                          const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // COMPACT PROFILE TABLE
            pw.Text('User Profile',
                style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey700)),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.blue100, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                  children: [
                    _buildPdfCell('Name', _userName ?? '—', isHeader: true),
                    _buildPdfCell('Age', _age != null ? '$_age yrs' : '—', isHeader: true),
                    _buildPdfCell('Gender', _gender ?? '—', isHeader: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _buildPdfCell('Height', _heightCm != null ? '${_heightCm!.toInt()} cm' : '—'),
                    _buildPdfCell('Weight', _weightKg != null ? '${_weightKg!.toInt()} kg' : '—'),
                    _buildPdfCell('BMI', _bmi != null ? '${_bmi!.toStringAsFixed(1)} ($_bmiCategory)' : '—'),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // ──────────────── OVERALL AVERAGES ────────────────
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildPdfStat('Avg Heart Rate', '${overallAvgHR.toInt()} BPM', PdfColors.red600),
                  pw.Container(width: 0.5, height: 30, color: PdfColors.blue200),
                  _buildPdfStat('Avg Temperature', '${overallAvgTemp.toStringAsFixed(1)} °C', PdfColors.blue600),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // ──────────────── HEALTH STATUS ────────────────
            pw.Text('Clinical Assessment',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blue100),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                color: PdfColors.grey50,
              ),
              child: pw.Text(status, style: const pw.TextStyle(fontSize: 11)),
            ),
            pw.SizedBox(height: 24),

            // ──────────────── RECOMMENDATIONS ────────────────
            pw.Text('Medical Recommendations',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            ...recs.map((rec) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        margin: const pw.EdgeInsets.only(top: 3, right: 8),
                        width: 4,
                        height: 4,
                        decoration: const pw.BoxDecoration(color: PdfColors.blue700, shape: pw.BoxShape.circle),
                      ),
                      pw.Expanded(child: pw.Text(rec, style: const pw.TextStyle(fontSize: 10))),
                    ],
                  ),
                )),
            pw.SizedBox(height: 24),

            // ──────────────── DAILY SUMMARY ────────────────
            pw.Text('Daily Activity Log',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellAlignment: pw.Alignment.center,
              cellStyle: const pw.TextStyle(fontSize: 9),
              headers: ['Date', 'Avg HR', 'Min/Max HR', 'Avg Temp', 'Readings'],
              data: _dailyData
                  .where((d) => d.readingsCount > 0)
                  .map((d) => [
                        DateFormat('MMM dd').format(d.date),
                        '${d.avgHR.toInt()} bpm',
                        '${d.minHR.toInt()} - ${d.maxHR.toInt()}',
                        '${d.avgTemp.toStringAsFixed(1)} °C',
                        '${d.readingsCount}',
                      ])
                  .toList(),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }


  Future<void> _showExportOptionsDialog(VoidCallback onConfirm) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Export Options", 
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Select the date range for your report:", 
              style: TextStyle(fontSize: 14, color: Colors.black54)),
            const SizedBox(height: 16),
            _buildDialogMenuOption(
              icon: Icons.calendar_view_week_rounded,
              title: "Last 7 Days (Weekly)",
              isSelected: _selectedPeriodType == 'weekly',
              onTap: () async {
                Navigator.pop(context);
                await _selectPeriod('weekly');
                onConfirm();
              },
            ),
            const SizedBox(height: 8),
            _buildDialogMenuOption(
              icon: Icons.calendar_month_rounded,
              title: "Last 30 Days (Monthly)",
              isSelected: _selectedPeriodType == 'monthly',
              onTap: () async {
                Navigator.pop(context);
                await _selectPeriod('monthly');
                onConfirm();
              },
            ),
            const SizedBox(height: 8),
            _buildDialogMenuOption(
              icon: Icons.date_range_rounded,
              title: "Custom Range...",
              isSelected: _selectedPeriodType == 'custom',
              onTap: () async {
                Navigator.pop(context);
                await _selectPeriod('custom');
                onConfirm();
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            _buildDialogMenuOption(
              icon: Icons.check_circle_outline_rounded,
              title: "Use Current View ($_periodLabel)",
              isSelected: false,
              highlight: true,
              onTap: () {
                Navigator.pop(context);
                onConfirm();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogMenuOption({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2D62ED).withOpacity(0.1) : 
                 highlight ? Colors.green.withOpacity(0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF2D62ED) : 
                   highlight ? Colors.green.withOpacity(0.3) : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? const Color(0xFF2D62ED) : 
                                       highlight ? Colors.green : Colors.black54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, 
                style: TextStyle(
                  fontSize: 14, 
                  fontWeight: isSelected || highlight ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? const Color(0xFF2D62ED) : 
                         highlight ? Colors.green.shade700 : Colors.black87,
                )),
            ),
            if (isSelected) const Icon(Icons.check_rounded, size: 16, color: Color(0xFF2D62ED)),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadReport() async {
    _showExportOptionsDialog(() async {
      try {
        final bytes = await _generatePdfBytes();
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => bytes,
          name: 'health_report_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error generating PDF: $e')),
          );
        }
      }
    });
  }

  Future<void> _sharePdf() async {
    _showExportOptionsDialog(() async {
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
    });
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

  // 🆕 Emotional Analytics Section Widget
  Widget _buildEmotionalAnalyticsSection() {
    if (_emotionDataLoading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology_rounded, color: Colors.purple, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "Emotional Analytics",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "ANALYTICS",
                    style: TextStyle(
                      color: Colors.purple,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Center(
              child: CircularProgressIndicator(color: Colors.purple),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                "Analyzing emotional patterns...",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Calculate emotion analytics
    final daysWithData = _emotionDailyData.where((d) => d['readingCount'] > 0).length;
    if (daysWithData == 0) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology_rounded, color: Colors.purple, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "Emotional Analytics",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Center(
              child: Column(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 48),
                  SizedBox(height: 8),
                  Text(
                    "No emotional data available for this period",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Calculate averages and insights
    final avgStress = _emotionDailyData
        .where((d) => d['avgStressScore'] != null)
        .map((d) => d['avgStressScore'] as double)
        .isEmpty
        ? 0.0
        : _emotionDailyData
                .where((d) => d['avgStressScore'] != null)
                .map((d) => d['avgStressScore'] as double)
                .reduce((a, b) => a + b) /
            daysWithData;

    final avgRelaxed = _emotionDailyData
        .where((d) => d['avgRelaxedScore'] != null)
        .map((d) => d['avgRelaxedScore'] as double)
        .isEmpty
        ? 0.0
        : _emotionDailyData
                .where((d) => d['avgRelaxedScore'] != null)
                .map((d) => d['avgRelaxedScore'] as double)
                .reduce((a, b) => a + b) /
            daysWithData;

    final avgAttention = _emotionDailyData
        .where((d) => d['avgAttention'] != null)
        .map((d) => d['avgAttention'] as int)
        .isEmpty
        ? 0
        : _emotionDailyData
                .where((d) => d['avgAttention'] != null)
                .map((d) => d['avgAttention'] as int)
                .reduce((a, b) => a + b) ~/
            daysWithData;

    final avgMeditation = _emotionDailyData
        .where((d) => d['avgMeditation'] != null)
        .map((d) => d['avgMeditation'] as int)
        .isEmpty
        ? 0
        : _emotionDailyData
                .where((d) => d['avgMeditation'] != null)
                .map((d) => d['avgMeditation'] as int)
                .reduce((a, b) => a + b) ~/
            daysWithData;

    // Mood distribution
    final Map<String, int> moodDist = {};
    for (final data in _emotionDailyData) {
      final distribution = data['moodDistribution'] as Map<String, dynamic>? ?? {};
      distribution.forEach((mood, count) {
        moodDist[mood] = (moodDist[mood] ?? 0) + (count as int);
      });
    }

    final dominantMood = moodDist.entries.isEmpty
        ? 'Neutral'
        : moodDist.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    // Emotional stability score (0-100)
    final emotionalStability = ((1 - avgStress) * 100).clamp(0.0, 100.0).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.psychology_rounded, color: Colors.purple, size: 20),
              const SizedBox(width: 8),
              const Text(
                "Emotional Analytics",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1C1C1E),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${daysWithData}/7 days",
                  style: const TextStyle(
                    color: Colors.purple,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Summary Stats Grid
          Row(
            children: [
              Expanded(
                child: _buildEmotionStatCard(
                  "Avg Stress",
                  "${(avgStress * 100).round()}%",
                  avgStress < 0.3 ? Colors.green : avgStress < 0.6 ? Colors.orange : Colors.red,
                  Icons.sentiment_dissatisfied_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEmotionStatCard(
                  "Avg Relaxed",
                  "${(avgRelaxed * 100).round()}%",
                  avgRelaxed > 0.7 ? Colors.green : avgRelaxed > 0.4 ? Colors.orange : Colors.red,
                  Icons.sentiment_satisfied_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildEmotionStatCard(
                  "Avg Focus",
                  "$avgAttention%",
                  avgAttention > 70 ? Colors.green : avgAttention > 40 ? Colors.orange : Colors.red,
                  Icons.psychology_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEmotionStatCard(
                  "Stability",
                  "$emotionalStability%",
                  emotionalStability > 70 ? Colors.green : emotionalStability > 40 ? Colors.orange : Colors.red,
                  Icons.balance_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 7-Day Stress Trend Chart
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "7-Day Stress Trend",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  child: _emotionDailyData.isEmpty
                      ? const Center(
                          child: Text("No data", style: TextStyle(color: Colors.grey)),
                        )
                      : LineChart(
                          LineChartData(
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: 0.2,
                              getDrawingHorizontalLine: (value) => FlLine(
                                color: Colors.grey.shade300,
                                strokeWidth: 1,
                              ),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: 0.2,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      "${(value * 100).round()}%",
                                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    );
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    if (value.toInt() < 0 || value.toInt() >= _emotionDailyData.length) {
                                      return const Text('');
                                    }
                                    final dateStr = _emotionDailyData[value.toInt()]['date'] as String;
                                    final date = DateTime.parse(dateStr);
                                    return Text(
                                      DateFormat('d').format(date),
                                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    );
                                  },
                                ),
                              ),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: _emotionDailyData.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final data = entry.value;
                                  final stress = data['avgStressScore'] as double?;
                                  return FlSpot(i.toDouble(), stress ?? 0.0);
                                }).toList(),
                                isCurved: true,
                                color: Colors.purple,
                                barWidth: 3,
                                isStrokeCapRound: true,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (spot, percent, barData, index) {
                                    return FlDotCirclePainter(
                                      radius: 4,
                                      color: Colors.purple,
                                      strokeWidth: 2,
                                      strokeColor: Colors.white,
                                    );
                                  },
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: Colors.purple.withOpacity(0.1),
                                ),
                              ),
                            ],
                            minX: 0,
                            maxX: (_emotionDailyData.length - 1).toDouble(),
                            minY: 0,
                            maxY: 1,
                          ),
                        ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Mood Distribution
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Mood Distribution",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 12),
                ...moodDist.entries.map((entry) {
                  final mood = entry.key;
                  final count = entry.value;
                  final percentage = daysWithData > 0 ? (count / daysWithData / 10) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(
                            mood,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: percentage.clamp(0.0, 1.0),
                            backgroundColor: Colors.grey.shade300,
                            color: _getMoodColor(mood),
                            borderRadius: BorderRadius.circular(4),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "${percentage.clamp(0.0, 1.0 * 100).round()}%",
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Insights
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade50, Colors.purple.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Weekly Insights",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "• Your dominant mood this week was $dominantMood\n"
                  "• Emotional stability: $emotionalStability%\n"
                  "• Average focus level: $avgAttention%\n"
                  "• Stress management: ${avgStress < 0.4 ? 'Good' : avgStress < 0.7 ? 'Moderate' : 'Needs attention'}",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmotionStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getMoodColor(String mood) {
    switch (mood.toLowerCase()) {
      case 'very relaxed':
      case 'relaxed':
        return Colors.green;
      case 'neutral':
        return Colors.blue;
      case 'elevated':
        return Colors.orange;
      case 'high stress':
      case 'very high stress':
        return Colors.red;
      default:
        return Colors.grey;
    }
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
      backgroundColor: const Color(0xFFF8FAFC), // Soft clinic background
      appBar: AppBar(
        title: const Text(
          "Health Intelligence Report",
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1C1C1E)),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_for_offline_rounded, color: Color(0xFF2D62ED)),
            tooltip: "Download PDF",
            onPressed: _downloadReport,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded, color: Color(0xFF2D62ED)),
            tooltip: "Share Report",
            onPressed: _sharePdf,
          ),
        ],
      ),
      body: Column(
        children: [
          // COMPACT FILTER BAR
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 4), // Extremely compact vertical padding
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildFilterChip("Last 7 Days", 'weekly', () => _selectPeriod('weekly')),
                  _buildFilterChip("Last 30 Days", 'monthly', () => _selectPeriod('monthly')),
                  _buildFilterChip("Custom Range", 'custom', () => _selectPeriod('custom')),
                ],
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text("Error: $_error",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () {
                                _fetchUserProfile();
                                _fetchReportData();
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text("RETRY LOADING"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2D62ED),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _dailyData.isEmpty
                        ? const Center(
                            child: Text("No data for selected period"))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // PREMIUM HEALTH STATUS DASHBOARD (Separate Card)
                                _buildOverallHealthStatusCard(avgHR, avgTemp, highRiskDays),

                                const SizedBox(height: 24),

                                // PREMIUM PERSONALIZED RECOMMENDATIONS (Separate Card)
                                _buildPersonalizedRecommendations(avgHR, avgTemp, highRiskDays),

                                const SizedBox(height: 24),

                                // Summary Cards Grid
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
                                        "Total Rides",
                                        _totalRides.toString(),
                                        Icons.motorcycle_rounded,
                                        Colors.indigo,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 32),

                                // Trend Charts
                                _buildTrendCard("Heart Rate Trend", true),
                                _buildTrendCard("Temperature Trend", false),
                                const SizedBox(height: 24),

                                // 🆕 EMOTIONAL ANALYTICS SECTION
                                _buildEmotionalAnalyticsSection(),

                                const SizedBox(height: 24),

                                // HISTORY SECTION
                                _buildHistorySection(),

                                const SizedBox(height: 24),

                                // ARCHIVED: General Tips (Replaced by Recommendations)
                                // _buildTipsSection(),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSummary() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.indigo.withOpacity(0.1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.badge_rounded, color: Colors.indigo.shade700, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                "USER PROFILE",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.indigo,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  _userName ?? "Anonymous User",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            childAspectRatio: 2.2,
            children: [
              _buildCompactProfileCell("Age", _age != null ? "$_age yrs" : "—"),
              _buildCompactProfileCell("Gender", _gender ?? "—"),
              _buildCompactProfileCell("Height", _heightCm != null ? "${_heightCm!.toInt()}cm" : "—"),
              _buildCompactProfileCell("Weight", _weightKg != null ? "${_weightKg!.toInt()}kg" : "—"),
              if (_bmi != null)
                _buildCompactProfileCell("BMI", _bmi!.toStringAsFixed(1), 
                    color: _bmiCategory == 'Normal' ? Colors.green : Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactProfileCell(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.grey.shade500, letterSpacing: 0.5),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: color ?? const Color(0xFF1C1C1E),
          ),
        ),
      ],
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

  Widget _buildOverallHealthStatusCard(double avgHR, double avgTemp, int highRiskDays) {
    // Logic for Aggregate Health Score - Using provided period averages
    int score = 100;
    if (avgHR > 90 || avgHR < 60) score -= 15;
    if (avgHR > 110 || avgHR < 50) score -= 25;
    if (avgTemp > 37.2 || avgTemp < 36.2) score -= 15;
    if (avgTemp > 38.0 || avgTemp < 35.5) score -= 25;
    if (highRiskDays > 0) score -= (highRiskDays * 10).clamp(0, 40);
    
    final int finalScore = score.clamp(0, 100);
    final String statusLabel = finalScore >= 85 ? "OPTIMAL" : finalScore >= 60 ? "STABLE" : "CAUTION";
    final Color statusColor = finalScore >= 85 ? const Color(0xFF34C759) : finalScore >= 60 ? const Color(0xFF007AFF) : const Color(0xFFFF3B30);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF065aa7).withOpacity(0.05),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF065aa7).withOpacity(0.15), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Overall Medical Status",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Aggregate for $_periodLabel",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: CircularProgressIndicator(
                      value: finalScore / 100,
                      strokeWidth: 10,
                      backgroundColor: Colors.white,
                      color: statusColor,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Text(
                    "$finalScore",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                       finalScore >= 85 ? "Excellent Condition" : finalScore >= 60 ? "Fair Condition" : "Medical Attention Needed",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getHealthStatus(), // Keeps the descriptive logic from original
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
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

  Widget _buildPersonalizedRecommendations(double avgHR, double avgTemp, int highRiskDays) {
    final List<Map<String, dynamic>> recommendations = [];

    if (avgHR > 90) {
      recommendations.add({
        "icon": Icons.speed_rounded,
        "title": "Heart Rate Alert",
        "tip": "Your average heart rate is high. Consider yoga or reducing high-intensity cardio.",
        "color": Colors.red,
      });
    }

    if (avgTemp > 37.2) {
      recommendations.add({
        "icon": Icons.thermostat_rounded,
        "title": "Temperature Trend",
        "tip": "Slightly elevated average. Ensure you aren't overexerting yourself.",
        "color": Colors.orange,
      });
    }

    if (highRiskDays > 0) {
      recommendations.add({
        "icon": Icons.health_and_safety_rounded,
        "title": "Clinical Review",
        "tip": "Multiple high-risk alerts detected. We recommend sharing this report with your doctor.",
        "color": Colors.indigo,
      });
    }

    // Default wellness advice
    recommendations.add({
      "icon": Icons.local_drink_rounded,
      "title": "Hydration Balance",
      "tip": "Keep drinking 3L of water. It helps stabilize your metabolic rate.",
      "color": Colors.blue,
    });

    recommendations.add({
      "icon": Icons.bedtime_rounded,
      "title": "Sleep Hygiene",
      "tip": "Maintaining 7+ hours of sleep will improve your overall recovery score.",
      "color": Colors.deepPurple,
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            "Medical Recommendations",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1C1C1E),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: recommendations.length,
            itemBuilder: (context, index) {
              final rec = recommendations[index];
              return Container(
                width: 260,
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: rec["color"].withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: rec["color"].withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(rec["icon"], color: rec["color"], size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            rec["title"],
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1C1C1E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            rec["tip"],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String type, VoidCallback onTap) {
    final bool active = _selectedPeriodType == type;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2D62ED).withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? const Color(0xFF2D62ED).withOpacity(0.5) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w900 : FontWeight.w600,
            color: active ? const Color(0xFF2D62ED) : Colors.grey.shade600,
          ),
        ),
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

    if (spots.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        height: 150,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isHR ? Icons.favorite_border_rounded : Icons.thermostat_auto_rounded, 
                  color: Colors.grey.shade300, size: 40),
              const SizedBox(height: 12),
              Text("No data for this period", 
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    final Color primaryColor = isHR ? const Color(0xFFFF4D4D) : const Color(0xFF4D94FF);
    final trend = _getTrendArrow(isHR);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 4),
                  Text(
                    isHR ? "BPM Averages" : "Celsius Averages",
                    style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _fetchReportData,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(
                        trend,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "REFRESH",
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: primaryColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: LineChart(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOutCubic,
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade100,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= _dailyData.length) return const Text('');
                        
                        // Dynamically adjust label frequency
                        int interval = 1;
                        if (_selectedPeriodType == 'monthly') interval = 5;
                        if (_dailyData.length > 31) interval = 7;
                        
                        if (i % interval != 0 && i != _dailyData.length - 1) return const Text('');

                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            DateFormat('dd').format(_dailyData[i].date),
                            style: TextStyle(
                              fontSize: 9, 
                              color: Colors.grey.shade500, 
                              fontWeight: FontWeight.bold
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(fontSize: 9, color: Colors.grey.shade400, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => primaryColor.withOpacity(0.8),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          "${spot.y.toStringAsFixed(isHR ? 0 : 1)}${isHR ? ' BPM' : '°C'}\n${DateFormat('MMM dd').format(_dailyData[spot.x.toInt()].date)}",
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        );
                      }).toList();
                    },
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (_dailyData.length - 1).toDouble(),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: primaryColor,
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 3,
                          color: Colors.white,
                          strokeColor: primaryColor,
                          strokeWidth: 2,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          primaryColor.withOpacity(0.2),
                          primaryColor.withOpacity(0.0),
                        ],
                      ),
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF2D62ED).withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF2D62ED).withOpacity(0.1), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_rounded, color: Colors.amber.shade700, size: 28),
              const SizedBox(width: 12),
              const Text(
                "Health Insights",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            "Based on your recent trends, maintaining a consistent sleep schedule and staying hydrated can significantly stabilize your heart rate and body temperature readings.",
            style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // --- NEW HISTORY SECTION ---

  Widget _buildHistorySection() {
    final now = DateTime.now();
    final today = _dailyData.firstWhere(
      (d) => DateFormat('yyyy-MM-dd').format(d.date) == 
             DateFormat('yyyy-MM-dd').format(now),
      orElse: () => DailySummary(
        date: now, 
        avgHR: 0, avgTemp: 0, minHR: 0, maxHR: 0, minTemp: 0, maxTemp: 0, 
        readingsCount: 0, highRiskPercent: 0
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            "Daily Average Summary",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1C1C1E), letterSpacing: -0.5),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2D62ED).withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            onTap: () => _showDayDetailDialog(today),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF2D62ED).withOpacity(0.1),
                border: Border.all(color: const Color(0xFF2D62ED).withOpacity(0.2)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('dd').format(today.date),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 16,
                        color: Color(0xFF2D62ED)
                      )),
                  Text(DateFormat('MMM').format(today.date).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9, 
                        fontWeight: FontWeight.w900, 
                        color: Color(0xFF2D62ED)
                      )),
                ],
              ),
            ),
            title: Row(
              children: [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D62ED),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text("TODAY", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                ),
                Text(
                  today.readingsCount > 0 ? "${today.avgHR.toInt()} BPM" : "-- BPM",
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(width: 8),
                Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(
                  today.readingsCount > 0 ? "${today.avgTemp.toStringAsFixed(1)}°C" : "--°C",
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF2D62ED)),
                ),
              ],
            ),
            subtitle: Text(
              today.readingsCount > 0 
                ? "Averages from ${today.readingsCount} sensor tracks" 
                : "No data recorded yet today",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF2D62ED), size: 14),
          ),
        ),
      ],
    );
  }

  void _showDayDetailDialog(DailySummary day) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool isSyncing = false;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, color: Colors.indigo.shade700),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(DateFormat('MMM dd, yyyy').format(day.date), 
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_month_rounded, color: Color(0xFF2D62ED)),
                  onPressed: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: day.date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (pickedDate != null && mounted) {
                      setDialogState(() => isSyncing = true);
                      
                      try {
                        // 1. Try to find in existing _dailyData
                        final found = _dailyData.firstWhere(
                          (d) => DateFormat('yyyy-MM-dd').format(d.date) == 
                                 DateFormat('yyyy-MM-dd').format(pickedDate),
                          orElse: () => DailySummary(
                            date: pickedDate, 
                            avgHR: 0, avgTemp: 0, minHR: 0, maxHR: 0, minTemp: 0, maxTemp: 0, 
                            readingsCount: -1, // Flag as not searched yet
                            highRiskPercent: 0
                          ),
                        );

                        if (found.readingsCount != -1) {
                          setDialogState(() {
                            day = found;
                            isSyncing = false;
                          });
                        } else {
                          // 2. Data not in current period, fetch from Firebase specifically for this day
                          final startOfDay = DateTime(pickedDate.year, pickedDate.month, pickedDate.day);
                          final endOfDay = startOfDay.add(const Duration(days: 1));

                          final snapshot = await _firestore
                              .collection("health_readings")
                              .where("userId", isEqualTo: userId)
                              .where("createdAt", isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
                              .where("createdAt", isLessThan: Timestamp.fromDate(endOfDay))
                              .get();

                          double sumHR = 0, sumTemp = 0;
                          double minHR = double.infinity, maxHR = 0;
                          double minTemp = double.infinity, maxTemp = 0;
                          int highRiskCount = 0;
                          int hrValid = 0, tempValid = 0;

                          for (var doc in snapshot.docs) {
                            final r = doc.data();
                            final hr = (r['heartRate'] as num?)?.toDouble() ?? 0;
                            final temp = (r['bodyTemperature'] as num?)?.toDouble() ?? 0;
                            
                            if (hr > 0) {
                              sumHR += hr; hrValid++;
                              if (hr < minHR) minHR = hr;
                              if (hr > maxHR) maxHR = hr;
                            }
                            if (temp > 0) {
                              sumTemp += temp; tempValid++;
                              if (temp < minTemp) minTemp = temp;
                              if (temp > maxTemp) maxTemp = temp;
                            }
                            final risk = (r['riskLevel'] as String? ?? '').toLowerCase();
                            if (risk.contains('high')) highRiskCount++;
                          }

                          final count = snapshot.docs.length;
                          setDialogState(() {
                            day = DailySummary(
                              date: pickedDate,
                              avgHR: hrValid > 0 ? sumHR / hrValid : 0,
                              avgTemp: tempValid > 0 ? sumTemp / tempValid : 0,
                              minHR: minHR.isFinite ? minHR : 0,
                              maxHR: maxHR,
                              minTemp: minTemp.isFinite ? minTemp : 0,
                              maxTemp: maxTemp,
                              readingsCount: count,
                              highRiskPercent: count > 0 ? (highRiskCount / count) * 100 : 0,
                            );
                            isSyncing = false;
                          });
                        }
                      } catch (e) {
                         debugPrint("Popup fetch error: $e");
                         setDialogState(() => isSyncing = false);
                      }
                    }
                  },
                ),
              ],
            ),
            content: isSyncing 
              ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (day.readingsCount == 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            Icon(Icons.query_stats_rounded, color: Colors.grey.shade300, size: 48),
                            const SizedBox(height: 16),
                            const Text("No biometric data found for this date", 
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                      )
                    else ...[
                      _buildDialogStatRow("Avg Heart Rate", "${day.avgHR.toInt()} BPM", Colors.red),
                      _buildDialogStatRow("HR Range", "${day.minHR.toInt()} - ${day.maxHR.toInt()} BPM", Colors.red.shade300),
                      const Divider(height: 24),
                      _buildDialogStatRow("Avg Temperature", "${day.avgTemp.toStringAsFixed(1)} °C", Colors.blue),
                      _buildDialogStatRow("Temp Range", "${day.minTemp.toStringAsFixed(1)} - ${day.maxTemp.toStringAsFixed(1)} °C", Colors.blue.shade300),
                      const Divider(height: 24),
                      _buildDialogStatRow("Total Data Points", "${day.readingsCount}", Colors.grey.shade700),
                      _buildDialogStatRow("Risk Probability", "${day.highRiskPercent.toStringAsFixed(1)}%", Colors.orange),
                    ],
                  ],
                ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CLOSE", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2D62ED))),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDialogStatRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  // --- PDF HELPER METHODS ---

  pw.Widget _buildPdfCell(String label, String value, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  pw.Widget _buildPdfStat(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
      ],
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
