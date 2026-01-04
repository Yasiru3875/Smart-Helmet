import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Optional header with app branding
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.security,
                    size: 80,
                    color: Colors.indigo.withOpacity(0.8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Smart Helmet App',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.indigo,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            Text(
              'Privacy Policy',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.indigo,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Effective Date: January 04, 2026\n'
              'Your privacy is extremely important to us. This policy explains how the Smart Helmet app collects, uses, and protects your personal data.',
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 32),

            // Section: Data We Collect
            _buildSectionCard(
              context: context,
              title: 'Data We Collect',
              children: [
                const BulletPoint(
                  text:
                      'Biometric Data: Heart rate, temperature, EEG (brainwaves), and IMU (motion) from helmet sensors.',
                ),
                const BulletPoint(
                  text: 'Location Data: GPS for route tracking and danger zone detection.',
                ),
                const BulletPoint(
                  text: 'Usage Data: Ride history, stress levels, and app interactions for personalized reports.',
                ),
                const BulletPoint(
                  text: 'Personal Info: Email and preferences (e.g., language: English/Sinhala).',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Section: How We Use Data
            _buildSectionCard(
              context: context,
              title: 'How We Use Your Data',
              children: [
                Text(
                  'Your data is used to provide real-time safety alerts, generate post-ride analytics, and improve app features. '
                  'We process data on the edge (ESP32) where possible and store it securely in the cloud (e.g., Firebase) with end-to-end encryption. '
                  'We do not share your data with third parties without your explicit consent, except in emergencies where it may be shared with authorized services.',
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Section: Security
            _buildSectionCard(
              context: context,
              title: 'Security Measures',
              children: [
                Text(
                  'We use secure Bluetooth Low Energy (BLE) transmission and adhere to industry-standard data protection practices. '
                  'You have full control: delete your data at any time through the app settings.',
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Section: Changes
            _buildSectionCard(
              context: context,
              title: 'Changes to This Policy',
              children: [
                Text(
                  'We may occasionally update this privacy policy. Continued use of the app after changes constitutes acceptance of the updated policy. '
                  'We will notify you of material changes via in-app notification or email.',
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ],
            ),
            const SizedBox(height: 32),

            
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.deepPurple,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class BulletPoint extends StatelessWidget {
  final String text;

  const BulletPoint({required this.text, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.fiber_manual_record,
            size: 12,
            color: Colors.indigo.withOpacity(0.8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}