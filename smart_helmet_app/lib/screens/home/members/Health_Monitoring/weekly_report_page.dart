// weekly_report_page.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

class WeeklyReportPage extends StatefulWidget {
  const WeeklyReportPage({super.key});

  @override
  State<WeeklyReportPage> createState() => _WeeklyReportPageState();
}

class _WeeklyReportPageState extends State<WeeklyReportPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String userId = "abc123xyz"; // replace with auth logic

  final ScreenshotController _screenshotController = ScreenshotController();

  List<DailySummary> _dailyData = [];
  bool _isLoading = true;
  String _error = '';

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  String _periodLabel = "Last 7 Days";

  @override
  void initState() {
    super.initState();
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
          .where("createdAt", isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
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

        double sumHR = 0, sumTemp = 0, minHR = double.infinity, maxHR = 0, minTemp = double.infinity, maxTemp = 0;
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
          _periodLabel = "${DateFormat('MMM d').format(_startDate)} – ${DateFormat('MMM d, yyyy').format(_endDate)}";
        }
        break;
    }
    await _fetchReportData();
  }

  Future<void> _exportToPdf() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          pw.Header(level: 0, text: 'Health Report – $_periodLabel'),
          pw.SizedBox(height: 16),
          pw.Text('Average Heart Rate: ${_getOverallAvgHR().toStringAsFixed(0)} BPM'),
          pw.Text('Average Temperature: ${_getOverallAvgTemp().toStringAsFixed(1)} °C'),
          pw.SizedBox(height: 24),
          pw.Text('Daily Summary', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Table.fromTextArray(
            headers: ['Date', 'Avg HR', 'Min HR', 'Max HR', 'Avg Temp', 'Readings'],
            data: _dailyData.map((d) => [
              DateFormat('MMM dd').format(d.date),
              d.avgHR.toStringAsFixed(0),
              d.minHR.toStringAsFixed(0),
              d.maxHR.toStringAsFixed(0),
              d.avgTemp.toStringAsFixed(1),
              d.readingsCount.toString(),
            ]).toList(),
          ),
        ],
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/health_report.pdf");
    await file.writeAsBytes(await pdf.save());

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'health_report.pdf');
  }

  Future<void> _shareAsImage() async {
    try {
      final imageBytes = await _screenshotController.capture();
      if (imageBytes == null) return;

      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/health_report.png';
      final file = File(imagePath);
      await file.writeAsBytes(imageBytes);

      await Share.shareXFiles([XFile(imagePath)], text: 'My Health Report – $_periodLabel');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing image: $e')),
        );
      }
    }
  }

  Future<void> _downloadReport() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(level: 0, text: 'Health Report – $_periodLabel'),
          pw.SizedBox(height: 16),
          pw.Text('Average Heart Rate: ${_getOverallAvgHR().toStringAsFixed(0)} BPM'),
          pw.Text('Average Temperature: ${_getOverallAvgTemp().toStringAsFixed(1)} °C'),
          pw.SizedBox(height: 24),
          pw.Text('Daily Summary', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Table.fromTextArray(
            headers: ['Date', 'Avg HR', 'Min HR', 'Max HR', 'Avg Temp', 'Readings'],
            data: _dailyData.map((d) => [
              DateFormat('MMM dd').format(d.date),
              d.avgHR.toStringAsFixed(0),
              d.minHR.toStringAsFixed(0),
              d.maxHR.toStringAsFixed(0),
              d.avgTemp.toStringAsFixed(1),
              d.readingsCount.toString(),
            ]).toList(),
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/health_report.pdf");
    await file.writeAsBytes(await pdf.save());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report downloaded to ${file.path}')),
      );
    }
  }

  double _getOverallAvgHR() {
    final valid = _dailyData.where((d) => d.avgHR > 0);
    return valid.isEmpty ? 0 : valid.fold<double>(0, (s, d) => s + d.avgHR) / valid.length;
  }

  double _getOverallAvgTemp() {
    final valid = _dailyData.where((d) => d.avgTemp > 0);
    return valid.isEmpty ? 0 : valid.fold<double>(0, (s, d) => s + d.avgTemp) / valid.length;
  }

  Color _getRiskBackgroundColor() {
    final highRiskDays = _dailyData.where((d) => d.highRiskPercent > 30).length;
    final totalDays = _dailyData.length;
    final riskRatio = totalDays > 0 ? highRiskDays / totalDays : 0;

    if (riskRatio > 0.4) return Colors.red.shade50;
    if (riskRatio > 0.2) return Colors.orange.shade50;
    return Colors.green.shade50;
  }

  @override
  Widget build(BuildContext context) {
    final validDays = _dailyData.where((d) => d.readingsCount > 0).toList();
    final avgHR = validDays.isEmpty ? 0.0 : validDays.fold<double>(0, (s, d) => s + d.avgHR) / validDays.length;
    final avgTemp = validDays.isEmpty ? 0.0 : validDays.fold<double>(0, (s, d) => s + d.avgTemp) / validDays.length;
    final highRiskDays = _dailyData.where((d) => d.highRiskPercent > 30).length;

    return Screenshot(
      controller: _screenshotController,
      child: Scaffold(
        backgroundColor: _getRiskBackgroundColor(),
        appBar: AppBar(
          title: const Text("Health Report", style: TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: "Download PDF",
              onPressed: _downloadReport,
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: "Export PDF",
              onPressed: _exportToPdf,
            ),
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: "Share as Image",
              onPressed: _shareAsImage,
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
                  Text(_periodLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip("Weekly", () => _selectPeriod('weekly')),
                        const SizedBox(width: 8),
                        _buildFilterChip("Monthly", () => _selectPeriod('monthly')),
                        const SizedBox(width: 8),
                        _buildFilterChip("Custom", () => _selectPeriod('custom')),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error.isNotEmpty
                      ? Center(child: Text("Error: $_error", style: const TextStyle(color: Colors.red)))
                      : _dailyData.isEmpty
                          ? const Center(child: Text("No data for selected period"))
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: _buildSummaryCard("Avg HR", "${avgHR.toStringAsFixed(0)} BPM", Icons.favorite, Colors.red)),
                                      const SizedBox(width: 12),
                                      Expanded(child: _buildSummaryCard("Avg Temp", "${avgTemp.toStringAsFixed(1)}°C", Icons.thermostat, Colors.blue)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(child: _buildSummaryCard("High Risk Days", "$highRiskDays/${_dailyData.length}", Icons.warning, Colors.orange)),
                                      const SizedBox(width: 12),
                                      Expanded(child: _buildSummaryCard("Total Readings", _dailyData.fold<int>(0, (s, d) => s + d.readingsCount).toString(), Icons.analytics, Colors.indigo)),
                                    ],
                                  ),
                                  const SizedBox(height: 24),

                                  // Health Insights before charts
                                  const Text("Health Insights", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 12),
                                  _buildDoctorAdvice(avgHR, avgTemp, highRiskDays),
                                  const SizedBox(height: 24),

                                  _buildTrendCard("Heart Rate", true),
                                  const SizedBox(height: 24),
                                  _buildTrendCard("Temperature", false),
                                  const SizedBox(height: 32),

                                  _buildTipsSection(),
                                ],
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onTap) {
    final bool active = (label == "Weekly" && _periodLabel.contains("7")) ||
        (label == "Monthly" && _periodLabel.contains("30")) ||
        (label == "Custom" && !_periodLabel.contains("Days"));
    return ActionChip(
      label: Text(label),
      backgroundColor: active ? Colors.indigo.shade100 : null,
      onPressed: onTap,
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendCard(String title, bool isHR) {
    final spots = _dailyData.asMap().entries.where((e) => (isHR ? e.value.avgHR : e.value.avgTemp) > 0).map((e) {
      return FlSpot(e.key.toDouble(), isHR ? e.value.avgHR : e.value.avgTemp);
    }).toList();

    if (spots.isEmpty) return const SizedBox();

    final color = isHR ? Colors.red : Colors.blue;
    final trend = _getTrendArrow(isHR);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text(trend, style: TextStyle(fontSize: 20, color: trend.contains('↑') ? Colors.red : trend.contains('↓') ? Colors.green : Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= _dailyData.length) return const Text('');
                          return Text(DateFormat('d').format(_dailyData[i].date), style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                  ),
                  minX: 0,
                  maxX: (_dailyData.length - 1).toDouble(),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: color,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
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
    final prev = isHR ? _dailyData[_dailyData.length - 2].avgHR : _dailyData[_dailyData.length - 2].avgTemp;
    if (last > prev + 2) return "↑";
    if (last < prev - 2) return "↓";
    return "→";
  }

  Widget _buildDoctorAdvice(double avgHR, double avgTemp, int highRiskDays) {
    final advice = <Widget>[];

    if (avgHR > 95 || highRiskDays > 3) {
      advice.add(_buildAdviceTile(Icons.warning, Colors.red, "High Risk", "Consult doctor soon"));
    } else if (avgHR > 85) {
      advice.add(_buildAdviceTile(Icons.info, Colors.orange, "Elevated", "Monitor closely"));
    }

    if (avgTemp > 37.2) {
      advice.add(_buildAdviceTile(Icons.thermostat, Colors.red, "High Temp", "Check for fever"));
    }

    if (advice.isEmpty) {
      advice.add(_buildAdviceTile(Icons.check_circle, Colors.green, "Good", "Keep it up!"));
    }

    return Column(children: advice);
  }

  Widget _buildAdviceTile(IconData icon, Color color, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
    );
  }

  Widget _buildTipsSection() {
    const tips = [
      "Drink 2.5–3 L water daily",
      "30 min moderate exercise",
      "Sleep 7–9 hours",
      "Balanced diet",
      "Manage stress",
    ];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Tips", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...tips.map((t) => Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t, style: const TextStyle(fontSize: 14))),
                  ],
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