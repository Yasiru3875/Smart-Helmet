// lib/services/whatsapp_alert_service.dart
// Sends emergency SMS messages automatically via Twilio API
// No hardware modules (SIM800L/GPS) required - uses phone's internet

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

/// Service for sending automated SMS emergency alerts via Twilio
/// 
/// Features:
/// - Fully automated (no user interaction required)
/// - Sends via Twilio SMS API through Firebase Cloud Functions
/// - Includes location, rider info, and emergency details
/// - Works without SIM800L or GPS hardware modules
class WhatsAppAlertService {
  // Firebase Cloud Function endpoint (to be configured)
  static const String _defaultCloudFunctionUrl = 
      'https://us-central1-your-project.cloudfunctions.net/sendSMS';
  
  String _cloudFunctionUrl = _defaultCloudFunctionUrl;
  
  /// Configure the cloud function URL (call this during app initialization)
  void configure({required String cloudFunctionUrl}) {
    _cloudFunctionUrl = cloudFunctionUrl;
  }

  /// Sends an emergency SMS message to all provided contacts automatically.
  /// 
  /// This method sends messages WITHOUT requiring user interaction.
  /// It calls the Firebase Cloud Function which uses Twilio SMS API.
  ///
  /// [contacts]     List of phone numbers with country code (e.g., +94771234567)
  /// [riderName]    User's display name
  /// [riskType]     Type of emergency (e.g., "CRITICAL cardiac risk", "Crash detected")
  /// [riskPercent]  Risk percentage from health model (0-100)
  /// [additionalInfo] Optional additional context
  ///
  /// Returns a map with success status and details per contact
  Future<Map<String, dynamic>> sendEmergencyAlert({
    required List<String> contacts,
    required String riderName,
    required String riskType,
    required int riskPercent,
    String? additionalInfo,
  }) async {
    if (contacts.isEmpty) {
      return {
        'success': false,
        'error': 'No emergency contacts configured',
        'results': {},
      };
    }

    // Get current location
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (e) {
      debugPrint('⚠️ Location unavailable: $e');
    }

    final now = DateTime.now();
    final timeStr = 
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} '
        '${now.day}/${now.month}/${now.year}';

    // Build emergency message (shortened for Twilio trial 160 char limit)
    final locationLine = position != null
        ? 'https://maps.google.com/?q=${position.latitude.toStringAsFixed(6)},${position.longitude.toStringAsFixed(6)}'
        : 'Loc unavailable';

    final message = 'EMERGENCY: $riderName - $riskType $riskPercent%. $locationLine';

    debugPrint('📱 WhatsApp Alert → ${contacts.length} contacts');
    debugPrint('📍 Location: $locationLine');

    // Send to each contact via Cloud Function
    final results = <String, dynamic>{};
    
    for (final contact in contacts) {
      try {
        final result = await _sendViaCloudFunction(
          phoneNumber: _formatPhoneNumber(contact),
          message: message,
        );
        results[contact] = result;
        
        if (result['success'] == true) {
          debugPrint('✅ WhatsApp sent to $contact');
        } else {
          debugPrint('❌ Failed to send to $contact: ${result['error']}');
        }
      } catch (e) {
        results[contact] = {'success': false, 'error': e.toString()};
        debugPrint('❌ Exception sending to $contact: $e');
      }
    }

    final allSuccess = results.values.every((r) => r['success'] == true);
    
    return {
      'success': allSuccess,
      'timestamp': DateTime.now().toIso8601String(),
      'location': position != null 
          ? {'lat': position.latitude, 'lng': position.longitude}
          : null,
      'results': results,
    };
  }

  /// Send a test WhatsApp message (for setup verification)
  Future<Map<String, dynamic>> sendTestMessage({
    required String phoneNumber,
    required String riderName,
  }) async {
    final message = 'TEST: Smart Helmet SOS for $riderName working!';

    return await _sendViaCloudFunction(
      phoneNumber: _formatPhoneNumber(phoneNumber),
      message: message,
    );
  }

  /// Internal method to call Firebase Cloud Function
  Future<Map<String, dynamic>> _sendViaCloudFunction({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_cloudFunctionUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'to': phoneNumber,
          'message': message,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {
          'success': true,
          'response': jsonDecode(response.body),
        };
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } on TimeoutException {
      return {
        'success': false,
        'error': 'Request timeout - check internet connection',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// Format phone number to E.164 format (required by Twilio)
  /// Handles common Sri Lankan and international formats
  String _formatPhoneNumber(String number) {
    // Remove all non-digit characters
    var digits = number.replaceAll(RegExp(r'\D'), '');
    
    // Handle Sri Lankan numbers
    if (digits.startsWith('0') && digits.length == 10) {
      // 0712345678 -> +94712345678
      digits = '94${digits.substring(1)}';
    }
    
    // Ensure + prefix for international format
    if (!digits.startsWith('+')) {
      digits = '+$digits';
    }
    
    return digits;
  }

  /// Validate that the service is properly configured
  bool get isConfigured => 
      _cloudFunctionUrl != _defaultCloudFunctionUrl &&
      _cloudFunctionUrl.isNotEmpty;

  /// Get current configuration status
  Map<String, dynamic> getConfigStatus() {
    return {
      'configured': isConfigured,
      'cloudFunctionUrl': _cloudFunctionUrl == _defaultCloudFunctionUrl 
          ? 'NOT_SET (using default)'
          : 'CONFIGURED',
    };
  }
}

/// Extension for easy integration with SOSController
extension WhatsAppAlertServiceExtension on WhatsAppAlertService {
  /// Quick emergency send with minimal parameters
  Future<void> sendQuickSOS({
    required List<String> contacts,
    required String riderName,
  }) async {
    await sendEmergencyAlert(
      contacts: contacts,
      riderName: riderName,
      riskType: 'MANUAL SOS TRIGGERED',
      riskPercent: 100,
      additionalInfo: 'Rider manually triggered emergency SOS',
    );
  }
}
