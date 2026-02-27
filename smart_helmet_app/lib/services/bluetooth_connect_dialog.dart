import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import 'bluetooth_manager.dart'; // ← make sure this file is also imported correctly

class BluetoothConnectDialog extends StatefulWidget {
  final BluetoothManager manager;

  const BluetoothConnectDialog({super.key, required this.manager});

  @override
  State<BluetoothConnectDialog> createState() => _BluetoothConnectDialogState();
}

class _BluetoothConnectDialogState extends State<BluetoothConnectDialog> {
  List<BluetoothDevice> _bondedDevices = [];
  bool _isLoading = true;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _loadBondedDevices();
  }

  Future<void> _loadBondedDevices() async {
    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      if (!mounted) return;
      setState(() {
        _bondedDevices = devices;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Error loading devices: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _connectToAll() async {
    if (_bondedDevices.isEmpty) return;

    if (!mounted) return;
    setState(() => _statusMessage = 'Connecting to all devices...');

    int successCount = 0;
    int failCount = 0;

    for (final device in _bondedDevices) {
      final deviceName = device.name ?? device.address;
      // Optional: filter only helmet-like devices
      // if (!deviceName.contains('Helmet') && !deviceName.contains('ESP')) continue;

      final result = await widget.manager.connectToDevice(deviceName);
      if (result.toLowerCase().contains('connected')) {
        successCount++;
      } else {
        failCount++;
      }
    }

    if (!mounted) return;
    setState(() {
      _statusMessage =
          'Connected: $successCount | Failed: $failCount\nTap outside to close.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bluetooth Devices'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_statusMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _statusMessage.contains('Connected')
                              ? Colors.green[700]
                              : Colors.red[700],
                        ),
                      ),
                    ),
                  if (_bondedDevices.isEmpty && !_isLoading)
                    const Text(
                      'No paired devices found.\n'
                      'Please pair your helmet device in phone Bluetooth settings first.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _bondedDevices.length,
                      itemBuilder: (context, index) {
                        final device = _bondedDevices[index];
                        final name =
                            device.name ?? 'Unknown (${device.address})';
                        final isConnected = widget.manager.isConnected(name);

                        return ListTile(
                          leading: Icon(
                            isConnected
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth,
                            color: isConnected ? Colors.green : Colors.grey,
                          ),
                          title: Text(name),
                          subtitle: Text(device.address),
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
            label: const Text('Connect All'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: _connectToAll,
          ),
      ],
    );
  }
}
