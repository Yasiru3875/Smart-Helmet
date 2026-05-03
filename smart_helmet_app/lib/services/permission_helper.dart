import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:background_sms/background_sms.dart';
import 'package:system_alert_window/system_alert_window.dart';
import 'package:geolocator/geolocator.dart';

class PermissionHelper {
  static Future<bool> requestAllEmergencyPermissions() async {
    bool allGranted = true;

    // 1. SMS Permission
    try {
      final smsStatus = await BackgroundSms.requestSmsPermission();
      if (smsStatus != SmsPermissionState.granted) {
        debugPrint('❌ SMS permission not granted');
        allGranted = false;
      } else {
        debugPrint('✅ SMS permission granted');
      }
    } catch (e) {
      debugPrint('❌ Error requesting SMS permission: $e');
      allGranted = false;
    }

    // 2. System Alert Window Permission
    try {
      final overlayStatus = await SystemAlertWindow.requestPermissions(
        prefMode: SystemWindowPrefMode.OVERLAY,
      );
      if (overlayStatus != true) {
        debugPrint('❌ System alert window permission not granted');
        allGranted = false;
      } else {
        debugPrint('✅ System alert window permission granted');
      }
    } catch (e) {
      debugPrint('❌ Error requesting overlay permission: $e');
      allGranted = false;
    }

    // 3. Location Permission
    try {
      final locationStatus = await Geolocator.requestPermission();
      if (locationStatus == LocationPermission.denied || 
          locationStatus == LocationPermission.deniedForever) {
        debugPrint('❌ Location permission not granted');
        allGranted = false;
      } else {
        debugPrint('✅ Location permission granted');
      }
    } catch (e) {
      debugPrint('❌ Error requesting location permission: $e');
      allGranted = false;
    }

    // 4. Phone State Permission (for Android)
    try {
      final phoneStatus = await Permission.phone.request();
      if (phoneStatus != PermissionStatus.granted) {
        debugPrint('❌ Phone state permission not granted');
        allGranted = false;
      } else {
        debugPrint('✅ Phone state permission granted');
      }
    } catch (e) {
      debugPrint('❌ Error requesting phone permission: $e');
      allGranted = false;
    }

    return allGranted;
  }

  static Future<void> showPermissionDialog(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Emergency Permissions Required'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The Smart Helmet app requires the following permissions for emergency monitoring:',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 16),
              Text('• SMS - Send emergency alerts', style: TextStyle(fontSize: 12)),
              Text('• System Alert - Show emergency overlay', style: TextStyle(fontSize: 12)),
              Text('• Location - Send your location in emergencies', style: TextStyle(fontSize: 12)),
              Text('• Phone State - Background monitoring', style: TextStyle(fontSize: 12)),
              SizedBox(height: 16),
              Text(
                'These permissions are critical for the emergency alert system to work when the app is in the background.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await requestAllEmergencyPermissions();
              },
              child: const Text('Grant Permissions'),
            ),
          ],
        );
      },
    );
  }

  static Future<bool> checkAllPermissions() async {
    try {
      // Check SMS permission
      final smsStatus = await BackgroundSms.getSmsPermissionStatus();
      if (smsStatus != SmsPermissionState.granted) return false;

      // Check overlay permission
      final overlayStatus = await SystemAlertWindow.checkPermissions();
      if (overlayStatus != true) return false;

      // Check location permission
      final locationStatus = await Geolocator.checkPermission();
      if (locationStatus == LocationPermission.denied || 
          locationStatus == LocationPermission.deniedForever) return false;

      // Check phone permission
      final phoneStatus = await Permission.phone.status;
      if (phoneStatus != PermissionStatus.granted) return false;

      return true;
    } catch (e) {
      debugPrint('❌ Error checking permissions: $e');
      return false;
    }
  }
}
