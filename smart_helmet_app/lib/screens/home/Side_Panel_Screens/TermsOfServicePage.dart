import 'package:flutter/material.dart';

class TermsOfServicePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header branding
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.gavel,
                    size: 80,
                    color: Colors.indigo.withOpacity(0.8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Terms of Service',
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
              'Effective Date: January 04, 2026',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.grey[700],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'By downloading, installing, or using the Smart Helmet app, you agree to be bound by these Terms of Service.',
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 32),

            // Section: Use of App
            _buildSectionCard(
              context: context,
              title: 'Use of the App',
              children: [
                Text(
                  'The Smart Helmet app is designed to enhance personal safety during cycling or motorcycling. '
                  'It is not a substitute for professional medical advice—always consult qualified healthcare professionals for health-related concerns.',
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
                const SizedBox(height: 16),
                const BulletPoint(text: 'You must be at least 18 years old or have parental/guardian consent to use the app.'),
                const BulletPoint(text: 'Certain features (e.g., voice alerts, emergency calls) require permissions such as location and microphone access.'),
              ],
            ),
            const SizedBox(height: 24),

            // Section: Liability
            _buildSectionCard(
              context: context,
              title: 'Limitation of Liability',
              children: [
                Text(
                  'The app is provided "as is" without warranties of any kind. '
                  'We are not liable for any inaccuracies in sensor data, accidents, injuries, health events, or any damages arising from use of the app.',
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Section: Prohibited Use
            _buildSectionCard(
              context: context,
              title: 'Prohibited Activities',
              children: [
                const BulletPoint(text: 'No modification, reverse engineering, decompilation, or unauthorized commercial use of the app.'),
                const BulletPoint(text: 'No use that violates applicable laws or infringes on third-party rights.'),
              ],
            ),
            const SizedBox(height: 24),

            // Section: Termination
            _buildSectionCard(
              context: context,
              title: 'Termination',
              children: [
                Text(
                  'We reserve the right to suspend or terminate your access to the app at any time for violations of these terms. '
                  'These terms are governed by the laws of Sri Lanka.',
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Footer
            Center(
              child: Text(
                'Smart Helmet App • SLIIT University Project',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              ),
            ),
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