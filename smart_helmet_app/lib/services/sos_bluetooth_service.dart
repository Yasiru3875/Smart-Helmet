import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class SOSBluetoothService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;
  final StreamController<String> _eventController = StreamController<String>.broadcast();

  Stream<String> get onEmergencyTriggered => _eventController.stream;

  Future<void> initialize() async {
    // Initialize Bluetooth and connect to ESP32
    // This will be integrated with your existing BLE manager
  }

  void setDevice(BluetoothDevice device) {
    _device = device;
  }

  void setCharacteristics(BluetoothCharacteristic tx, BluetoothCharacteristic rx) {
    _txCharacteristic = tx;
    _rxCharacteristic = rx;
    
    // Listen for incoming data from ESP32
    _rxCharacteristic?.value.listen((data) {
      final message = String.fromCharCodes(data);
      _handleIncomingMessage(message);
    });
  }

  void _handleIncomingMessage(String message) {
    switch (message.trim()) {
      case 'EMERGENCY_TRIGGERED':
        _eventController.add('EMERGENCY_TRIGGERED');
        break;
      case 'SOS_CANCELLED':
        // ESP32 cancelled the SOS
        break;
      default:
        // Handle other messages
        break;
    }
  }

  Future<void> sendCommand(String command) async {
    if (_txCharacteristic != null) {
      await _txCharacteristic?.write(command.codeUnits);
    }
  }

  void dispose() {
    _eventController.close();
  }
}
