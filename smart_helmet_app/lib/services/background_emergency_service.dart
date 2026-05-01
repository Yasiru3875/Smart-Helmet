import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:system_alert_window/system_alert_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();

  final prefs = await SharedPreferences.getInstance();
  
  int sustainedCounter = 0;
  Timer? alertTimer;
  bool isAlerting = false;
  int countdown = 30;

  // Listen to health metrics from shared preferences (updated by main app)
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    try {
      // Get current sensor values from shared preferences
      final heartRate = prefs.getInt('current_heart_rate') ?? 70;
      final temperature = prefs.getDouble('current_temperature') ?? 36.5;
      final riskPercent = prefs.getInt('current_risk_percent') ?? 0;

      final bool isHighRisk = _evaluateHighRisk(
        riskPercent: riskPercent,
        hr: heartRate.toDouble(),
        temp: temperature,
      );

      if (isHighRisk && !isAlerting) {
        sustainedCounter++;
        debugPrint('Background: High risk sustained for $sustainedCounter seconds');
        
        if (sustainedCounter >= 30) {
          // Sustained risk confirmed - start alert sequence
          isAlerting = true;
          sustainedCounter = 0;
          await _showCancelOverlay(service);
          await _startFinalCountdown(service);
        }
      } else if (!isHighRisk) {
        sustainedCounter = 0; // Reset if risk drops
      }

      // Update service notification with current status
      service.invoke('updateStatus', {
        'heartRate': heartRate,
        'temperature': temperature,
        'riskPercent': riskPercent,
        'sustainedSeconds': sustainedCounter,
        'isAlerting': isAlerting,
      });

    } catch (e) {
      debugPrint('Background service error: $e');
    }
  });
}

bool _evaluateHighRisk({
  required int riskPercent,
  required double hr,
  required double temp,
}) {
  const int hrThreshold = 120;
  const double tempThreshold = 38.0;
  const double riskPercentThreshold = 75.0;

  if (riskPercent >= riskPercentThreshold) return true;
  if (hr > hrThreshold) return true;
  if (hr > 110 && temp > tempThreshold) return true;
  return false;
}

Future<void> _showCancelOverlay(ServiceInstance service) async {
  // Notify main app to show overlay - cannot use UI plugins in background isolate
  service.invoke('emergencyDetected');
}

Future<void> _startFinalCountdown(ServiceInstance service) async {
  int countdown = 30;
  
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    countdown--;
    
    // Notify main app of countdown update
    service.invoke('countdownUpdate', {'seconds': countdown});

    if (countdown <= 0) {
      timer.cancel();
      await _executeEmergencyProtocol(service);
    }
  });
}

Future<void> _cancelAlert(ServiceInstance service) async {
  // Just notify that alert was cancelled - UI handled by main app
  service.invoke('alertCancelled');
}

Future<void> _executeEmergencyProtocol(ServiceInstance service) async {
  try {
    // Fetch emergency contacts from Firestore
    final contacts = <String>[];
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('emergency_contacts')
          .get();
      
      for (var doc in snapshot.docs) {
        final phone = doc['phone'] as String?;
        if (phone != null && phone.isNotEmpty) {
          contacts.add(phone);
        }
      }
    } catch (e) {
      debugPrint('Error fetching contacts: $e');
    }

    // Notify main app to execute emergency protocol (launch SMS, show UI)
    // Cannot use url_launcher or UI plugins in background isolate
    service.invoke('executeEmergency', {
      'contacts': contacts,
      'timestamp': DateTime.now().toIso8601String(),
    });

    debugPrint('Emergency protocol triggered for ${contacts.length} contacts');

    // Log to Firestore for history
    try {
      await FirebaseFirestore.instance.collection('emergency_alerts').add({
        'alertType': 'BACKGROUND_EMERGENCY',
        'contactsNotified': contacts,
        'alertMethod': 'BACKGROUND_SMS_SIM',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error logging alert: $e');
    }
  } catch (e) {
    debugPrint('Error in emergency protocol: $e');
    service.invoke('emergencyProtocolError', {'error': e.toString()});
  }
}

class BackgroundEmergencyService {
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();
    
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'smart_helmet_emergency_channel',
        initialNotificationTitle: 'Smart Helmet Emergency Service',
        initialNotificationContent: 'Monitoring sensors for rider safety',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: (ServiceInstance service) async {
          onStart(service);
          return true;
        },
      ),
    );
    
    service.startService();
  }

  static Future<void> requestPermissions() async {
    // Request system alert window permission
    await SystemAlertWindow.requestPermissions(prefMode: SystemWindowPrefMode.OVERLAY);
    
    // Request location permission
    await Geolocator.requestPermission();
  }

  static Future<void> updateSensorData({
    required int heartRate,
    required double temperature,
    required int riskPercent,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_heart_rate', heartRate);
    await prefs.setDouble('current_temperature', temperature);
    await prefs.setInt('current_risk_percent', riskPercent);
  }

  static Future<bool> isServiceRunning() async {
    return await FlutterBackgroundService().isRunning();
  }

  static Future<void> stopService() async {
    FlutterBackgroundService().invoke('stopService');
  }
}
