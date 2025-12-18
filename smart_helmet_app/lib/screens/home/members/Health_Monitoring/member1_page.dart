import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:firebase_database/firebase_database.dart';

// --- BLE UUIDs ---
final Guid SERVICE_UUID = Guid("4fafc201-1fb5-459e-8fcc-c200c200c200");
final Guid CHARACTERISTIC_UUID = Guid("beb5483e-36e1-4688-b7f5-ea07361b26a8");

// Firebase reference
final databaseRef = FirebaseDatabase.instance.ref("SmartHelmetData");

class Member1Page extends StatefulWidget {
  const Member1Page({super.key});

  @override
  State<Member1Page> createState() => _Member1PageState();
}

class _Member1PageState extends State<Member1Page> {
  String connectionStatus = "Disconnected";
  double latestHR = 0.0;
  double latestTemp = 0.0;
  String predictionResult = "Awaiting Sensor Data...";
  int _riskLevel = -1;

  BluetoothDevice? esp32Device;
  StreamSubscription<List<ScanResult>>? scanSub;
  StreamSubscription<List<int>>? notifySub;
  StreamSubscription<BluetoothConnectionState>? disconnectSub;

  @override
  void initState() {
    super.initState();
    _startBLEScan();
  }

  @override
  void dispose() {
    scanSub?.cancel();
    notifySub?.cancel();
    disconnectSub?.cancel();
    esp32Device?.disconnect();
    super.dispose();
  }

  // ==============================
  // SCAN FOR DEVICE
  // ==============================
  void _startBLEScan() {
    setState(() => connectionStatus = "Scanning...");

    FlutterBluePlus.startScan();

    scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (var r in results) {
        if (r.device.platformName == "SmartHelmet_ESP32") {
          esp32Device = r.device;
          FlutterBluePlus.stopScan();
          scanSub?.cancel();
          _connectToDevice(esp32Device!);
          break;
        }
      }
    });
  }

  // ==============================
  // CONNECT TO DEVICE
  // ==============================
  void _connectToDevice(BluetoothDevice device) async {
    setState(() => connectionStatus = "Connecting...");

    await device.connect();

    // Handle disconnects
    disconnectSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        setState(() => connectionStatus = "Disconnected. Retrying...");
        _startBLEScan();
      }
    });

    setState(() => connectionStatus = "Discovering services...");
    _discoverServices(device);
  }

  // ==============================
  // DISCOVER + SUBSCRIBE
  // ==============================
  void _discoverServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();

    for (var service in services) {
      if (service.uuid == SERVICE_UUID) {
        for (var char in service.characteristics) {
          if (char.uuid == CHARACTERISTIC_UUID) {
            await char.setNotifyValue(true);

            notifySub = char.lastValueStream.listen(_processBLEData);

            setState(() => connectionStatus = "Connected & Receiving");
            return;
          }
        }
      }
    }

    setState(() => connectionStatus = "Characteristic not found");
  }

  // ==============================
  // PROCESS DATA
  // ==============================
  void _processBLEData(List<int> value) {
    if (value.isEmpty) return;

    String jsonString = utf8.decode(value);

    try {
      Map<String, dynamic> data = jsonDecode(jsonString);
      double hr = (data["hr"] ?? 0).toDouble();
      double temp = (data["temp"] ?? 0).toDouble();

      int risk = _runPredictionModel(hr, temp);

      setState(() {
        latestHR = hr;
        latestTemp = temp;
        _riskLevel = risk;
        predictionResult = (risk == 1)
            ? "⚠️ HIGH RISK"
            : "✅ LOW RISK";
      });

      _sendToFirebase(hr, temp, risk);
    } catch (e) {
      print("JSON error: $e");
    }
  }

  // Simple rule-based prediction
  int _runPredictionModel(double hr, double temp) {
    return (hr > 100 && temp > 38) ? 1 : 0;
  }

  void _sendToFirebase(double hr, double temp, int risk) {
    databaseRef.push().set({
      "timestamp": DateTime.now().toIso8601String(),
      "heart_rate": hr,
      "body_temperature": temp,
      "predicted_risk": risk
    });
  }

  // ==============================
  // UI
  // ==============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Member 1 - Monitoring"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildStatusCard(),
            const SizedBox(height: 20),
            _buildPredictionCard(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _buildDataCard("Heart Rate", latestHR, Icons.favorite, Colors.red)),
                const SizedBox(width: 10),
                Expanded(child: _buildDataCard("Temp (°C)", latestTemp, Icons.thermostat, Colors.orange)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: ListTile(
        title: const Text("Bluetooth Status"),
        subtitle: Text(connectionStatus),
        leading: const Icon(Icons.bluetooth),
      ),
    );
  }

  Widget _buildPredictionCard() {
    Color c = (_riskLevel == 1) ? Colors.red : Colors.green;
    return Card(
      color: c.withOpacity(0.8),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon((_riskLevel == 1) ? Icons.warning : Icons.check_circle,
                size: 40, color: Colors.white),
            const SizedBox(height: 10),
            Text(
              predictionResult,
              style: const TextStyle(fontSize: 24, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataCard(String title, double value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 10),
            Text(title),
            Text(value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
