import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:firebase_database/firebase_database.dart';

// --- BLE UUIDs (MUST match ESP32) ---
final Guid SERVICE_UUID = Guid("4fafc201-1fb5-459e-8fcc-c200c200c200");
final Guid CHARACTERISTIC_UUID = Guid("beb5483e-36e1-4688-b7f5-ea07361b26a8");

// --- Firebase Reference ---
final DatabaseReference databaseRef = FirebaseDatabase.instance.ref('SmartHelmetData');

class Member1Page extends StatefulWidget {
  const Member1Page({super.key});

  @override
  State<Member1Page> createState() => _Member1PageState();
}

class _Member1PageState extends State<Member1Page> {
  // State variables for UI display
  String connectionStatus = "Disconnected";
  double latestHR = 0.0;
  double latestTemp = 0.0;
  String predictionResult = "Awaiting Sensor Data...";
  int _riskLevel = -1; // -1: initial, 0: Low, 1: High
  BluetoothDevice? esp32Device;

  @override
  void initState() {
    super.initState();
    _startBLEScan(); // Start automatic scanning
  }

  @override
  void dispose() {
    esp32Device?.disconnect(); // Clean up BLE connection
    super.dispose();
  }
  
  // =================================================================
  // 1. BLE CLIENT LOGIC (Scan, Connect, Subscribe)
  // =================================================================
  void _startBLEScan() async {
    setState(() => connectionStatus = "Scanning for SmartHelmet_ESP32...");
    
    FlutterBluePlus.scan(timeout: const Duration(seconds: 5)).listen(
      (scanResult) {
        // Find the device by its advertised name
        if (scanResult.device.platformName == "SmartHelmet_ESP32") {
          FlutterBluePlus.stopScan();
          esp32Device = scanResult.device;
          _connectToDevice(esp32Device!);
        }
      },
      onDone: () {
        if (esp32Device == null) {
          setState(() => connectionStatus = "Device not found. Retrying...");
          _startBLEScan(); 
        }
      }
    );
  }

  void _connectToDevice(BluetoothDevice device) async {
    setState(() => connectionStatus = "Connecting...");
    try {
      await device.connect();
      device.cancelWhenDisconnected(() {
        setState(() => connectionStatus = "Disconnected. Retrying scan...");
        _startBLEScan(); 
      });
      setState(() => connectionStatus = "Connected. Discovering services...");
      _discoverServices(device);
    } catch (e) {
      setState(() => connectionStatus = "Connection failed: $e");
      device.disconnect();
    }
  }

  void _discoverServices(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid == SERVICE_UUID) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == CHARACTERISTIC_UUID) {
              await characteristic.setNotifyValue(true);
              
              // Listen to the data stream (Notifications) from the ESP32
              characteristic.lastValueStream.listen(_processBLEData);
              
              setState(() => connectionStatus = "Subscribed to live data.");
              return;
            }
          }
        }
      }
      setState(() => connectionStatus = "Service/Characteristic not found.");
    } catch (e) {
      setState(() => connectionStatus = "Service discovery failed: $e");
    }
  }
  
  // =================================================================
  // 2. DATA PROCESSING, PREDICTION, AND FIREBASE UPLOAD
  // =================================================================
  void _processBLEData(List<int> value) {
    if (value.isEmpty) return;
    
    String jsonString = utf8.decode(value); 
    
    try {
      // Decode the JSON sent by ESP32: {"hr": X, "temp": Y}
      Map<String, dynamic> data = jsonDecode(jsonString);
      double hr = data['hr'] ?? 0.0;
      double temp = data['temp'] ?? 0.0;

      // Run Prediction based on the sensor data
      int risk = _runPredictionModel(hr, temp); 
      
      // Update UI with new data and prediction
      setState(() {
        latestHR = hr;
        latestTemp = temp;
        _riskLevel = risk;
        predictionResult = risk == 1 
            ? "⚠️ HIGH RISK ALERT" 
            : "✅ Low Risk";
      });

      // Upload data (with prediction) to Firebase
      _sendDataToFirebase(hr, temp, risk);

    } catch (e) {
      print("JSON Decoding Error: $e");
    }
  }

  // --- LOCAL ML PREDICTION LOGIC ---
  // This logic is based on the rule used to create your model's labels:
  // Risk = 1 if (Heart Rate > 100) AND (Body Temperature > 38)
  int _runPredictionModel(double hr, double temp) {
    if (hr > 100.0 && temp > 38.0) {
      return 1; // High Risk
    } else {
      return 0; // Low Risk
    }
  }

  void _sendDataToFirebase(double hr, double temp, int risk) {
    final currentTime = DateTime.now().toUtc().toIso8601String(); 
    
    databaseRef.push().set({
      'timestamp': currentTime,
      'heart_rate': hr,
      'body_temperature': temp,
      'predicted_risk': risk, 
    }).then((_) {
      // print("Data and Prediction sent to Firebase.");
    }).catchError((error) {
      print("Firebase Error: $error");
    });
  }

  // =================================================================
  // 3. UI BUILDER (The Member1 Dashboard)
  // =================================================================
  @override
  Widget build(BuildContext context) {
    Color predictionColor;
    if (_riskLevel == 1) {
        predictionColor = Colors.red.shade700;
    } else if (_riskLevel == 0) {
        predictionColor = Colors.green.shade600;
    } else {
        predictionColor = Colors.grey;
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Member 1 - Smart Helmet Monitoring'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // --- 3.1. Connection Status ---
            _buildStatusCard('Bluetooth Connection', connectionStatus, Colors.blue),
            const SizedBox(height: 16),
            
            // --- 3.2. Prediction Result ---
            _buildPredictionCard(predictionResult, predictionColor),
            const SizedBox(height: 24),
            
            // --- 3.3. Sensor Data Display ---
            const Text('Live Sensor Readings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            
            Row(
              children: [
                Expanded(child: _buildDataCard('Heart Rate (BPM)', latestHR.toStringAsFixed(1), Icons.favorite, Colors.red)),
                const SizedBox(width: 16),
                Expanded(child: _buildDataCard('Temp (°C)', latestTemp.toStringAsFixed(1), Icons.thermostat, Colors.orange)),
              ],
            ),
            
            const SizedBox(height: 40),
            const Text(
              'Disclaimer: This app provides a simplified risk assessment based on sensor data and should NOT be used for clinical diagnosis.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  // Helper function for Connection Status
  Widget _buildStatusCard(String title, String value, Color color) {
    return Card(
      elevation: 4,
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(value, style: TextStyle(fontSize: 14, color: color)),
        leading: Icon(Icons.bluetooth_connected, color: color),
      ),
    );
  }

  // Helper function for Prediction Result
  Widget _buildPredictionCard(String result, Color color) {
    return Card(
      elevation: 6,
      color: color.withOpacity(0.8),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(color == Colors.red.shade700 ? Icons.warning_amber : Icons.health_and_safety, 
                 size: 40, color: Colors.white),
            const SizedBox(height: 10),
            Text(
              'Risk Analysis:',
              style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.8)),
            ),
            Text(
              result,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  // Helper function for Sensor Data
  Widget _buildDataCard(String title, String value, IconData icon, Color iconColor) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 30),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}