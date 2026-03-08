import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Highly robust BLE Manager for SmartWatch_ESP32 with diagnostic logging
class BleManager extends ChangeNotifier {
  // Singleton pattern
  static final BleManager _instance = BleManager._internal();
  factory BleManager() => _instance;
  BleManager._internal();

  final Map<String, BluetoothDevice> _connectedDevices = {};
  final Map<String, bool> _connectionStatus = {};
  final Map<String, StreamController<List<int>>> _dataControllers = {};
  
  // Track subscriptions
  final Map<String, StreamSubscription> _valueSubscriptions = {};
  StreamSubscription? _adapterStateSubscription;

  // Standard Heart Rate Service & Characteristic UUIDs
  static const String hrServiceUuid = "180d";
  static const String hrCharUuid = "2a37";
  
  // Nordic UART Service (common for ESP32 serial bridge)
  static const String nusServiceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  static const String nusRxCharUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

  bool isConnected(String deviceName) => _connectionStatus[deviceName] ?? false;

  BleManager() {
    // Listen to adapter state
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state != BluetoothAdapterState.on) {
        debugPrint("BLE Adapter is: $state");
        // Handle global disconnection if needed
      }
    });
    
    // Set verbose logging for thorough debugging
    FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
  }

  Stream<List<int>>? getDataStream(String deviceName) {
    return _dataControllers[deviceName]?.stream;
  }

  Future<bool> isBluetoothOn() async {
    return await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
  }

  Future<bool> requestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location, // Critical for scanning on many Android versions
      ].request();
      
      bool granted = statuses.values.every((status) => status.isGranted);
      debugPrint("BLE Permissions: $granted | $statuses");
      return granted;
    }
    return true;
  }

  Future<String> connectToDevice(String deviceName) async {
    if (_connectionStatus[deviceName] == true) {
      return "Already connected to $deviceName";
    }

    if (!await isBluetoothOn()) {
      return "Bluetooth is OFF. Please turn it ON.";
    }

    if (!await requestPermissions()) {
      return "BLE permissions denied. Check app settings.";
    }

    try {
      BluetoothDevice? targetDevice;

      // 1. Check already connected devices
      List<BluetoothDevice> connected = await FlutterBluePlus.connectedSystemDevices;
      for (var d in connected) {
        debugPrint("System device: ${d.platformName} | ${d.advName}");
        if (d.platformName == deviceName || d.advName == deviceName) {
          targetDevice = d;
          break;
        }
      }

      // 2. Scan if not found
      if (targetDevice == null) {
        debugPrint("Starting diagnostic scan for $deviceName...");
        
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}

        final deviceCompleter = Completer<BluetoothDevice?>();
        final scanResults = <String>{}; // To avoid flooding logs with duplicates
        
        final scanSubscription = FlutterBluePlus.scanResults.listen((results) {
          for (ScanResult r in results) {
            String logEntry = "[Found] Name: ${r.device.platformName} | AdvName: ${r.advName} | RSSI: ${r.rssi} | ID: ${r.device.remoteId}";
            if (scanResults.add(logEntry)) {
              debugPrint(logEntry);
            }
            
            if (r.device.platformName == deviceName || 
                r.advName == deviceName || 
                r.advertisementData.localName == deviceName) {
              if (!deviceCompleter.isCompleted) {
                debugPrint(">>> MATCH FOUND: $deviceName <<<");
                deviceCompleter.complete(r.device);
              }
            }
          }
        });

        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 15), 
          androidUsesFineLocation: true,
          // Scanning for specific names is sometimes unreliable, scan all and filter manually
        );

        targetDevice = await deviceCompleter.future.timeout(
          const Duration(seconds: 15), 
          onTimeout: () => null
        );

        await scanSubscription.cancel();
        await FlutterBluePlus.stopScan();
      }

      if (targetDevice == null) {
        return "Not found. Is $deviceName nearby and advertising?";
      }

      // 3. Connect with aggressive parameters
      debugPrint("Connecting to ${targetDevice.remoteId}...");
      
      // Retry connection up to 2 times
      int retry = 0;
      bool success = false;
      while (retry < 2 && !success) {
        try {
          await targetDevice.connect(
            timeout: const Duration(seconds: 10), 
            autoConnect: false,
          );
          success = true;
        } catch (e) {
          retry++;
          debugPrint("Connection attempt $retry failed: $e");
          if (retry < 2) await Future.delayed(const Duration(seconds: 2));
        }
      }

      if (!success) return "Connection handshake failed. Try toggling watch Bluetooth.";

      _connectedDevices[deviceName] = targetDevice;
      _connectionStatus[deviceName] = true;

      // Request MTU (don't fail if this fails)
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          await targetDevice.requestMtu(512).timeout(const Duration(seconds: 3));
          debugPrint("MTU set to 512");
        } catch (e) {
          debugPrint("MTU request refused: $e");
        }
      }

      // 4. Robust Service Discovery
      debugPrint("Discovering services for ${deviceName}...");
      List<BluetoothService> services = await targetDevice.discoverServices();
      BluetoothCharacteristic? targetChar;

      for (var service in services) {
        String sUuid = service.uuid.toString().toLowerCase();
        debugPrint("Service found: $sUuid");
        
        if (sUuid.contains(hrServiceUuid)) {
          for (var char in service.characteristics) {
             debugPrint("  Characteristic: ${char.uuid}");
            if (char.uuid.toString().toLowerCase().contains(hrCharUuid)) {
              targetChar = char;
              debugPrint("  Target: Heart Rate found!");
              break;
            }
          }
        }
        
        if (targetChar == null && sUuid.contains(nusServiceUuid)) {
          for (var char in service.characteristics) {
            debugPrint("  Characteristic (NUS): ${char.uuid}");
             if (char.uuid.toString().toLowerCase().contains(nusRxCharUuid)) {
              targetChar = char;
              debugPrint("  Target: NUS Data found!");
              break;
            }
          }
        }
      }

      if (targetChar != null) {
        await targetChar.setNotifyValue(true);
        _valueSubscriptions[deviceName] = targetChar.onValueReceived.listen((value) {
          if (_dataControllers[deviceName]?.isClosed == false) {
             _dataControllers[deviceName]!.add(value);
          }
        });
        debugPrint("Notifications enabled for $deviceName");
      } else {
        debugPrint("Check watch firmware: No Heart Rate or NUS service detected.");
      }

      // 5. Monitor State
      targetDevice.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection(deviceName);
        }
      });

      notifyListeners();
      return "Connected to $deviceName";
    } catch (e) {
      debugPrint("Critical connection error: $e");
      _handleDisconnection(deviceName);
      return "Failed: $e";
    }
  }

  void _handleDisconnection(String deviceName) {
    _valueSubscriptions[deviceName]?.cancel();
    _valueSubscriptions.remove(deviceName);
    _connectedDevices.remove(deviceName);
    _connectionStatus[deviceName] = false;
    notifyListeners();
  }

  Future<void> disconnectDevice(String deviceName) async {
    await _connectedDevices[deviceName]?.disconnect();
    _handleDisconnection(deviceName);
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    for (var sub in _valueSubscriptions.values) {
      sub.cancel();
    }
    for (var controller in _dataControllers.values) {
      controller.close();
    }
    super.dispose();
  }
}
