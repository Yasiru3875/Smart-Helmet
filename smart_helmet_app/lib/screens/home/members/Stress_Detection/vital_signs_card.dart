import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/sensor_data_provider.dart';
import '../../../../services/combined_stress_service.dart';

/// VitalSignsCard displays heart rate and temperature from the smartwatch
/// and provides stress calculation using HR+Temp when EEG is unavailable
class VitalSignsCard extends StatelessWidget {
  final bool useFallback;
  final double? fallbackStressScore;
  final String? fallbackStressLevel;
  final Color? fallbackStressColor;
  final String? fallbackStressEmoji;

  const VitalSignsCard({
    super.key,
    this.useFallback = false,
    this.fallbackStressScore,
    this.fallbackStressLevel,
    this.fallbackStressColor,
    this.fallbackStressEmoji,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorDataProvider>(
      builder: (context, sensorProvider, child) {
        final heartRate = sensorProvider.heartRate;
        final temperature = sensorProvider.temperature;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Vital Signs",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "Smartwatch data",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Heart Rate and Temperature Row
              Row(
                children: [
                  // Heart Rate Card
                  Expanded(
                    child: _buildVitalMetricCard(
                      icon: Icons.favorite,
                      iconColor: Colors.red,
                      value: "$heartRate",
                      unit: "BPM",
                      label: "Heart Rate",
                      normalRange: "60-100",
                      isNormal: heartRate >= 60 && heartRate <= 100,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Temperature Card
                  Expanded(
                    child: _buildVitalMetricCard(
                      icon: Icons.thermostat,
                      iconColor: Colors.orange,
                      value: "${temperature.toStringAsFixed(1)}",
                      unit: "°C",
                      label: "Temperature",
                      normalRange: "36.1-37.2",
                      isNormal: temperature >= 36.1 && temperature <= 37.2,
                    ),
                  ),
                ],
              ),

              // Fallback Stress Display (when EEG unavailable)
              if (useFallback && fallbackStressScore != null) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (fallbackStressColor ?? Colors.grey).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: (fallbackStressColor ?? Colors.grey).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (fallbackStressColor ?? Colors.grey).withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              fallbackStressEmoji ?? "📊",
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fallbackStressLevel ?? "Calculating...",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: fallbackStressColor ?? Colors.grey,
                                  ),
                                ),
                                const Text(
                                  "Based on HR & Temperature",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: fallbackStressScore ?? 0.0,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          fallbackStressColor ?? Colors.grey,
                        ),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Stress Load: ${((fallbackStressScore ?? 0) * 100).toInt()}%",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: fallbackStressColor ?? Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildVitalMetricCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String unit,
    required String label,
    required String normalRange,
    required bool isNormal,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: iconColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isNormal ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isNormal ? "Normal" : "Abnormal",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isNormal ? Colors.green : Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: isNormal ? iconColor : Colors.orange,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 14,
                  color: iconColor.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Normal: $normalRange",
            style: TextStyle(
              fontSize: 10,
              color: Colors.black.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// VitalSignsCardWithStress is a StatefulWidget that automatically calculates
/// stress from HR+Temp when EEG is not available
class VitalSignsCardWithStress extends StatefulWidget {
  final bool eegAvailable;
  
  const VitalSignsCardWithStress({
    super.key,
    required this.eegAvailable,
  });

  @override
  State<VitalSignsCardWithStress> createState() => _VitalSignsCardWithStressState();
}

class _VitalSignsCardWithStressState extends State<VitalSignsCardWithStress> {
  final CombinedStressService _stressService = CombinedStressService();

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorDataProvider>(
      builder: (context, sensorProvider, child) {
        // Update stress service with current HR and Temp
        _stressService.updateHeartRate(sensorProvider.heartRate.toDouble());
        _stressService.updateTemperature(sensorProvider.temperature);

        final stressScore = _stressService.combinedStressScore;
        final stressLevel = _stressService.getStressLevelText();
        final stressColor = _stressService.getStressColor();
        final stressEmoji = _stressService.getStressEmoji();

        return VitalSignsCard(
          useFallback: !widget.eegAvailable,
          fallbackStressScore: stressScore,
          fallbackStressLevel: stressLevel,
          fallbackStressColor: stressColor,
          fallbackStressEmoji: stressEmoji,
        );
      },
    );
  }
}
