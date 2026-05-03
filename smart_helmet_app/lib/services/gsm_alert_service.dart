// lib/services/gsm_alert_service.dart
// Sends emergency SMS via SmartHelmet_ESP32 → SIM800L GSM module
// with fallback to direct phone SMS via url_launcher

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bluetooth_manager.dart';

class GsmAlertService {
  static const String _helmetDeviceName = 'SmartHelmet_ESP32';

  /// Sends an emergency SMS to all provided contacts.
  ///
  /// Primary path: BluetoothManager → SmartHelmet_ESP32 → SIM800L
  /// Fallback path: url_launcher sms: URI (opens native SMS app)
  ///
  /// [contacts]     List of phone numbers (E.164 format preferred)
  /// [riderName]    User's display name
  /// [riskType]     e.g. "CRITICAL cardiac risk", "High heart rate"
  /// [riskPercent]  Risk percentage from model (0-100)
  /// [lat] / [lng]  Current GPS coordinates (null if unavailable)
  /// [btManager]    Shared BluetoothManager instance
  ///
  /// Returns null on success, or an error string.
  Future<String?> sendAlert({
    required List<String> contacts,
    required String riderName,
    required String riskType,
    required int riskPercent,
    required double? lat,
    required double? lng,
    required BluetoothManager btManager,
  }) async {
    if (contacts.isEmpty) {
      return 'No emergency contacts configured';
    }

    final locationLine = (lat != null && lng != null)
        ? 'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'
        : 'Location unavailable';

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} '
        '${now.day}/${now.month}/${now.year}';

    final message = '⚠️ EMERGENCY ALERT\n'
        'Rider: $riderName\n'
        'Status: $riskType detected\n'
        'Risk Level: $riskPercent%\n'
        '📍 Live Location: $locationLine\n'
        'Time: $timeStr\n'
        'This is an automated alert from Smart Helmet.';

    debugPrint('📡 GSM Alert → contacts: $contacts\nMessage: $message');

    // ── Primary: via SmartHelmet_ESP32 BT → SIM800L ──────────────────────
    bool sentViaBt = false;
    if (btManager.isConnected(_helmetDeviceName)) {
      try {
        btManager.sendJson(_helmetDeviceName, {
          'cmd': 'SEND_SMS',
          'numbers': contacts,
          'message': message,
        });
        sentViaBt = true;
        debugPrint('✅ SMS command sent to SmartHelmet_ESP32');
      } catch (e) {
        debugPrint('⚠️ BT send failed: $e  — falling back to phone SMS');
      }
    } else {
      debugPrint(
          '⚠️ SmartHelmet_ESP32 not connected — falling back to phone SMS');
    }

    // ── Fallback: phone SMS via url_launcher ──────────────────────────────
    if (!sentViaBt) {
      for (final number in contacts) {
        try {
          final uri = Uri.parse(
              'sms:$number?body=${Uri.encodeComponent(message)}');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        } catch (e) {
          debugPrint('❌ Fallback SMS to $number failed: $e');
        }
      }
    }

    return null; // success
  }
}
