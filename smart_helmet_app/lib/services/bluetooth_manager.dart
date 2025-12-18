import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized Bluetooth Manager to handle multiple device connections
class BluetoothManager extends ChangeNotifier {
  // Singleton pattern
  static final BluetoothManager _instance = BluetoothManager._internal();
  factory BluetoothManager() => _instance;
  BluetoothManager._internal();

  // Device connections map
  final Map<String, BluetoothConnection> _connections = {};
  final Map<String, bool> _connectionStatus = {};
  final Map<String, StreamController<List<int>>> _dataControllers = {};

  // Get connection status for a device
  bool isConnected(String deviceName) => _connectionStatus[deviceName] ?? false;

  // Get data stream for a device
  Stream<List<int>>? getDataStream(String deviceName) {
    return _dataControllers[deviceName]?.stream;
  }

  // Request Bluetooth permissions
  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  // Connect to a specific device
  Future<String> connectToDevice(String deviceName) async {
    // Check if already connected
    if (_connectionStatus[deviceName] == true) {
      return "Already connected to $deviceName";
    }

    // Check permissions
    if (!await Permission.bluetoothConnect.isGranted) {
      return "Bluetooth permission denied";
    }

    try {
      // Get bonded devices
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();

      // Find target device
      BluetoothDevice? target;
      for (final device in devices) {
        if (device.name == deviceName) {
          target = device;
          break;
        }
      }

      if (target == null) {
        return "$deviceName not paired. Please pair the device in system settings.";
      }

      // Add a small delay before connecting (helps with ESP32)
      await Future.delayed(const Duration(milliseconds: 500));

      // Create connection
      final connection = await BluetoothConnection.toAddress(target.address);
      _connections[deviceName] = connection;
      _connectionStatus[deviceName] = true;

      // Create data stream controller if not exists
      if (!_dataControllers.containsKey(deviceName)) {
        _dataControllers[deviceName] = StreamController<List<int>>.broadcast();
      }

      // Listen to incoming data
      connection.input!.listen(
        (data) {
          // Forward data to device-specific stream
          if (_dataControllers[deviceName]?.isClosed == false) {
            _dataControllers[deviceName]!.add(data);
          }
        },
        onDone: () {
          debugPrint("$deviceName disconnected");
          _handleDisconnection(deviceName);
        },
        onError: (error) {
          debugPrint("$deviceName error: $error");
          _handleDisconnection(deviceName);
        },
        cancelOnError: true,
      );

      notifyListeners();
      return "Connected to $deviceName";
    } catch (e) {
      debugPrint("Failed to connect to $deviceName: $e");
      _connectionStatus[deviceName] = false;
      notifyListeners();
      return "Connection failed: ${e.toString()}";
    }
  }

  // Disconnect from a specific device
  Future<void> disconnectDevice(String deviceName) async {
    try {
      await _connections[deviceName]?.finish();
      _handleDisconnection(deviceName);
    } catch (e) {
      debugPrint("Error disconnecting $deviceName: $e");
    }
  }

  // Handle disconnection cleanup
  void _handleDisconnection(String deviceName) {
    _connections.remove(deviceName);
    _connectionStatus[deviceName] = false;
    notifyListeners();
  }

  // Disconnect all devices
  Future<void> disconnectAll() async {
    final devices = List<String>.from(_connections.keys);
    for (final deviceName in devices) {
      await disconnectDevice(deviceName);
    }
  }

  // Dispose resources
  @override
  void dispose() {
    for (final controller in _dataControllers.values) {
      controller.close();
    }
    _dataControllers.clear();

    for (final connection in _connections.values) {
      connection.dispose();
    }
    _connections.clear();

    super.dispose();
  }
}