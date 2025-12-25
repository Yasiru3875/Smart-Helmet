// import 'package:flutter/material.dart';
// import 'dart:async';
// import 'dart:convert';
// import 'dart:typed_data';
// import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
// import 'package:permission_handler/permission_handler.dart';

// class Member3Page extends StatefulWidget {
//   const Member3Page({super.key});

//   @override
//   State<Member3Page> createState() => _Member3PageState();
// }

// class _Member3PageState extends State<Member3Page> {
//   // IMU Data from MPU6050
//   double gyroX = 0.0;
//   double gyroY = 0.0;
//   double gyroZ = 0.0;
//   double accelX = 0.0;
//   double accelY = 0.0;
//   double accelZ = 0.0;

//   // Turn Detection
//   int sharpTurnCount = 0;
//   int riskyTurnCount = 0;
//   String currentTurnStatus = "Normal";
//   Color statusColor = Colors.green;

//   // Historical data for graph
//   List<double> gyroZHistory = [];
//   final int maxHistoryLength = 50;

//   // Thresholds (adjust based on calibration)
//   final double sharpTurnThreshold = 100.0; // degrees/sec
//   final double riskyTurnThreshold = 150.0; // degrees/sec

//   // Bluetooth Classic Connection
//   BluetoothConnection? _connection;
//   bool isConnected = false;
//   bool isConnecting = false;
//   String connectionStatus = "Disconnected";
//   String _dataBuffer = "";

//   // ESP32 Configuration
//   static const String targetDeviceName = "SmartHelmet_ESP32";

//   @override
//   void initState() {
//     super.initState();
//     _requestPermissions();
//   }

//   @override
//   void dispose() {
//     _disconnect();
//     super.dispose();
//   }

//   // Request Bluetooth permissions
//   Future<void> _requestPermissions() async {
//     await [
//       Permission.bluetooth,
//       Permission.bluetoothConnect,
//       Permission.bluetoothScan,
//       Permission.location,
//     ].request();
//   }

//   // Scan and connect to device
//   Future<void> _scanAndConnect() async {
//     if (!mounted) return;
//     setState(() {
//       isConnecting = true;
//       connectionStatus = "Scanning...";
//     });

//     try {
//       // Get bonded (paired) devices
//       List<BluetoothDevice> bondedDevices =
//           await FlutterBluetoothSerial.instance.getBondedDevices();

//       // Find target device
//       BluetoothDevice? targetDevice;
//       for (BluetoothDevice device in bondedDevices) {
//         if (device.name == targetDeviceName) {
//           targetDevice = device;
//           break;
//         }
//       }

//       if (targetDevice == null) {
//         if (!mounted) return;
//         setState(() {
//           connectionStatus = "Device not paired. Pair '$targetDeviceName' in Bluetooth settings.";
//           isConnecting = false;
//         });
//         return;
//       }

//       // Connect to device
//       if (!mounted) return;
//       setState(() {
//         connectionStatus = "Connecting...";
//       });

//       BluetoothConnection connection =
//           await BluetoothConnection.toAddress(targetDevice.address);

//       if (!mounted) return;
//       setState(() {
//         _connection = connection;
//         isConnected = true;
//         isConnecting = false;
//         connectionStatus = "Connected";
//       });

//       // Listen to incoming data
//       _connection!.input!.listen((Uint8List data) {
//         _handleIncomingData(data);
//       }).onDone(() {
//         if (mounted) {
//           setState(() {
//             isConnected = false;
//             connectionStatus = "Disconnected";
//           });
//         }
//       });
//     } catch (e) {
//       if (!mounted) return;
//       setState(() {
//         connectionStatus = "Connection failed: $e";
//         isConnected = false;
//         isConnecting = false;
//       });
//     }
//   }

//   // Handle incoming Bluetooth data
//   void _handleIncomingData(Uint8List data) {
//     // Add new data to buffer
//     _dataBuffer += utf8.decode(data);

//     // Process complete JSON messages (ending with newline)
//     while (_dataBuffer.contains('\n')) {
//       int newlineIndex = _dataBuffer.indexOf('\n');
//       String jsonString = _dataBuffer.substring(0, newlineIndex).trim();
//       _dataBuffer = _dataBuffer.substring(newlineIndex + 1);

//       if (jsonString.isNotEmpty) {
//         _parseIMUData(jsonString);
//       }
//     }
//   }

//   // Parse incoming JSON data
//   void _parseIMUData(String jsonString) {
//     try {
//       Map<String, dynamic> data = json.decode(jsonString);

//       _processIMUData({
//         'gyroX': (data['gyroX'] ?? 0.0).toDouble(),
//         'gyroY': (data['gyroY'] ?? 0.0).toDouble(),
//         'gyroZ': (data['gyroZ'] ?? 0.0).toDouble(),
//         'accelX': (data['accelX'] ?? 0.0).toDouble(),
//         'accelY': (data['accelY'] ?? 0.0).toDouble(),
//         'accelZ': (data['accelZ'] ?? 0.0).toDouble(),
//       });
//     } catch (e) {
//       print('Error parsing IMU data: $e');
//     }
//   }

//   // Disconnect from device
//   Future<void> _disconnect() async {
//     try {
//       await _connection?.finish();
//     } catch (e) {
//       print('Disconnect error: $e');
//     }

//     if (!mounted) return;
//     setState(() {
//       _connection = null;
//       isConnected = false;
//       connectionStatus = "Disconnected";
//     });
//   }

//   void _processIMUData(Map<String, double> data) {
//     if (!mounted) return;
//     setState(() {
//       gyroX = data['gyroX']!;
//       gyroY = data['gyroY']!;
//       gyroZ = data['gyroZ']!;
//       accelX = data['accelX']!;
//       accelY = data['accelY']!;
//       accelZ = data['accelZ']!;

//       // Add to history
//       gyroZHistory.add(gyroZ.abs());
//       if (gyroZHistory.length > maxHistoryLength) {
//         gyroZHistory.removeAt(0);
//       }

//       // Detect turn severity
//       double turnRate = gyroZ.abs();

//       if (turnRate > riskyTurnThreshold) {
//         currentTurnStatus = "RISKY TURN!";
//         statusColor = Colors.red;
//         riskyTurnCount++;
//       } else if (turnRate > sharpTurnThreshold) {
//         currentTurnStatus = "Sharp Turn";
//         statusColor = Colors.orange;
//         sharpTurnCount++;
//       } else {
//         currentTurnStatus = "Normal";
//         statusColor = Colors.green;
//       }
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Sharp Turn Detection'),
//         backgroundColor: Colors.blue[700],
//         actions: [
//           IconButton(
//             icon: Icon(
//               isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
//             ),
//             onPressed: isConnected ? _disconnect : _scanAndConnect,
//             tooltip: isConnected ? 'Disconnect' : 'Connect',
//           ),
//         ],
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             // Connection Status Card
//             _buildConnectionCard(),
//             const SizedBox(height: 16),

//             // Status Card
//             _buildStatusCard(),
//             const SizedBox(height: 16),

//             // Statistics
//             _buildStatisticsRow(),
//             const SizedBox(height: 16),

//             // Live Gyroscope Data
//             _buildGyroscopeCard(),
//             const SizedBox(height: 16),

//             // Accelerometer Data
//             _buildAccelerometerCard(),
//             const SizedBox(height: 16),

//             // Turn Rate Graph
//             _buildTurnRateGraph(),
//             const SizedBox(height: 16),

//             // Reset Button
//             ElevatedButton.icon(
//               onPressed: _resetCounters,
//               icon: const Icon(Icons.refresh),
//               label: const Text('Reset Counters'),
//               style: ElevatedButton.styleFrom(
//                 padding: const EdgeInsets.all(16),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildConnectionCard() {
//     return Card(
//       color: isConnected ? Colors.green[50] : Colors.grey[100],
//       elevation: 4,
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           children: [
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Flexible(
//                   child: Row(
//                     children: [
//                       Icon(
//                         isConnected
//                             ? Icons.bluetooth_connected
//                             : Icons.bluetooth_disabled,
//                         color: isConnected ? Colors.green : Colors.grey,
//                         size: 28,
//                       ),
//                       const SizedBox(width: 12),
//                       Flexible(
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             const Text(
//                               'ESP32 Connection',
//                               style: TextStyle(
//                                 fontSize: 16,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                             Text(
//                               connectionStatus,
//                               style: TextStyle(
//                                 fontSize: 14,
//                                 color: isConnected
//                                     ? Colors.green
//                                     : Colors.grey[700],
//                               ),
//                               overflow: TextOverflow.ellipsis,
//                             ),
//                           ],
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//                 if (!isConnected && !isConnecting)
//                   ElevatedButton.icon(
//                     onPressed: _scanAndConnect,
//                     icon: const Icon(Icons.search, size: 18),
//                     label: const Text('Connect'),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.blue,
//                       foregroundColor: Colors.white,
//                     ),
//                   ),
//                 if (isConnecting)
//                   const SizedBox(
//                     width: 20,
//                     height: 20,
//                     child: CircularProgressIndicator(strokeWidth: 2),
//                   ),
//               ],
//             ),
//             if (!isConnected && !isConnecting)
//               Padding(
//                 padding: const EdgeInsets.only(top: 12),
//                 child: Text(
//                   'Device name: $targetDeviceName\n(Pair in Bluetooth settings first)',
//                   style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//                   textAlign: TextAlign.center,
//                 ),
//               ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildStatusCard() {
//     return Card(
//       color: statusColor.withOpacity(0.2),
//       elevation: 4,
//       child: Padding(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           children: [
//             Icon(_getStatusIcon(), size: 48, color: statusColor),
//             const SizedBox(height: 12),
//             Text(
//               currentTurnStatus,
//               style: TextStyle(
//                 fontSize: 24,
//                 fontWeight: FontWeight.bold,
//                 color: statusColor,
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               'Turn Rate: ${gyroZ.abs().toStringAsFixed(1)}°/s',
//               style: const TextStyle(fontSize: 16),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   IconData _getStatusIcon() {
//     if (currentTurnStatus == "RISKY TURN!") return Icons.warning_amber;
//     if (currentTurnStatus == "Sharp Turn") return Icons.turn_sharp_right;
//     return Icons.check_circle;
//   }

//   Widget _buildStatisticsRow() {
//     return Row(
//       children: [
//         Expanded(
//           child: _buildStatCard(
//             'Sharp Turns',
//             sharpTurnCount.toString(),
//             Icons.turn_right,
//             Colors.orange,
//           ),
//         ),
//         const SizedBox(width: 16),
//         Expanded(
//           child: _buildStatCard(
//             'Risky Turns',
//             riskyTurnCount.toString(),
//             Icons.warning,
//             Colors.red,
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildStatCard(
//     String label,
//     String value,
//     IconData icon,
//     Color color,
//   ) {
//     return Card(
//       elevation: 3,
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           children: [
//             Icon(icon, size: 32, color: color),
//             const SizedBox(height: 8),
//             Text(
//               value,
//               style: TextStyle(
//                 fontSize: 28,
//                 fontWeight: FontWeight.bold,
//                 color: color,
//               ),
//             ),
//             Text(
//               label,
//               style: const TextStyle(fontSize: 14),
//               textAlign: TextAlign.center,
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildGyroscopeCard() {
//     return Card(
//       elevation: 3,
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Text(
//               'Gyroscope (°/s)',
//               style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//             ),
//             const SizedBox(height: 12),
//             _buildDataRow('X-axis (Roll)', gyroX, Colors.red),
//             _buildDataRow('Y-axis (Pitch)', gyroY, Colors.green),
//             _buildDataRow('Z-axis (Yaw)', gyroZ, Colors.blue),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildAccelerometerCard() {
//     return Card(
//       elevation: 3,
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Text(
//               'Accelerometer (m/s²)',
//               style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//             ),
//             const SizedBox(height: 12),
//             _buildDataRow('X-axis', accelX, Colors.red),
//             _buildDataRow('Y-axis', accelY, Colors.green),
//             _buildDataRow('Z-axis', accelZ, Colors.blue),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildDataRow(String label, double value, Color color) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 4),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           Text(label, style: const TextStyle(fontSize: 16)),
//           Row(
//             children: [
//               Container(
//                 width: 100,
//                 height: 20,
//                 decoration: BoxDecoration(
//                   color: color.withOpacity(0.2),
//                   borderRadius: BorderRadius.circular(4),
//                 ),
//                 child: FractionallySizedBox(
//                   widthFactor: (value.abs() / 200).clamp(0.0, 1.0),
//                   alignment: Alignment.centerLeft,
//                   child: Container(
//                     decoration: BoxDecoration(
//                       color: color,
//                       borderRadius: BorderRadius.circular(4),
//                     ),
//                   ),
//                 ),
//               ),
//               const SizedBox(width: 8),
//               SizedBox(
//                 width: 70,
//                 child: Text(
//                   value.toStringAsFixed(2),
//                   style: TextStyle(
//                     fontSize: 16,
//                     fontWeight: FontWeight.bold,
//                     color: color,
//                   ),
//                   textAlign: TextAlign.right,
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildTurnRateGraph() {
//     return Card(
//       elevation: 3,
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Text(
//               'Turn Rate History',
//               style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//             ),
//             const SizedBox(height: 12),
//             SizedBox(
//               height: 150,
//               child: CustomPaint(
//                 size: Size.infinite,
//                 painter: GraphPainter(
//                   data: gyroZHistory,
//                   sharpThreshold: sharpTurnThreshold,
//                   riskyThreshold: riskyTurnThreshold,
//                 ),
//               ),
//             ),
//             const SizedBox(height: 8),
//             Row(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 _buildLegend('Normal', Colors.green),
//                 const SizedBox(width: 12),
//                 _buildLegend('Sharp', Colors.orange),
//                 const SizedBox(width: 12),
//                 _buildLegend('Risky', Colors.red),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildLegend(String label, Color color) {
//     return Row(
//       children: [
//         Container(width: 16, height: 3, color: color),
//         const SizedBox(width: 4),
//         Text(label, style: const TextStyle(fontSize: 12)),
//       ],
//     );
//   }

//   void _resetCounters() {
//     setState(() {
//       sharpTurnCount = 0;
//       riskyTurnCount = 0;
//       gyroZHistory.clear();
//     });
//   }
// }

// // Custom painter for the turn rate graph
// class GraphPainter extends CustomPainter {
//   final List<double> data;
//   final double sharpThreshold;
//   final double riskyThreshold;

//   GraphPainter({
//     required this.data,
//     required this.sharpThreshold,
//     required this.riskyThreshold,
//   });

//   @override
//   void paint(Canvas canvas, Size size) {
//     if (data.isEmpty) return;

//     // Draw threshold lines
//     final sharpPaint = Paint()
//       ..color = Colors.orange.withOpacity(0.3)
//       ..strokeWidth = 2
//       ..style = PaintingStyle.stroke;

//     final riskyPaint = Paint()
//       ..color = Colors.red.withOpacity(0.3)
//       ..strokeWidth = 2
//       ..style = PaintingStyle.stroke;

//     double sharpY = size.height - (sharpThreshold / 200 * size.height);
//     double riskyY = size.height - (riskyThreshold / 200 * size.height);

//     canvas.drawLine(Offset(0, sharpY), Offset(size.width, sharpY), sharpPaint);
//     canvas.drawLine(Offset(0, riskyY), Offset(size.width, riskyY), riskyPaint);

//     // Draw data line
//     final paint = Paint()
//       ..color = Colors.blue
//       ..strokeWidth = 2
//       ..style = PaintingStyle.stroke;

//     final path = Path();

//     for (int i = 0; i < data.length; i++) {
//       double x = (i / (data.length - 1)) * size.width;
//       double y = size.height - (data[i].clamp(0, 200) / 200 * size.height);

//       if (i == 0) {
//         path.moveTo(x, y);
//       } else {
//         path.lineTo(x, y);
//       }
//     }

//     canvas.drawPath(path, paint);
//   }

//   @override
//   bool shouldRepaint(GraphPainter oldDelegate) => true;
// }


import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:smart_helmet_app/models/journey_model.dart';
import 'package:smart_helmet_app/providers/journey_provider.dart';
import 'package:smart_helmet_app/services/journey_service.dart';

class Member3Page extends StatefulWidget {
  const Member3Page({super.key});

  @override
  State<Member3Page> createState() => _Member3PageState();
}

class _Member3PageState extends State<Member3Page> with SingleTickerProviderStateMixin {
  // Tab controller
  late TabController _tabController;
  
  // Journey Service
  final JourneyService _journeyService = JourneyService();
  List<JourneyData> _journeyHistory = [];
  JourneyData? _selectedJourney;
  bool _isLoadingHistory = false;
  
  // IMU Data from MPU6050 (Live Monitoring)
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

  // Thresholds
  final double sharpTurnThreshold = 100.0;
  final double riskyTurnThreshold = 150.0;

  // Bluetooth Connection
  BluetoothConnection? _connection;
  bool isConnected = false;
  bool isConnecting = false;
  String connectionStatus = "Disconnected";
  String _dataBuffer = "";
  static const String targetDeviceName = "SmartHelmet_ESP32";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _requestPermissions();
    _loadJourneyHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _disconnect();
    super.dispose();
  }

  // Load journey history from Firebase
  Future<void> _loadJourneyHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final journeys = await _journeyService.getAllJourneys();
      setState(() {
        _journeyHistory = journeys;
        _isLoadingHistory = false;
      });
    } catch (e) {
      setState(() => _isLoadingHistory = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading journeys: $e')),
        );
      }
    }
  }

  // Request Bluetooth permissions
  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
  }

  // Scan and connect to device
  Future<void> _scanAndConnect() async {
    if (!mounted) return;
    setState(() {
      isConnecting = true;
      connectionStatus = "Scanning...";
    });

    try {
      List<BluetoothDevice> bondedDevices =
          await FlutterBluetoothSerial.instance.getBondedDevices();

      BluetoothDevice? targetDevice;
      for (BluetoothDevice device in bondedDevices) {
        if (device.name == targetDeviceName) {
          targetDevice = device;
          break;
        }
      }

      if (targetDevice == null) {
        if (!mounted) return;
        setState(() {
          connectionStatus = "Device not paired";
          isConnecting = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() => connectionStatus = "Connecting...");

      BluetoothConnection connection =
          await BluetoothConnection.toAddress(targetDevice.address);

      if (!mounted) return;
      setState(() {
        _connection = connection;
        isConnected = true;
        isConnecting = false;
        connectionStatus = "Connected";
      });

      _connection!.input!.listen((Uint8List data) {
        _handleIncomingData(data);
      }).onDone(() {
        if (mounted) {
          setState(() {
            isConnected = false;
            connectionStatus = "Disconnected";
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        connectionStatus = "Connection failed: $e";
        isConnected = false;
        isConnecting = false;
      });
    }
  }

  void _handleIncomingData(Uint8List data) {
    _dataBuffer += utf8.decode(data);
    while (_dataBuffer.contains('\n')) {
      int newlineIndex = _dataBuffer.indexOf('\n');
      String jsonString = _dataBuffer.substring(0, newlineIndex).trim();
      _dataBuffer = _dataBuffer.substring(newlineIndex + 1);
      if (jsonString.isNotEmpty) {
        _parseIMUData(jsonString);
      }
    }
  }

  void _parseIMUData(String jsonString) {
    try {
      Map<String, dynamic> data = json.decode(jsonString);
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

  Future<void> _disconnect() async {
    try {
      await _connection?.finish();
    } catch (e) {
      print('Disconnect error: $e');
    }
    if (!mounted) return;
    setState(() {
      _connection = null;
      isConnected = false;
      connectionStatus = "Disconnected";
    });
  }

  void _processIMUData(Map<String, double> data) {
    if (!mounted) return;
    
    final journeyProvider = Provider.of<JourneyProvider>(context, listen: false);
    
    setState(() {
      gyroX = data['gyroX']!;
      gyroY = data['gyroY']!;
      gyroZ = data['gyroZ']!;
      accelX = data['accelX']!;
      accelY = data['accelY']!;
      accelZ = data['accelZ']!;

      gyroZHistory.add(gyroZ.abs());
      if (gyroZHistory.length > maxHistoryLength) {
        gyroZHistory.removeAt(0);
      }

      double turnRate = gyroZ.abs();

      if (turnRate > riskyTurnThreshold) {
        currentTurnStatus = "RISKY TURN!";
        statusColor = Colors.red;
        riskyTurnCount++;
        
        // Add to journey if active
        if (journeyProvider.isJourneyActive) {
          journeyProvider.addTurnEvent(
            severity: 'risky',
            turnRate: turnRate,
            latitude: 0.0, // Get from GPS
            longitude: 0.0,
          );
        }
      } else if (turnRate > sharpTurnThreshold) {
        currentTurnStatus = "Sharp Turn";
        statusColor = Colors.orange;
        sharpTurnCount++;
        
        if (journeyProvider.isJourneyActive) {
          journeyProvider.addTurnEvent(
            severity: 'sharp',
            turnRate: turnRate,
            latitude: 0.0,
            longitude: 0.0,
          );
        }
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
        title: const Text('Risk Assessment'),
        backgroundColor: Colors.blue[700],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.history), text: 'Journey History'),
            Tab(icon: Icon(Icons.sensors), text: 'Live Monitoring'),
          ],
        ),
        actions: [
          if (_tabController.index == 1)
            IconButton(
              icon: Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
              onPressed: isConnected ? _disconnect : _scanAndConnect,
              tooltip: isConnected ? 'Disconnect' : 'Connect',
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildJourneyHistoryTab(),
          _buildLiveMonitoringTab(),
        ],
      ),
    );
  }

  // Journey History Tab
  Widget _buildJourneyHistoryTab() {
    return RefreshIndicator(
      onRefresh: _loadJourneyHistory,
      child: _isLoadingHistory
          ? const Center(child: CircularProgressIndicator())
          : _journeyHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.route_outlined, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No journeys recorded yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start a journey from Home Dashboard',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _journeyHistory.length,
                        itemBuilder: (context, index) {
                          final journey = _journeyHistory[index];
                          return _buildJourneyCard(journey);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildJourneyCard(JourneyData journey) {
    final duration = journey.endTime != null
        ? journey.endTime!.difference(journey.startTime)
        : Duration.zero;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      child: InkWell(
        onTap: () => _showJourneyDetails(journey),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.navigation, color: Colors.blue[700], size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          journey.destination ?? 'Unknown Destination',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          DateFormat('MMM dd, yyyy • HH:mm').format(journey.startTime),
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  _getRiskBadge(journey),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn(
                    Icons.route,
                    '${journey.totalDistance.toStringAsFixed(1)} km',
                    'Distance',
                  ),
                  _buildStatColumn(
                    Icons.timer,
                    '${duration.inMinutes} min',
                    'Duration',
                  ),
                  _buildStatColumn(
                    Icons.turn_sharp_right,
                    '${journey.sharpTurns}',
                    'Sharp',
                    Colors.orange,
                  ),
                  _buildStatColumn(
                    Icons.warning,
                    '${journey.riskyTurns}',
                    'Risky',
                    Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getRiskBadge(JourneyData journey) {
    final totalTurns = journey.sharpTurns + journey.riskyTurns;
    Color color;
    String label;
    
    if (journey.riskyTurns > 5 || totalTurns > 15) {
      color = Colors.red;
      label = 'HIGH RISK';
    } else if (journey.riskyTurns > 2 || totalTurns > 8) {
      color = Colors.orange;
      label = 'MODERATE';
    } else {
      color = Colors.green;
      label = 'LOW RISK';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildStatColumn(IconData icon, String value, String label, [Color? color]) {
    return Column(
      children: [
        Icon(icon, size: 24, color: color ?? Colors.grey[700]),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.black,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  void _showJourneyDetails(JourneyData journey) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => JourneyDetailsSheet(journey: journey),
    );
  }

  // Live Monitoring Tab
  Widget _buildLiveMonitoringTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildConnectionCard(),
          const SizedBox(height: 16),
          _buildStatusCard(),
          const SizedBox(height: 16),
          _buildStatisticsRow(),
          const SizedBox(height: 16),
          _buildGyroscopeCard(),
          const SizedBox(height: 16),
          _buildAccelerometerCard(),
          const SizedBox(height: 16),
          _buildTurnRateGraph(),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _resetCounters,
            icon: const Icon(Icons.refresh),
            label: const Text('Reset Counters'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
          ),
        ],
      ),
    );
  }

  // Keep all existing build methods for live monitoring
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
                Flexible(
                  child: Row(
                    children: [
                      Icon(
                        isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                        color: isConnected ? Colors.green : Colors.grey,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ESP32 Connection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(
                              connectionStatus,
                              style: TextStyle(fontSize: 14, color: isConnected ? Colors.green : Colors.grey[700]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isConnected && !isConnecting)
                  ElevatedButton.icon(
                    onPressed: _scanAndConnect,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (isConnecting)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
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
            Icon(_getStatusIcon(), size: 48, color: statusColor),
            const SizedBox(height: 12),
            Text(currentTurnStatus, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: statusColor)),
            const SizedBox(height: 8),
            Text('Turn Rate: ${gyroZ.abs().toStringAsFixed(1)}°/s', style: const TextStyle(fontSize: 16)),
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
        Expanded(child: _buildStatCard('Sharp Turns', sharpTurnCount.toString(), Icons.turn_right, Colors.orange)),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard('Risky Turns', riskyTurnCount.toString(), Icons.warning, Colors.red)),
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
            Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center),
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
            const Text('Gyroscope (°/s)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            const Text('Accelerometer (m/s²)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: Text(
                  value.toStringAsFixed(2),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
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
            const Text('Turn Rate History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: CustomPaint(
                size: Size.infinite,
                painter: GraphPainter(data: gyroZHistory, sharpThreshold: sharpTurnThreshold, riskyThreshold: riskyTurnThreshold),
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
        Container(width: 16, height: 3, color: color),
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

// Journey Details Sheet
class JourneyDetailsSheet extends StatelessWidget {
  final JourneyData journey;

  const JourneyDetailsSheet({super.key, required this.journey});

  @override
  Widget build(BuildContext context) {
    final duration = journey.endTime != null
        ? journey.endTime!.difference(journey.startTime)
        : Duration.zero;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      journey.destination ?? 'Journey Details',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('EEEE, MMM dd, yyyy • HH:mm').format(journey.startTime),
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                    _buildDetailCard(
                      'Journey Summary',
                      [
                        _buildDetailRow(Icons.route, 'Distance', '${journey.totalDistance.toStringAsFixed(2)} km'),
                        _buildDetailRow(Icons.timer, 'Duration', '${duration.inMinutes} minutes'),
                        _buildDetailRow(Icons.speed, 'Avg Speed', '${journey.averageSpeed.toStringAsFixed(1)} km/h'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildDetailCard(
                      'Risk Assessment',
                      [
                        _buildDetailRow(Icons.turn_sharp_right, 'Sharp Turns', '${journey.sharpTurns}', Colors.orange),
                        _buildDetailRow(Icons.warning, 'Risky Turns', '${journey.riskyTurns}', Colors.red),
                        _buildDetailRow(Icons.assessment, 'Total Events', '${journey.turnEvents.length}'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Generate PDF report
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Generate Report feature coming soon!')),
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Generate Report'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailCard(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 24, color: color ?? Colors.grey[700]),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

// Graph Painter (keep existing)
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

    // Threshold lines
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

    // Data line
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
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    return oldDelegate.data != data ||
           oldDelegate.sharpThreshold != sharpThreshold ||
           oldDelegate.riskyThreshold != riskyThreshold;
  }
}