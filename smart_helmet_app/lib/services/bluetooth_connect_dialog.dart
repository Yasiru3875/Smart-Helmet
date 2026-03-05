import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import 'bluetooth_manager.dart'; // Your BluetoothManager class

class BluetoothConnectDialog extends StatefulWidget {
  final BluetoothManager manager;

  const BluetoothConnectDialog({super.key, required this.manager});

  @override
  State<BluetoothConnectDialog> createState() => _BluetoothConnectDialogState();
}

class _BluetoothConnectDialogState extends State<BluetoothConnectDialog> {
  List<BluetoothDevice> _bondedDevices = [];
  bool _isLoading = true;
  String _overallStatus = 'Scanning for your sensors...';

  // Only these devices are relevant
  final List<String> _targetDevices = [
    "SmartHelmet_ESP32",
    "SmartWatch_ESP32",
    "HR-S0C1913",
  ];

  // Track real-time status for each target device
  final Map<String, String> _deviceStatus = {};

  @override
  void initState() {
    super.initState();
    _loadPairedDevices().then((_) {
      _autoConnectTargets();
    });
  }

  Future<void> _loadPairedDevices() async {
    try {
      final allPaired =
          await FlutterBluetoothSerial.instance.getBondedDevices();
      if (!mounted) return;

      // Filter only devices that match our targets
      final matched = allPaired.where((d) {
        final nameLower = (d.name ?? '').toLowerCase().trim();
        return _targetDevices.any((t) {
          final tLower = t.toLowerCase();
          return nameLower.contains(tLower) ||
              nameLower.startsWith(tLower) ||
              nameLower
                  .replaceAll(' ', '')
                  .contains(tLower.replaceAll(' ', ''));
        });
      }).toList();

      setState(() {
        _bondedDevices = matched;
        _isLoading = false;
      });

      // Debug print - very useful!
      print("=== DETECTED TARGET DEVICES ===");
      if (matched.isEmpty) {
        print("→ None of the target devices were found");
      } else {
        for (var d in matched) {
          print(" - ${d.name ?? 'Unnamed'} (${d.address})");
        }
      }
      print("==============================");
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _overallStatus = 'Error loading devices: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _autoConnectTargets({bool isRetry = false}) async {
    if (_bondedDevices.isEmpty) {
      setState(() {
        _overallStatus = 'No matching sensors found.\n\n'
            'Make sure:\n'
            '• Devices are powered on\n'
            '• Paired in phone Bluetooth settings\n'
            '• Names include: SmartHelmet_ESP32, SmartWatch_ESP32, HR-S0C1913';
      });
      return;
    }

    setState(() {
      _overallStatus = '${isRetry ? 'Re-' : 'A'}uto-connecting sensors...';
      _deviceStatus.clear(); // reset per-device status
    });

    int success = 0;

    for (final target in _targetDevices) {
      // Try to find matching device
      BluetoothDevice? targetDevice;
      for (var d in _bondedDevices) {
        final nameLower = (d.name ?? '').toLowerCase().trim();
        final targetLower = target.toLowerCase();
        if (nameLower.contains(targetLower) ||
            nameLower.startsWith(targetLower) ||
            nameLower
                .replaceAll(' ', '')
                .contains(targetLower.replaceAll(' ', ''))) {
          targetDevice = d;
          break;
        }
      }

      if (targetDevice == null) {
        setState(() {
          _deviceStatus[target] = '✗ Not found';
          _overallStatus += '\n✗ $target → not detected';
        });
        continue;
      }

      final displayName = targetDevice.name ?? targetDevice.address;

      setState(() {
        _deviceStatus[target] = 'Connecting...';
        _overallStatus += '\n→ Trying $displayName...';
      });

      try {
        final result = await widget.manager.connectToDevice(displayName);
        final isSuccess = result.toLowerCase().contains('connected');

        setState(() {
          _deviceStatus[target] = isSuccess ? '✓ Connected' : '✗ $result';
          _overallStatus +=
              '\n${isSuccess ? '✓' : '✗'} $displayName → ${isSuccess ? 'Connected' : result}';
        });

        if (isSuccess) success++;
      } catch (e) {
        setState(() {
          _deviceStatus[target] = '✗ Error';
          _overallStatus += '\n✗ $displayName → Error: $e';
        });
      }

      // Important: delay between connections
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    setState(() {
      _overallStatus +=
          '\n\nFinished: $success/${_targetDevices.length} connected successfully.\n'
          'Close dialog or tap "Retry All" to try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your Sensors'),
      content: SizedBox(
        width: double.maxFinite,
        height: 480,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status summary
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _overallStatus,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: _overallStatus.contains('✓') ||
                                _overallStatus.contains('Connected')
                            ? Colors.green[800]
                            : _overallStatus.contains('✗') ||
                                    _overallStatus.contains('Error')
                                ? Colors.red[800]
                                : Colors.blue[800],
                      ),
                    ),
                  ),

                  // If no devices found → show instructions
                  if (_bondedDevices.isEmpty && !_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'None of your sensors were detected.\n\n'
                        'Steps to fix:\n'
                        '1. Turn on all sensors\n'
                        '2. Go to phone Settings → Bluetooth\n'
                        '3. Pair: SmartHelmet_ESP32, SmartWatch_ESP32, HR-S0C1913\n'
                        '4. Restart Bluetooth or phone if needed',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ),

                  // List of only your expected devices
                  Expanded(
                    child: ListView.builder(
                      itemCount: _bondedDevices.length,
                      itemBuilder: (context, index) {
                        final device = _bondedDevices[index];
                        final name =
                            device.name ?? 'Unknown (${device.address})';
                        final isConnected = widget.manager.isConnected(name);
                        final statusText = _deviceStatus.entries
                            .firstWhere(
                              (e) => name
                                  .toLowerCase()
                                  .contains(e.key.toLowerCase()),
                              orElse: () => MapEntry('', ''),
                            )
                            .value;

                        return ListTile(
                          leading: Icon(
                            isConnected
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth,
                            color: isConnected ? Colors.green : Colors.grey,
                          ),
                          title: Text(name),
                          subtitle: Text(
                            statusText.isNotEmpty ? statusText : device.address,
                            style: TextStyle(
                              color: statusText.contains('✓')
                                  ? Colors.green
                                  : statusText.contains('✗')
                                      ? Colors.red
                                      : null,
                            ),
                          ),
                          trailing: isConnected
                              ? IconButton(
                                  icon: const Icon(Icons.link_off,
                                      color: Colors.red),
                                  onPressed: () async {
                                    await widget.manager.disconnectDevice(name);
                                    setState(() {});
                                  },
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (!_isLoading && _bondedDevices.isNotEmpty)
          ElevatedButton.icon(
            icon: const Icon(Icons.sync),
            label: const Text('Retry All'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _autoConnectTargets(isRetry: true),
          ),
      ],
    );
  }
}
