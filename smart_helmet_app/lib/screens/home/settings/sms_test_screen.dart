import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/sos_controller.dart';

/// SMS Test Screen - Use this to verify SMS is working
class SmsTestScreen extends StatelessWidget {
  const SmsTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Diagnostics'),
        backgroundColor: Colors.indigo,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Configuration Status Card
            _buildStatusCard(context),
            const SizedBox(height: 16),
            
            // Test Buttons
            _buildTestButtons(context),
            const SizedBox(height: 16),
            
            // Important Info
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final sosController = context.watch<SOSController>();
    final status = sosController.whatsAppStatus;
    final isConfigured = sosController.isWhatsAppConfigured;

    return Card(
      color: isConfigured ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConfigured ? Icons.check_circle : Icons.error,
                  color: isConfigured ? Colors.green : Colors.red,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  'SMS Service Status',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Configured: ${status['configured']}',
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              status['cloudFunctionUrl'].toString(),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (!isConfigured)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '⚠️ SMS service not configured. Cloud Function URL missing.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestButtons(BuildContext context) {
    final phoneController = TextEditingController(text: '+94703875215');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Test SMS',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number (with country code)',
                hintText: '+94703875215',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                final sosController = context.read<SOSController>();
                
                if (!sosController.isWhatsAppConfigured) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ SMS service not configured. Check Cloud Function URL.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Show loading
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(child: CircularProgressIndicator()),
                );

                // Send test SMS
                final result = await sosController.sendTestWhatsApp(phoneController.text);
                
                // Hide loading
                Navigator.of(context).pop();

                // Show result
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result['success'] 
                        ? '✅ Test SMS sent! Check your phone.'
                        : '❌ Failed: ${result['error']}',
                    ),
                    backgroundColor: result['success'] ? Colors.green : Colors.red,
                  ),
                );
              },
              icon: const Icon(Icons.send),
              label: const Text('Send Test SMS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final sosController = context.read<SOSController>();
                
                // Trigger SOS to test full flow
                sosController.startSOS();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🚨 SOS Countdown started. Wait 60s or press cancel.'),
                    duration: Duration(seconds: 5),
                  ),
                );
              },
              icon: const Icon(Icons.emergency, color: Colors.red),
              label: const Text('Trigger SOS Countdown'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue.shade50,
      child: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Important Notes',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text('• Phone numbers must include country code (e.g., +94...)'),
            Text('• Trial accounts only send to verified numbers'),
            Text('• Check Twilio logs if messages fail'),
            Text('• Ensure Firebase Functions are deployed'),
            SizedBox(height: 8),
            Text(
              'Verified Number: +94703875215',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
