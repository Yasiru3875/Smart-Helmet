import 'package:flutter/material.dart';
import 'dart:async';
// import 'dart:math';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class Member3Page extends StatefulWidget {
  const Member3Page({super.key});

  @override
  State<Member3Page> createState() => _Member3PageState();
}

class _Member3PageState extends State<Member3Page> {
  // IMU Data from MPU6050
  double gyroX = 0.0;
  double gyroY = 0.0;
  double gyroZ = 0.0;
  double accelX = 0.0;
  double accelY = 0.0;
  double accelZ = 0.0;
  
  // Turn Detection
  int sharpTurnCount = 0;
  int riskyTurnCount = 0;
  String currentTurnStatus = "Normal";
  Color statusColor = Colors.green;
  
  // Historical data for graph
  List<double> gyroZHistory = [];
  final int maxHistoryLength = 50;
  
  // Thresholds (adjust based on calibration)
  final double sharpTurnThreshold = 100.0; // degrees/sec
  final double riskyTurnThreshold = 150.0; // degrees/sec
  
  // BLE Connection
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? imuCharacteristic;
  StreamSubscription? _characteristicSubscription;
  bool isConnected = false;
  bool isScanning = false;
  String connectionStatus = "Disconnected";
  
  // ESP32 BLE Configuration - UPDATE THESE VALUES
  static const String targetDeviceName = "ESP32_IMU"; // Change to your ESP32 device name
  static const String serviceUUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"; // Your service UUID
  static const String characteristicUUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8"; // Your characteristic UUID
  
  @override
  void initState() {
    super.initState();
    _initializeBLE();
  }
  
  @override
  void dispose() {
    _characteristicSubscription?.cancel();
    connectedDevice?.disconnect();
    super.dispose();
  }
  
  // Initialize BLE and check adapter state
  Future<void> _initializeBLE() async {
    // Check if Bluetooth is supported
    if (await FlutterBluePlus.isSupported == false) {
      setState(() {
        connectionStatus = "BLE not supported";
      });
      return;
    }
    
    // Listen to Bluetooth adapter state
    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        // Bluetooth is on, ready to scan
      } else {
        setState(() {
          connectionStatus = "Turn on Bluetooth";
        });
      }
    });
  }
  
  // Scan for ESP32 device
  Future<void> _scanAndConnect() async {
    setState(() {
      isScanning = true;
      connectionStatus = "Scanning...";
    });
    
    try {
      // Start scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      
      // Listen to scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          // Find device by name
          if (result.device.platformName == targetDeviceName) {
            FlutterBluePlus.stopScan();
            _connectToDevice(result.device);
            break;
          }
        }
      });
      
      // Stop scanning after timeout
      await Future.delayed(const Duration(seconds: 10));
      await FlutterBluePlus.stopScan();
      
      if (!isConnected) {
        setState(() {
          connectionStatus = "Device not found";
          isScanning = false;
        });
      }
    } catch (e) {
      setState(() {
        connectionStatus = "Scan error: $e";
        isScanning = false;
      });
    }
  }
  
  // Connect to the ESP32 device
  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      connectionStatus = "Connecting...";
    });
    
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      
      setState(() {
        connectedDevice = device;
        isConnected = true;
        connectionStatus = "Connected";
        isScanning = false;
      });
      
      // Discover services
      await _discoverServices();
      
    } catch (e) {
      setState(() {
        connectionStatus = "Connection failed: $e";
        isConnected = false;
        isScanning = false;
      });
    }
  }
  
  // Discover services and characteristics
  Future<void> _discoverServices() async {
    if (connectedDevice == null) return;
    
    try {
      List<BluetoothService> services = await connectedDevice!.discoverServices();
      
      for (BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() == characteristicUUID.toLowerCase()) {
              imuCharacteristic = characteristic;
              await _subscribeToIMUData();
              return;
            }
          }
        }
      }
      
      setState(() {
        connectionStatus = "IMU service not found";
      });
    } catch (e) {
      setState(() {
        connectionStatus = "Service discovery error: $e";
      });
    }
  }
  
  // Subscribe to IMU data notifications
  Future<void> _subscribeToIMUData() async {
    if (imuCharacteristic == null) return;
    
    try {
      // Enable notifications
      await imuCharacteristic!.setNotifyValue(true);
      
      // Listen to characteristic updates
      _characteristicSubscription = imuCharacteristic!.lastValueStream.listen((value) {
        _parseIMUData(value);
      });
      
      setState(() {
        connectionStatus = "Receiving data";
      });
    } catch (e) {
      setState(() {
        connectionStatus = "Subscription error: $e";
      });
    }
  }
  
  // Parse incoming BLE data
  void _parseIMUData(List<int> value) {
    try {
      // Convert bytes to string and parse JSON
      String jsonString = utf8.decode(value);
      Map<String, dynamic> data = json.decode(jsonString);
      
      // Process the data
      _processIMUData({
        'gyroX': (data['gyroX'] ?? 0.0).toDouble(),
        'gyroY': (data['gyroY'] ?? 0.0).toDouble(),
        'gyroZ': (data['gyroZ'] ?? 0.0).toDouble(),
        'accelX': (data['accelX'] ?? 0.0).toDouble(),
        'accelY': (data['accelY'] ?? 0.0).toDouble(),
        'accelZ': (data['accelZ'] ?? 0.0).toDouble(),
      });
    } catch (e) {
      print('Error parsing IMU data: $e');
    }
  }
  
  // Disconnect from device
  Future<void> _disconnect() async {
    if (connectedDevice != null) {
      await _characteristicSubscription?.cancel();
      await connectedDevice!.disconnect();
      
      setState(() {
        connectedDevice = null;
        imuCharacteristic = null;
        isConnected = false;
        connectionStatus = "Disconnected";
      });
    }
  }
  
  void _processIMUData(Map<String, double> data) {
    setState(() {
      gyroX = data['gyroX']!;
      gyroY = data['gyroY']!;
      gyroZ = data['gyroZ']!;
      accelX = data['accelX']!;
      accelY = data['accelY']!;
      accelZ = data['accelZ']!;
      
      // Add to history
      gyroZHistory.add(gyroZ.abs());
      if (gyroZHistory.length > maxHistoryLength) {
        gyroZHistory.removeAt(0);
      }
      
      // Detect turn severity
      double turnRate = gyroZ.abs();
      
      if (turnRate > riskyTurnThreshold) {
        currentTurnStatus = "RISKY TURN!";
        statusColor = Colors.red;
        riskyTurnCount++;
      } else if (turnRate > sharpTurnThreshold) {
        currentTurnStatus = "Sharp Turn";
        statusColor = Colors.orange;
        sharpTurnCount++;
      } else {
        currentTurnStatus = "Normal";
        statusColor = Colors.green;
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sharp Turn Detection'),
        backgroundColor: Colors.blue[700],
        actions: [
          IconButton(
            icon: Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
            onPressed: isConnected ? _disconnect : _scanAndConnect,
            tooltip: isConnected ? 'Disconnect' : 'Connect',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection Status Card
            _buildConnectionCard(),
            const SizedBox(height: 16),
            
            // Status Card
            _buildStatusCard(),
            const SizedBox(height: 16),
            
            // Statistics
            _buildStatisticsRow(),
            const SizedBox(height: 16),
            
            // Live Gyroscope Data
            _buildGyroscopeCard(),
            const SizedBox(height: 16),
            
            // Accelerometer Data
            _buildAccelerometerCard(),
            const SizedBox(height: 16),
            
            // Turn Rate Graph
            _buildTurnRateGraph(),
            const SizedBox(height: 16),
            
            // Reset Button
            ElevatedButton.icon(
              onPressed: _resetCounters,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset Counters'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildConnectionCard() {
    return Card(
      color: isConnected ? Colors.green[50] : Colors.grey[100],
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: isConnected ? Colors.green : Colors.grey,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ESP32 Connection',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          connectionStatus,
                          style: TextStyle(
                            fontSize: 14,
                            color: isConnected ? Colors.green : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (!isConnected && !isScanning)
                  ElevatedButton.icon(
                    onPressed: _scanAndConnect,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (!isConnected && !isScanning)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Device name: $targetDeviceName',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusCard() {
    return Card(
      color: statusColor.withOpacity(0.2),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              _getStatusIcon(),
              size: 48,
              color: statusColor,
            ),
            const SizedBox(height: 12),
            Text(
              currentTurnStatus,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Turn Rate: ${gyroZ.abs().toStringAsFixed(1)}°/s',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
  
  IconData _getStatusIcon() {
    if (currentTurnStatus == "RISKY TURN!") return Icons.warning_amber;
    if (currentTurnStatus == "Sharp Turn") return Icons.turn_sharp_right;
    return Icons.check_circle;
  }
  
  Widget _buildStatisticsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Sharp Turns',
            sharpTurnCount.toString(),
            Icons.turn_right,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            'Risky Turns',
            riskyTurnCount.toString(),
            Icons.warning,
            Colors.red,
          ),
        ),
      ],
    );
  }
  
  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildGyroscopeCard() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gyroscope (°/s)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildDataRow('X-axis (Roll)', gyroX, Colors.red),
            _buildDataRow('Y-axis (Pitch)', gyroY, Colors.green),
            _buildDataRow('Z-axis (Yaw)', gyroZ, Colors.blue),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAccelerometerCard() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Accelerometer (m/s²)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildDataRow('X-axis', accelX, Colors.red),
            _buildDataRow('Y-axis', accelY, Colors.green),
            _buildDataRow('Z-axis', accelZ, Colors.blue),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDataRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Row(
            children: [
              Container(
                width: 100,
                height: 20,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FractionallySizedBox(
                  widthFactor: (value.abs() / 200).clamp(0.0, 1.0),
                  alignment: Alignment.centerLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: Text(
                  value.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildTurnRateGraph() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Turn Rate History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: CustomPaint(
                size: Size.infinite,
                painter: GraphPainter(
                  data: gyroZHistory,
                  sharpThreshold: sharpTurnThreshold,
                  riskyThreshold: riskyTurnThreshold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegend('Normal', Colors.green),
                const SizedBox(width: 12),
                _buildLegend('Sharp', Colors.orange),
                const SizedBox(width: 12),
                _buildLegend('Risky', Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLegend(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 3,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
  
  void _resetCounters() {
    setState(() {
      sharpTurnCount = 0;
      riskyTurnCount = 0;
      gyroZHistory.clear();
    });
  }
}

// Custom painter for the turn rate graph
class GraphPainter extends CustomPainter {
  final List<double> data;
  final double sharpThreshold;
  final double riskyThreshold;
  
  GraphPainter({
    required this.data,
    required this.sharpThreshold,
    required this.riskyThreshold,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    // Draw threshold lines
    final sharpPaint = Paint()
      ..color = Colors.orange.withOpacity(0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    final riskyPaint = Paint()
      ..color = Colors.red.withOpacity(0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    double sharpY = size.height - (sharpThreshold / 200 * size.height);
    double riskyY = size.height - (riskyThreshold / 200 * size.height);
    
    canvas.drawLine(Offset(0, sharpY), Offset(size.width, sharpY), sharpPaint);
    canvas.drawLine(Offset(0, riskyY), Offset(size.width, riskyY), riskyPaint);
    
    // Draw data line
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    final path = Path();
    
    for (int i = 0; i < data.length; i++) {
      double x = (i / (data.length - 1)) * size.width;
      double y = size.height - (data[i].clamp(0, 200) / 200 * size.height);
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(GraphPainter oldDelegate) => true;
}