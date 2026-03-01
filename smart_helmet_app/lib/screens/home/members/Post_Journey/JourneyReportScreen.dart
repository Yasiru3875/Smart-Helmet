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
import 'package:fl_chart/fl_chart.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
  bool _isGeneratingPdf = false;

  // Danger zone filter toggles
  bool _showRiskyTurns = true;
  bool _showSharpTurns = true;
  bool _showBrakes = true;
  bool _showStressPeaks = true;
  bool _showCritical = true;

  JourneyData get j => widget.journey;

  @override
  void initState() {
    super.initState();
    _buildMapData();
  }

  // ───────────────────────────────────────────────────────────
  // MAP DATA — builds route polyline + all danger zone markers
  // ───────────────────────────────────────────────────────────
  void _buildMapData() {
    final markers = <Marker>{};
    final polylines = <Polyline>{};

    // ── 1. GPS Route polyline (blue) ──────────────────────
    if (j.gpsTrack.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: j.gpsTrack.map((p) => LatLng(p.latitude, p.longitude)).toList(),
        color: const Color(0xFF1565C0),
        width: 5,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ));
    }

    // ── 2. Start marker (green) ───────────────────────────
    if (j.gpsTrack.isNotEmpty) {
      markers.add(Marker(
        markerId: const MarkerId('journey_start'),
        position: LatLng(j.gpsTrack.first.latitude, j.gpsTrack.first.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: '🚦 Start: ${j.startLocation ?? 'Start Point'}',
          snippet: DateFormat('HH:mm').format(j.startTime),
        ),
        zIndex: 10,
      ));
    }

    // ── 3. End marker (rose/red) ──────────────────────────
    if (j.gpsTrack.length > 1) {
      markers.add(Marker(
        markerId: const MarkerId('journey_end'),
        position: LatLng(j.gpsTrack.last.latitude, j.gpsTrack.last.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
        infoWindow: InfoWindow(
          title: '🏁 End: ${j.destination ?? 'End Point'}',
          snippet: j.endTime != null ? DateFormat('HH:mm').format(j.endTime!) : '',
        ),
        zIndex: 10,
      ));
    }

    // ── 4. Risky turns (red) ──────────────────────────────
    if (_showRiskyTurns) {
      for (int i = 0; i < j.turnEvents.length; i++) {
        final e = j.turnEvents[i];
        if (e.severity == 'risky') {
          markers.add(Marker(
            markerId: MarkerId('risky_$i'),
            position: LatLng(e.latitude, e.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: '⚠️ RISKY TURN',
              snippet: '${e.turnRate.abs().toStringAsFixed(1)}°/s  ·  ${DateFormat('HH:mm:ss').format(e.timestamp)}',
            ),
            zIndex: 8,
          ));
        }
      }
    }

    // ── 5. Sharp turns (orange) ───────────────────────────
    if (_showSharpTurns) {
      for (int i = 0; i < j.turnEvents.length; i++) {
        final e = j.turnEvents[i];
        if (e.severity == 'sharp') {
          markers.add(Marker(
            markerId: MarkerId('sharp_$i'),
            position: LatLng(e.latitude, e.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(
              title: '↩️ Sharp Turn',
              snippet: '${e.turnRate.abs().toStringAsFixed(1)}°/s  ·  ${DateFormat('HH:mm:ss').format(e.timestamp)}',
            ),
            zIndex: 6,
          ));
        }
      }
    }

    // ── 6. Brake events ───────────────────────────────────
    if (_showBrakes) {
      for (int i = 0; i < j.brakeEvents.length; i++) {
        final e = j.brakeEvents[i];
        markers.add(Marker(
          markerId: MarkerId('brake_$i'),
          position: LatLng(e.latitude, e.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            e.severity == 'harsh' ? BitmapDescriptor.hueYellow : BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: e.severity == 'harsh' ? '🛑 Harsh Brake' : '⚠ Sudden Brake',
            snippet: '${e.deceleration.toStringAsFixed(1)} m/s²  ·  ${DateFormat('HH:mm:ss').format(e.timestamp)}',
          ),
          zIndex: 7,
        ));
      }
    }

    // ── 7. Stress peaks (violet) ──────────────────────────
    if (_showStressPeaks) {
      for (int i = 0; i < j.stressPeaks.length; i++) {
        final e = j.stressPeaks[i];
        markers.add(Marker(
          markerId: MarkerId('stress_$i'),
          position: LatLng(e.latitude, e.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(
            title: '🧠 Stress Peak — ${e.stressLevel}%',
            snippet: DateFormat('HH:mm:ss').format(e.timestamp),
          ),
          zIndex: 7,
        ));
      }
    }

    // ── 8. Critical events (cyan) ─────────────────────────
    if (_showCritical) {
      for (int i = 0; i < j.criticalEvents.length; i++) {
        final e = j.criticalEvents[i];
        markers.add(Marker(
          markerId: MarkerId('crit_$i'),
          position: LatLng(e.latitude, e.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: InfoWindow(
            title: '🚨 ${e.severityLabel} Event',
            snippet: '${e.description}  ·  ${DateFormat('HH:mm:ss').format(e.timestamp)}',
          ),
          zIndex: 9,
        ));
      }
    }

    _markers = markers;
    _polylines = polylines;
  }

  void _rebuildMap() => setState(_buildMapData);

  Future<void> _fitRoute() async {
    if (_mapController == null || j.gpsTrack.isEmpty) return;
    if (j.gpsTrack.length == 1) {
      _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(j.gpsTrack.first.latitude, j.gpsTrack.first.longitude), 15));
      return;
    }
    final lats = j.gpsTrack.map((p) => p.latitude).toList();
    final lngs = j.gpsTrack.map((p) => p.longitude).toList();
    await _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
        northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
      ),
      60,
    ));
  }

  Color get _scoreColor {
    if (j.riskScore >= 80) return Colors.green;
    if (j.riskScore >= 60) return Colors.orange;
    if (j.riskScore >= 40) return Colors.deepOrange;
    return Colors.red;
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(j.destination != null
            ? 'Report: ${j.destination}'
            : 'Journey Report'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isGeneratingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
            onPressed: _isGeneratingPdf ? null : _exportPdf,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildScoreHeader(),
          _buildRideMap(),       // ★ Full ride visualization
          _buildMapFilters(),    // ★ Toggle danger zone visibility
          _buildDangerLog(),     // ★ All events with coordinates
          _buildTurnChart(),
          _buildStressChart(),
          _buildEventBreakdown(),
          _buildCriticalEvents(),
          _buildWeatherSection(),
          _buildRecommendations(),
          const SizedBox(height: 36),
        ]),
      ),
    );
  }

  // ── 1. Score Header ──────────────────────────────────────
  Widget _buildScoreHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[700]!, Colors.blue[900]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(children: [
        CircularPercentIndicator(
          radius: 68,
          lineWidth: 11,
          percent: (j.riskScore / 100).clamp(0.0, 1.0),
          center: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(j.riskScore.toStringAsFixed(0),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
            Text(j.riskLabel, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
          progressColor: _scoreColor,
          backgroundColor: Colors.white24,
          circularStrokeCap: CircularStrokeCap.round,
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (j.startLocation != null)
              _hRow(Icons.trip_origin, j.startLocation!, color: Colors.greenAccent),
            if (j.destination != null)
              _hRow(Icons.location_on, j.destination!, color: Colors.redAccent[100]!),
            const SizedBox(height: 4),
            _hRow(Icons.calendar_today, DateFormat('EEE, MMM dd yyyy').format(j.startTime)),
            _hRow(Icons.access_time,
                '${DateFormat('HH:mm').format(j.startTime)}  →  ${j.endTime != null ? DateFormat('HH:mm').format(j.endTime!) : '--:--'}'),
            _hRow(Icons.timer, '${j.duration.inMinutes} min'),
            _hRow(Icons.straighten, '${j.totalDistance.toStringAsFixed(2)} km'),
            _hRow(Icons.speed,
                'Avg ${j.averageSpeed.toStringAsFixed(1)}  ·  Max ${j.maxSpeed.toStringAsFixed(1)} km/h'),
          ]),
        ),
      ]),
    );
  }

  Widget _hRow(IconData icon, String text, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Icon(icon, size: 13, color: color ?? Colors.white70),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color ?? Colors.white))),
    ]),
  );

  // ── 2. RIDE VISUALIZATION MAP ────────────────────────────
  Widget _buildRideMap() {
    final hasGps = j.gpsTrack.isNotEmpty;
    final initialPos = hasGps
        ? LatLng(j.gpsTrack.first.latitude, j.gpsTrack.first.longitude)
        : const LatLng(6.9271, 79.8612);

    return _section(
      icon: Icons.map,
      title: 'Ride Route & Danger Zones',
      subtitle: hasGps
          ? 'Full route from ${j.startLocation ?? 'Start'} to ${j.destination ?? 'End'}'
          : 'No GPS data recorded',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Google Map ──────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 350,
            child: hasGps
                ? Stack(children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(target: initialPos, zoom: 13),
                      onMapCreated: (ctrl) async {
                        _mapController = ctrl;
                        await Future.delayed(const Duration(milliseconds: 600));
                        await _fitRoute();
                      },
                      markers: _markers,
                      polylines: _polylines,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: true,
                      compassEnabled: true,
                      mapToolbarEnabled: false,
                    ),
                    // Fit-to-route FAB
                    Positioned(
                      right: 10,
                      bottom: 60,
                      child: FloatingActionButton.small(
                        heroTag: 'fitRoute',
                        backgroundColor: Colors.white,
                        elevation: 3,
                        onPressed: _fitRoute,
                        tooltip: 'Fit full route',
                        child: const Icon(Icons.fit_screen, color: Colors.blue, size: 20),
                      ),
                    ),
                  ])
                : Container(
                    color: Colors.grey[200],
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.gps_off, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 10),
                      Text('No GPS route recorded',
                          style: TextStyle(color: Colors.grey[600], fontSize: 15)),
                      const SizedBox(height: 4),
                      Text('Enable GPS on helmet during ride',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                    ]),
                  ),
          ),
        ),
        const SizedBox(height: 14),

        // ── Map Legend ──────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Map Legend',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 8, children: [
              _legendItem(const Color(0xFF1565C0), 'Route Traveled', isLine: true),
              _legendItem(Colors.green, 'Start Point'),
              _legendItem(Colors.pink[300]!, 'End Point'),
              _legendItem(Colors.red, '⚠️ Risky Turn'),
              _legendItem(Colors.orange, '↩️ Sharp Turn'),
              _legendItem(Colors.yellow[700]!, '🛑 Harsh Brake'),
              _legendItem(Colors.lightBlue, '⚠ Sudden Brake'),
              _legendItem(Colors.purple[400]!, '🧠 Stress Peak'),
              _legendItem(Colors.cyan[700]!, '🚨 Critical Event'),
            ]),
          ]),
        ),

        const SizedBox(height: 12),

        // ── Danger counts strip ─────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.red[50]!, Colors.orange[50]!],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange[100]!),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _dangerCount('Risky\nTurns', j.riskyTurns, Colors.red),
            _vertLine(),
            _dangerCount('Sharp\nTurns', j.sharpTurns, Colors.orange),
            _vertLine(),
            _dangerCount('Sudden\nBrakes', j.suddenBrakes, Colors.yellow[800]!),
            _vertLine(),
            _dangerCount('Stress\nPeaks', j.stressPeakCount, Colors.purple),
            _vertLine(),
            _dangerCount('Critical\nEvents', j.criticalEvents.length, Colors.red[900]!),
          ]),
        ),
      ]),
    );
  }

  Widget _legendItem(Color color, String label, {bool isLine = false}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        isLine
            ? Container(width: 22, height: 4,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)))
            : Container(width: 13, height: 13, decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);

  Widget _dangerCount(String label, int n, Color color) => Column(children: [
    Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
    Text(label, style: TextStyle(fontSize: 10, color: color), textAlign: TextAlign.center),
  ]);

  Widget _vertLine() => Container(width: 1, height: 40, color: Colors.orange[200]);

  // ── 3. Map Filters ───────────────────────────────────────
  Widget _buildMapFilters() {
    return _section(
      icon: Icons.tune,
      title: 'Danger Zone Visibility',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _filterChip('Risky Turns', _showRiskyTurns, Colors.red, () {
            setState(() { _showRiskyTurns = !_showRiskyTurns; _rebuildMap(); });
          }),
          _filterChip('Sharp Turns', _showSharpTurns, Colors.orange, () {
            setState(() { _showSharpTurns = !_showSharpTurns; _rebuildMap(); });
          }),
          _filterChip('Brakes', _showBrakes, Colors.yellow[700]!, () {
            setState(() { _showBrakes = !_showBrakes; _rebuildMap(); });
          }),
          _filterChip('Stress Peaks', _showStressPeaks, Colors.purple, () {
            setState(() { _showStressPeaks = !_showStressPeaks; _rebuildMap(); });
          }),
          _filterChip('Critical', _showCritical, Colors.cyan[700]!, () {
            setState(() { _showCritical = !_showCritical; _rebuildMap(); });
          }),
          ActionChip(
            avatar: const Icon(Icons.fit_screen, size: 15),
            label: const Text('Fit Route', style: TextStyle(fontSize: 12)),
            onPressed: _fitRoute,
            backgroundColor: Colors.blue[50],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool active, Color color, VoidCallback onTap) =>
      FilterChip(
        label: Text(label, style: TextStyle(color: active ? Colors.white : color, fontSize: 12)),
        selected: active,
        selectedColor: color,
        checkmarkColor: Colors.white,
        backgroundColor: color.withOpacity(0.12),
        side: BorderSide(color: color),
        onSelected: (_) => onTap(),
      );

  // ── 4. Danger Event Log ──────────────────────────────────
  Widget _buildDangerLog() {
    final hasEvents = j.turnEvents.isNotEmpty ||
        j.brakeEvents.isNotEmpty ||
        j.stressPeaks.isNotEmpty ||
        j.criticalEvents.isNotEmpty;

    return _section(
      icon: Icons.place,
      title: 'Danger Zone Log',
      subtitle: 'All events with GPS coordinates',
      child: hasEvents
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Risky Turns
              if (j.turnEvents.any((e) => e.severity == 'risky')) ...[
                _dangerHeader('🔴  Risky Turns', Colors.red, j.turnEvents.where((e) => e.severity == 'risky').length),
                ...j.turnEvents.where((e) => e.severity == 'risky').map((e) =>
                    _eventRow(Icons.warning_amber, Colors.red,
                        '${e.turnRate.abs().toStringAsFixed(1)}°/s',
                        e.timestamp, e.latitude, e.longitude)),
                const SizedBox(height: 10),
              ],
              // Sharp Turns
              if (j.turnEvents.any((e) => e.severity == 'sharp')) ...[
                _dangerHeader('🟠  Sharp Turns', Colors.orange, j.turnEvents.where((e) => e.severity == 'sharp').length),
                ...j.turnEvents.where((e) => e.severity == 'sharp').map((e) =>
                    _eventRow(Icons.turn_sharp_right, Colors.orange,
                        '${e.turnRate.abs().toStringAsFixed(1)}°/s',
                        e.timestamp, e.latitude, e.longitude)),
                const SizedBox(height: 10),
              ],
              // Brakes
              if (j.brakeEvents.isNotEmpty) ...[
                _dangerHeader('🟡  Sudden / Harsh Braking', Colors.yellow[800]!, j.brakeEvents.length),
                ...j.brakeEvents.map((e) =>
                    _eventRow(
                        e.severity == 'harsh' ? Icons.stop_circle : Icons.warning,
                        e.severity == 'harsh' ? Colors.red[700]! : Colors.orange,
                        '${e.deceleration.toStringAsFixed(1)} m/s²  (${e.severity})',
                        e.timestamp, e.latitude, e.longitude)),
                const SizedBox(height: 10),
              ],
              // Stress Peaks
              if (j.stressPeaks.isNotEmpty) ...[
                _dangerHeader('🟣  EEG Stress Peaks', Colors.purple, j.stressPeaks.length),
                ...j.stressPeaks.map((e) =>
                    _eventRow(Icons.psychology, Colors.purple,
                        'Stress ${e.stressLevel}%',
                        e.timestamp, e.latitude, e.longitude)),
                const SizedBox(height: 10),
              ],
              // Critical Events
              if (j.criticalEvents.isNotEmpty) ...[
                _dangerHeader('🚨  Critical Multi-Factor Events', Colors.red[900]!, j.criticalEvents.length),
                ...j.criticalEvents.map((e) =>
                    _eventRow(Icons.dangerous, Colors.red[900]!,
                        '${e.severityLabel}: ${e.description}',
                        e.timestamp, e.latitude, e.longitude)),
              ],
            ])
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 30),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('No danger zones detected — clean ride! 🎉',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ]),
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
    if (j.turnEvents.isEmpty) return const SizedBox();
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
    final spots = j.turnEvents.map((e) {
      final min = e.timestamp.difference(j.startTime).inSeconds / 60.0;
      return FlSpot(min, e.turnRate.abs());
    }).toList();
    return LineChartData(
      gridData: FlGridData(show: true, horizontalInterval: 50,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey[200]!, strokeWidth: 1)),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28,
            getTitlesWidget: (v, _) => Text('${v.toInt()}m', style: const TextStyle(fontSize: 10)))),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, interval: 50,
            getTitlesWidget: (v, _) => Text('${v.toInt()}°/s', style: const TextStyle(fontSize: 9)))),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey[300]!)),
      minX: 0, maxX: spots.isNotEmpty ? spots.last.x + 2 : 10, minY: 0, maxY: 220,
      lineBarsData: [LineChartBarData(
        spots: spots, isCurved: false, color: Colors.blue, barWidth: 2,
        dotData: FlDotData(show: true, getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
          radius: 5,
          color: s.y > 150 ? Colors.red : s.y > 100 ? Colors.orange : Colors.blue,
          strokeWidth: 1.5, strokeColor: Colors.white,
        )),
        belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.08)),
      )],
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(y: 100, color: Colors.orange, strokeWidth: 1.5, dashArray: [5, 5],
            label: HorizontalLineLabel(show: true, labelResolver: (_) => 'Sharp',
                style: const TextStyle(fontSize: 9, color: Colors.orange))),
        HorizontalLine(y: 150, color: Colors.red, strokeWidth: 1.5, dashArray: [5, 5],
            label: HorizontalLineLabel(show: true, labelResolver: (_) => 'Risky',
                style: const TextStyle(fontSize: 9, color: Colors.red))),
      ]),
    );
  }

  // ── 6. Stress Timeline ───────────────────────────────────
  Widget _buildStressChart() {
    if (j.sensorReadings.isEmpty) return const SizedBox();
    return _section(
      icon: Icons.psychology,
      title: 'EEG Stress Timeline',
      child: Column(children: [
        SizedBox(height: 200, child: LineChart(_stressChartData())),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _chartLegend(Colors.deepPurple, 'Stress Level (%)'),
          _chartLegend(Colors.red, 'Peak Threshold 65%', dashed: true),
        ]),
      ]),
    );
  }

  LineChartData _stressChartData() {
    final spots = j.sensorReadings.map((e) {
      final min = e.timestamp.difference(j.startTime).inSeconds / 60.0;
      return FlSpot(min, e.stressLevel.toDouble());
    }).toList();
    return LineChartData(
      gridData: FlGridData(show: true, horizontalInterval: 20,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey[200]!, strokeWidth: 1)),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28,
            getTitlesWidget: (v, _) => Text('${v.toInt()}m', style: const TextStyle(fontSize: 10)))),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, interval: 20,
            getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 9)))),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey[300]!)),
      minX: 0, maxX: spots.isNotEmpty ? spots.last.x + 1 : 10, minY: 0, maxY: 100,
      lineBarsData: [LineChartBarData(
        spots: spots, isCurved: true, curveSmoothness: 0.3,
        color: Colors.deepPurple, barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, gradient: LinearGradient(
          colors: [Colors.deepPurple.withOpacity(0.3), Colors.deepPurple.withOpacity(0.0)],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        )),
      )],
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(y: 65, color: Colors.red, strokeWidth: 1.5, dashArray: [5, 5],
            label: HorizontalLineLabel(show: true, labelResolver: (_) => 'Peak',
                style: const TextStyle(fontSize: 9, color: Colors.red))),
      ]),
    );
  }

  Widget _chartLegend(Color color, String label, {bool dashed = false}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 22, height: 3,
            decoration: BoxDecoration(
              color: dashed ? null : color, borderRadius: BorderRadius.circular(2),
              border: dashed ? Border(bottom: BorderSide(color: color, width: 2)) : null,
            )),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);

  // ── 7. Event Breakdown Cards ─────────────────────────────
  Widget _buildEventBreakdown() {
    return _section(
      icon: Icons.analytics_outlined,
      title: 'Event Summary',
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        _eventCard('Sharp Turns', '${j.sharpTurns}', Icons.turn_right, Colors.orange),
        _eventCard('Risky Turns', '${j.riskyTurns}', Icons.warning, Colors.red),
        _eventCard('Sudden Brakes', '${j.suddenBrakes}', Icons.stop_circle, Colors.yellow[800]!),
        _eventCard('Stress Peaks', '${j.stressPeakCount}', Icons.psychology, Colors.purple),
        _eventCard('Critical Events', '${j.criticalEvents.length}', Icons.dangerous, Colors.red[900]!),
        _eventCard('Avg Stress', '${j.averageStressLevel.toStringAsFixed(0)}%',
            Icons.monitor_heart, Colors.teal),
      ]),
    );
  }

  Widget _eventCard(String label, String value, IconData icon, Color color) {
    final w = (MediaQuery.of(context).size.width - 56) / 3;
    return Container(
      width: w,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[700]),
            textAlign: TextAlign.center),
      ]),
    );
  }

  // ── 8. Critical Events Detail ────────────────────────────
  Widget _buildCriticalEvents() {
    if (j.criticalEvents.isEmpty) return const SizedBox();
    return _section(
      icon: Icons.dangerous,
      title: 'Critical Risk Moments (${j.criticalEvents.length})',
      child: Column(children: j.criticalEvents.map((e) {
        final c = e.severity >= 3 ? Colors.red : e.severity == 2 ? Colors.orange : Colors.amber;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withOpacity(0.4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
                child: Text(e.severityLabel,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(e.description,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: e.factors.map((f) => Chip(
              label: Text(f, style: const TextStyle(fontSize: 10)),
              backgroundColor: c.withOpacity(0.1),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            )).toList()),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.access_time, size: 12, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(DateFormat('HH:mm:ss').format(e.timestamp),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              const SizedBox(width: 12),
              Icon(Icons.location_on, size: 12, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text('${e.latitude.toStringAsFixed(5)}, ${e.longitude.toStringAsFixed(5)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ]),
          ]),
        );
      }).toList()),
    );
  }

  // ── 9. Weather ───────────────────────────────────────────
  Widget _buildWeatherSection() {
    final w = j.weatherContext;
    if (w == null) return const SizedBox();
    return _section(
      icon: Icons.wb_cloudy_outlined,
      title: 'Weather During Ride',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: w.isAdverseWeather ? Colors.blue[50] : Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: w.isAdverseWeather ? Colors.blue[200]! : Colors.green[200]!),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _weatherCell(Icons.thermostat, '${w.temperature.toStringAsFixed(1)}°C', 'Temp'),
            _weatherCell(Icons.water_drop, '${w.humidity.toStringAsFixed(0)}%', 'Humidity'),
            _weatherCell(Icons.air, '${w.windSpeed.toStringAsFixed(1)} km/h', 'Wind'),
            _weatherCell(Icons.visibility, '${w.visibility.toStringAsFixed(1)} km', 'Visibility'),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(w.isAdverseWeather ? Icons.warning_amber : Icons.check_circle,
                color: w.isAdverseWeather ? Colors.orange : Colors.green),
            const SizedBox(width: 8),
            Expanded(child: Text(
              w.isAdverseWeather
                  ? 'Adverse conditions (${w.description}) — risk thresholds were auto-adjusted'
                  : 'Good weather conditions during ride',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            )),
          ]),
        ]),
      ),
    );
  }

  Widget _weatherCell(IconData icon, String val, String label) =>
      Column(children: [
        Icon(icon, size: 20, color: Colors.blueGrey),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]);

  // ── 10. Recommendations ──────────────────────────────────
  Widget _buildRecommendations() {
    if (j.recommendations.isEmpty) return const SizedBox();
    return _section(
      icon: Icons.lightbulb_outline,
      title: 'Personalized Recommendations',
      child: Column(children: j.recommendations.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 6, height: 6,
              margin: const EdgeInsets.only(top: 8, right: 10),
              decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle)),
          Expanded(child: Text(r, style: const TextStyle(fontSize: 14, height: 1.4))),
        ]),
      )).toList()),
    );
  }

  // ── Section wrapper ──────────────────────────────────────
  Widget _section({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) =>
      Container(
        margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: Colors.blue[700], size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    if (subtitle != null)
                      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ]),
                ),
              ]),
              const Divider(height: 20),
              child,
            ]),
          ),
        ),
      );

  // ═══════════════════════════════════════════════════════════
  // PDF EXPORT
  // ═══════════════════════════════════════════════════════════
  Future<void> _exportPdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final pdf = pw.Document();
      final sc = j.riskScore >= 80
          ? PdfColors.green
          : j.riskScore >= 60
              ? PdfColors.orange
              : j.riskScore >= 40
                  ? PdfColors.deepOrange
                  : PdfColors.red;

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blue, width: 2))),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('POST-JOURNEY RISK ASSESSMENT REPORT',
                  style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
              pw.Text('Smart Helmet App  |  IT22608086  |  Ride Visualization & Danger Zone Analysis',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
            ]),
            pw.Text(DateFormat('MMM dd, yyyy').format(j.startTime),
                style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey)),
          ]),
        ),
        build: (ctx) => [
          // Journey overview
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(color: PdfColors.blue50, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(children: [
              pw.Container(
                width: 85, height: 85,
                decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: sc, width: 6)),
                child: pw.Center(child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
                  pw.Text(j.riskScore.toStringAsFixed(0),
                      style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: sc)),
                  pw.Text(j.riskLabel, style: pw.TextStyle(fontSize: 9, color: sc)),
                ])),
              ),
              pw.SizedBox(width: 18),
              pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('${j.startLocation ?? 'Start'} → ${j.destination ?? 'End'}',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                pw.Text('Date: ${DateFormat('EEE, MMM dd yyyy  HH:mm').format(j.startTime)}'),
                pw.Text('Duration: ${j.duration.inMinutes} min  |  Distance: ${j.totalDistance.toStringAsFixed(2)} km'),
                pw.Text('Avg Speed: ${j.averageSpeed.toStringAsFixed(1)} km/h  |  Max: ${j.maxSpeed.toStringAsFixed(1)} km/h'),
              ])),
            ]),
          ),

          // Danger zone summary table
          pw.SizedBox(height: 20),
          _pdfTitle('DANGER ZONE SUMMARY'),
          pw.SizedBox(height: 8),
          pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: [
            _pdfHeader(['Zone Type', 'Count', 'Severity', 'Risk Level']),
            _pdfRow(['Risky Turns', '${j.riskyTurns}', 'High', j.riskyTurns > 2 ? '🔴 Critical' : j.riskyTurns > 0 ? '🟠 Caution' : '✓ None']),
            _pdfRow(['Sharp Turns', '${j.sharpTurns}', 'Medium', j.sharpTurns > 5 ? '🟠 Frequent' : j.sharpTurns > 0 ? '⚠ Monitor' : '✓ None']),
            _pdfRow(['Sudden/Harsh Brakes', '${j.suddenBrakes}', 'Medium-High', j.suddenBrakes > 3 ? '🔴 High' : j.suddenBrakes > 0 ? '⚠ Caution' : '✓ None']),
            _pdfRow(['EEG Stress Peaks', '${j.stressPeakCount}', 'Physiological', j.stressPeakCount > 2 ? '🟣 Elevated' : j.stressPeakCount > 0 ? '⚠ Monitor' : '✓ Normal']),
            _pdfRow(['Critical Multi-Events', '${j.criticalEvents.length}', 'Very High', j.criticalEvents.isNotEmpty ? '🚨 Action Required' : '✓ None']),
          ]),

          // Detailed event log
          if (j.turnEvents.isNotEmpty || j.brakeEvents.isNotEmpty || j.stressPeaks.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _pdfTitle('DETAILED EVENT LOG WITH GPS COORDINATES'),
            pw.SizedBox(height: 8),
            pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: [
              _pdfHeader(['Time', 'Event Type', 'GPS Location', 'Reading', 'Severity']),
              ...j.turnEvents.map((e) => _pdfRow([
                DateFormat('HH:mm:ss').format(e.timestamp),
                e.severity == 'risky' ? 'Risky Turn' : 'Sharp Turn',
                '${e.latitude.toStringAsFixed(5)}, ${e.longitude.toStringAsFixed(5)}',
                '${e.turnRate.abs().toStringAsFixed(1)}°/s',
                e.severity == 'risky' ? '🔴 HIGH' : '🟠 MED',
              ])),
              ...j.brakeEvents.map((e) => _pdfRow([
                DateFormat('HH:mm:ss').format(e.timestamp),
                '${e.severity == 'harsh' ? 'Harsh' : 'Sudden'} Brake',
                '${e.latitude.toStringAsFixed(5)}, ${e.longitude.toStringAsFixed(5)}',
                '${e.deceleration.toStringAsFixed(1)} m/s²',
                e.severity == 'harsh' ? '🟡 HIGH' : '🟡 MED',
              ])),
              ...j.stressPeaks.map((e) => _pdfRow([
                DateFormat('HH:mm:ss').format(e.timestamp),
                'EEG Stress Peak',
                '${e.latitude.toStringAsFixed(5)}, ${e.longitude.toStringAsFixed(5)}',
                '${e.stressLevel}%',
                '🟣 ELEVATED',
              ])),
            ]),
          ],

          if (j.criticalEvents.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _pdfTitle('CRITICAL MULTI-FACTOR EVENTS'),
            pw.SizedBox(height: 8),
            pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: [
              _pdfHeader(['Time', 'Severity', 'GPS', 'Description', 'Factors']),
              ...j.criticalEvents.map((e) => _pdfRow([
                DateFormat('HH:mm:ss').format(e.timestamp),
                e.severityLabel,
                '${e.latitude.toStringAsFixed(5)}, ${e.longitude.toStringAsFixed(5)}',
                e.description,
                e.factors.join(', '),
              ])),
            ]),
          ],

          if (j.weatherContext != null) ...[
            pw.SizedBox(height: 20),
            _pdfTitle('WEATHER CONDITIONS'),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(color: PdfColors.blue50, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('${j.weatherContext!.condition} — ${j.weatherContext!.description}'),
                pw.Text('Temp: ${j.weatherContext!.temperature.toStringAsFixed(1)}°C  |  Humidity: ${j.weatherContext!.humidity.toStringAsFixed(0)}%'),
                pw.Text('Wind: ${j.weatherContext!.windSpeed.toStringAsFixed(1)} km/h  |  Visibility: ${j.weatherContext!.visibility.toStringAsFixed(1)} km'),
                if (j.weatherContext!.isAdverseWeather)
                  pw.Text('⚠ Adverse conditions — risk thresholds auto-reduced by 20%',
                      style: pw.TextStyle(color: PdfColors.orange800)),
              ]),
            ),
          ],

          if (j.recommendations.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _pdfTitle('PERSONALIZED SAFETY RECOMMENDATIONS'),
            pw.SizedBox(height: 8),
            ...j.recommendations.map((r) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('• ', style: const pw.TextStyle(fontSize: 13)),
                pw.Expanded(child: pw.Text(r, style: const pw.TextStyle(fontSize: 12))),
              ]),
            )),
          ],

          pw.SizedBox(height: 28),
          pw.Divider(),
          pw.Text(
            'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}  |  Smart Helmet App  |  IT22608086',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
          ),
        ],
      ));

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/journey_report_${j.id}.pdf');
      await file.writeAsBytes(await pdf.save());
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)],
          subject: 'Journey Report — ${j.destination ?? 'My Ride'}',
          text: 'Score: ${j.riskScore.toStringAsFixed(0)}/100 (${j.riskLabel})'
              '\n${j.riskyTurns} risky turns · ${j.suddenBrakes} brakes · ${j.stressPeakCount} stress peaks');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF export failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  pw.Widget _pdfTitle(String t) => pw.Text(t,
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900));

  pw.TableRow _pdfHeader(List<String> h) => pw.TableRow(
    decoration: const pw.BoxDecoration(color: PdfColors.blue50),
    children: h.map((c) => pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(c, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
    )).toList(),
  );

  pw.TableRow _pdfRow(List<String> c) => pw.TableRow(
    children: c.map((t) => pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(t, style: const pw.TextStyle(fontSize: 8)),
    )).toList(),
  );
}