import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:background_sms/background_sms.dart';
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
  try {
    await SystemAlertWindow.requestPermissions(prefMode: SystemWindowPrefMode.OVERLAY);
    
    await SystemAlertWindow.showSystemWindow(
      backgroundColor: '#ff0000',
      height: 200,
      gravity: SystemWindowGravity.TOP,
      body: Column(
        children: [
          Text(
            'EMERGENCY ALERT',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),
          Text(
            'Sustained high risk detected!',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          SizedBox(height: 10),
          Text(
            'Emergency SMS will be sent in 30 seconds',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              await _cancelAlert(service);
            },
            child: Text('CANCEL'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red,
            ),
          ),
        ],
      ),
    );
  } catch (e) {
    debugPrint('Error showing overlay: $e');
  }
}

Future<void> _startFinalCountdown(ServiceInstance service) async {
  int countdown = 30;
  
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    countdown--;
    
    try {
      // Update countdown on overlay
      await SystemAlertWindow.sendMessageToOverlay("Time left: $countdown");
    } catch (e) {
      debugPrint('Error updating overlay: $e');
    }

    if (countdown <= 0) {
      timer.cancel();
      await _executeEmergencyProtocol(service);
    }
  });
}

Future<void> _cancelAlert(ServiceInstance service) async {
  try {
    await SystemAlertWindow.closeSystemWindow();
    service.invoke('alertCancelled');
  } catch (e) {
    debugPrint('Error cancelling alert: $e');
  }
}

Future<void> _executeEmergencyProtocol(ServiceInstance service) async {
  try {
    // 1. Get current location
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
    }

    String locUrl = pos != null 
        ? "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}"
        : "Location unavailable";

    // 2. Fetch emergency contacts from Firestore
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

    // 3. Send SMS via SIM
    for (String phone in contacts) {
      try {
        await BackgroundSms.sendMessage(
          phoneNumber: phone,
          message: "EMERGENCY! Sustained heart risk detected for Smart Helmet user. Location: $locUrl. Please check on them immediately!",
        );
        debugPrint('SMS sent to $phone');
      } catch (e) {
        debugPrint('Error sending SMS to $phone: $e');
      }
    }

    // 4. Close overlay and notify main app
    await SystemAlertWindow.closeSystemWindow();
    service.invoke('emergencySent', {
      'contacts': contacts,
      'location': locUrl,
    });

    // 5. Log to Firestore
    try {
      await FirebaseFirestore.instance.collection('emergency_alerts').add({
        'alertType': 'BACKGROUND_EMERGENCY',
        'location': pos != null ? GeoPoint(pos.latitude, pos.longitude) : null,
        'googleMapsLink': locUrl,
        'contactsNotified': contacts,
        'alertMethod': 'BACKGROUND_SMS_SIM',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error logging alert: $e');
    }

  } catch (e) {
    debugPrint('Error in emergency protocol: $e');
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
        notificationChannelId: 'smart_helmet_emergency',
        initialNotificationTitle: 'Smart Helmet Emergency Monitor',
        initialNotificationContent: 'Monitoring your health in background',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onStart,
        onWillTerminate: () async {
          // Cleanup when service terminates
        },
      ),
    );
    
    service.startService();
  }

  static Future<void> requestPermissions() async {
    // Request SMS permission
    await BackgroundSms.requestSmsPermission();
    
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
    await FlutterBackgroundService().invoke('stopService');
  }
}
