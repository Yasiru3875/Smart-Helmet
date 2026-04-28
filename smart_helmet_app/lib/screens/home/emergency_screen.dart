import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/sos_controller.dart';
import '../../models/sos_state.dart';

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SOSController>(
      builder: (context, sosController, child) {
        final state = sosController.state;

        if (!state.isActive) {
          return const Scaffold(
            body: Center(
              child: Text('No Emergency'),
            ),
          );
        }

        return Scaffold(
          body: Container(
            color: Colors.red,
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_rounded,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'EMERGENCY',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    '${state.countdown}',
                    style: const TextStyle(
                      fontSize: 120,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    'SOS will be sent in...',
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Press CANCEL to stop',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 60),
                  _buildCancelButton(context, sosController),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCancelButton(BuildContext context, SOSController controller) {
    return ElevatedButton(
      onPressed: controller.cancelSOS,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.red,
        padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      child: const Text(
        'CANCEL SOS',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
