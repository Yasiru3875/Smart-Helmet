import 'package:flutter/material.dart';

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Us'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Removed: SLIIT logo and title

            // Hero Section with Smart Helmet Image
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Image.asset(
                    'assets/icons/app_icon.png', // Make sure the path matches your pubspec.yaml
                    height: 100,
                    width: double.infinity,
                    
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(
                          'Smart Helmet for Cyclists and Motorcyclists',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Project ID: 25-26J-294 | Year: 2025\n',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Project Overview
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Overview',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.deepPurple),
                    ),
                    const Divider(),
                    const Text(
                      'This intelligent smart helmet system enhances rider safety and well-being through real-time health monitoring, '
                      'stress detection, danger zone alerts, and personalized post-ride analytics. '
                      'Integrating biometric sensors (heart rate, temperature, EEG), motion sensors (IMU), IoT (ESP32), and machine learning, '
                      'it provides proactive alerts, hands-free emergency communication, and multilingual voice guidance.',
                      style: TextStyle(fontSize: 16, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            

            // Team Members
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Development Team',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.deepPurple),
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    Image.asset(
                      'assets/icons/dev_team.png',
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                    const SizedBox(height: 16),
                    const BulletPoint(text: 'Vithanage K.W.Y.L.N (IT22595980) – Health Monitoring System'),
                    const BulletPoint(text: 'Samarakoon S.S.A.D.S.B (IT22207036) – Emotion & Stress Monitoring with Real-Time Feedback'),
                    const BulletPoint(text: 'Samarasinghe K.P.C (IT22608086) – Post-Journey Risk Assessment & Report Generation'),
                    const BulletPoint(text: 'Primasha W.G.R (IT22216878) – Danger Zone Detection & Voice-Guided Riding Assistant'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Footer
            Center(
              child: Text(
                'Version 1.0.0 • January 2026\n© SLIIT Research Project Team',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// Reusable BulletPoint widget
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
          const Text('• ', style: TextStyle(color: Colors.indigo, fontSize: 20, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 15.5, height: 1.5)),
          ),
        ],
      ),
    );
  }
}