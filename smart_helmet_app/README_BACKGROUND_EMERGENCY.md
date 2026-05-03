# Background Emergency Service Integration

## Overview
This document describes the integration of a background SIM-based emergency alert system for the Smart Helmet app. The system ensures continuous monitoring of vital signs and automatic SMS emergency alerts even when the app is killed or the phone is locked.

## Architecture

### 1. Background Service Components

#### BackgroundEmergencyService
- **Location**: `lib/services/background_emergency_service.dart`
- **Purpose**: Manages the background service that monitors health metrics and triggers emergency alerts
- **Key Features**:
  - Runs in a background isolate with Firebase initialization
  - Monitors heart rate, temperature, and risk percentage from shared preferences
  - Implements 30-second sustained risk detection
  - Shows system alert overlay for cancellation window
  - Sends SMS via SIM with location data

#### AlertEngine Integration
- **Location**: `lib/providers/alert_engine.dart`
- **Purpose**: Integrates background service with existing health monitoring
- **Key Features**:
  - Initializes background service on first risk reading
  - Updates background service with latest sensor data
  - Maintains existing foreground alert functionality

### 2. Permission Management

#### PermissionHelper
- **Location**: `lib/services/permission_helper.dart`
- **Purpose**: Handles all emergency-related permissions
- **Permissions Required**:
  - SEND_SMS - Send emergency alerts
  - SYSTEM_ALERT_WINDOW - Show emergency overlay
  - ACCESS_FINE_LOCATION - Get user location
  - READ_PHONE_STATE - Background monitoring
  - FOREGROUND_SERVICE - Background execution

## Installation & Setup

### 1. Dependencies
Add to `pubspec.yaml`:
```yaml
flutter_background_service: ^5.0.0
background_sms: ^0.0.1
system_alert_window: ^1.4.0
```

### 2. Android Permissions
Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.SEND_SMS" />
<uses-permission android:name="android.permission.READ_PHONE_STATE" />
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

### 3. Service Configuration
Add to `AndroidManifest.xml` inside `<application>`:
```xml
<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:foregroundServiceType="specialUse"
    android:enabled="true"
    android:exported="false" />
```

## Emergency Alert Flow

### Phase 1: Risk Detection
- Background service monitors sensor data every second
- Evaluates high risk conditions:
  - Heart rate > 120 BPM
  - Temperature > 38.0°C
  - Risk percentage > 75%
  - Combined conditions (HR > 110 + Temp > 38°C)

### Phase 2: Sustained Risk (30 seconds)
- Continuous high risk for 30 seconds triggers alert sequence
- Shows system alert overlay with countdown
- User can cancel alert within 30 seconds

### Phase 3: Emergency Protocol
- Fetches current GPS location
- Retrieves emergency contacts from Firestore
- Sends SMS alerts with location via SIM
- Logs alert to Firestore
- Closes overlay window

## Testing Instructions

### 1. Android 15/16 Permission Setup
For sideloaded apps, SMS permission requires manual enabling:
1. Long-press app icon → Tap (i) icon
2. Tap three-dot menu (⋮) → "Allow restricted settings"
3. Go to Permissions > SMS → Select "Allow"

### 2. Background Service Testing
1. Install app and grant all permissions
2. Start health monitoring
3. Simulate high risk conditions (HR > 120 BPM)
4. Verify 30-second sustained detection
5. Test cancellation window
6. Verify SMS dispatch with location

### 3. App Kill Test
1. Start health monitoring
2. Kill app from recent apps
3. Verify background service continues monitoring
4. Trigger high risk conditions
5. Verify emergency alert still works

## Key Features

### ✅ Background Persistence
- Service continues running even when app is killed
- Uses foreground service with notification
- Survives phone lock and app swipes

### ✅ System Alert Overlay
- Shows over lock screen and other apps
- 30-second countdown timer
- Cancel button for false alarms

### ✅ SMS Emergency Dispatch
- Uses native SIM for reliability
- Includes Google Maps location link
- Fetches contacts from Firestore
- Logs all alerts to database

### ✅ Dual Monitoring
- Foreground alerts for active use
- Background alerts for continuous protection
- Seamless integration with existing AlertEngine

## Troubleshooting

### Common Issues

1. **Background Service Not Starting**
   - Check all permissions are granted
   - Verify Firebase initialization
   - Check AndroidManifest.xml configuration

2. **SMS Not Sending**
   - Verify SEND_SMS permission
   - Check restricted settings on Android 15+
   - Ensure SIM card is active

3. **Overlay Not Showing**
   - Check SYSTEM_ALERT_WINDOW permission
   - Verify overlay settings in device
   - Check for other apps blocking overlay

4. **Location Not Working**
   - Check location permissions
   - Ensure GPS is enabled
   - Verify location accuracy settings

### Debug Logs
Enable debug logs to troubleshoot:
```dart
debugPrint('Background service status: $status');
debugPrint('Sensor data: HR=$hr, Temp=$temp, Risk=$risk%');
debugPrint('SMS sent to: $phone');
```

## Future Enhancements

1. **Battery Optimization**: Implement adaptive monitoring to reduce battery usage
2. **Multiple Alert Methods**: Add email and push notification fallbacks
3. **Voice Alerts**: Add text-to-speech emergency announcements
4. **Contact Verification**: Add contact confirmation before SMS dispatch
5. **Network Fallback**: Use internet SMS when SIM is unavailable

## Security Considerations

1. **Privacy**: Location data only sent during emergencies
2. **Data Protection**: All emergency logs encrypted in Firestore
3. **False Alarms**: Multiple cancellation methods available
4. **Permission Management**: Minimal permissions requested
5. **User Control**: Easy disable option in settings

## Support

For issues with the background emergency service:
1. Check permission status in app settings
2. Verify device compatibility (Android 8.0+)
3. Test with different SIM carriers
4. Review debug logs in console
5. Contact development team with device details
