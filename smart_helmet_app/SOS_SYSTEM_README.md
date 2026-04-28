# SOS Emergency System - Smart Helmet

## Overview
Production-level SOS emergency system with smart cancellation features integrated into the Smart Helmet app. The system automatically detects emergencies from ESP32 helmet sensors and provides multiple cancellation methods to prevent false alarms.

## Architecture

### State Management
- **Provider** for state management (already integrated in the app)

### Layers
1. **UI Layer** - Emergency Screen
2. **Application Layer** - SOS Controller
3. **Domain Layer** - SOS State Model
4. **Data Layer** - Bluetooth, Sensors, Voice, Alert Services

## Features

### 1. Bluetooth Integration (ESP32 ↔ App)
- **File**: `lib/services/sos_bluetooth_service.dart`
- **ESP32 Events**:
  - `EMERGENCY_TRIGGERED` - Triggers SOS countdown
  - `SOS_CANCELLED` - ESP32 cancelled the SOS
- **Integration**: Connect with existing BLE manager

### 2. SOS Controller (Core Logic)
- **File**: `lib/providers/sos_controller.dart`
- **15-second countdown** with automatic SOS send
- **Smart cancellation** based on rider activity
- **State management** using Provider

### 3. Alert System
- **File**: `lib/services/sos_alert_service.dart`
- **Vibration pattern**: `[0, 500, 500, 500]`
- **Local notifications** with ongoing alert
- **Emergency alert sending** (API/SMS integration required)

### 4. Voice Cancellation System
- **File**: `lib/services/sos_voice_service.dart`
- **Cancellation phrases**:
  - "cancel"
  - "cancel sos"
  - "stop alert"
  - "stop"
  - "i'm okay"
  - "fine"
  - "help"
- **Speech-to-text** using `speech_to_text` package

### 5. Motion-Based Auto Cancel
- **File**: `lib/services/sos_motion_service.dart`
- **GPS Speed Monitoring**: Threshold = 15 km/h
- **Accelerometer**: Detects smooth motion vs crash
- **Double Tap Detection**: Tap helmet twice within 500ms
- **Gyroscope**: Helps detect sudden movements

### 6. Emergency UI Screen
- **File**: `lib/screens/home/emergency_screen.dart`
- **Full red background** for visibility
- **Large countdown timer** (120px)
- **Status indicators**:
  - Voice listening active
  - Motion monitoring active
- **Manual cancel button**

## Installation

### 1. Add Dependencies
Already added to `pubspec.yaml`:
```yaml
speech_to_text: ^6.6.0
sensors_plus: ^4.0.2
flutter_local_notifications: ^16.3.2
vibration: ^2.0.0
```

### 2. Run Flutter Pub Get
```bash
flutter pub get
```

### 3. Configure Permissions

#### Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<!-- Location permissions for GPS -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- Microphone permission for voice cancellation -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />

<!-- Notification permission -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Vibration permission -->
<uses-permission android:name="android.permission.VIBRATE" />
```

#### iOS (`ios/Runner/Info.plist`)
```xml
<!-- Location permissions -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access to monitor rider speed and detect normal motion.</string>

<!-- Microphone permission -->
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for voice cancellation of emergency alerts.</string>

<!-- Notification permission -->
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

## Usage

### Automatic Trigger
1. ESP32 detects emergency (crash, fall, etc.)
2. Sends `EMERGENCY_TRIGGERED` via Bluetooth
3. App receives event and starts SOS countdown
4. Emergency screen automatically appears

### Manual Cancel Options
1. **Voice**: Say "cancel sos" or "i'm okay"
2. **Motion**: Ride normally (speed > 15 km/h, smooth acceleration)
3. **Double Tap**: Tap helmet twice within 500ms
4. **Button**: Tap "CANCEL SOS" on emergency screen

### Countdown Timeline
| Time | Action |
|------|--------|
| 0-5s | Beep + vibration |
| 5-15s | Voice warning |
| During | Check movement + speed |
| 15s | Send SOS if not cancelled |

## Integration with Existing Code

### Main App Integration
- **SOSController** added to provider tree in `main.dart`
- **EmergencyScreen** route added to routes
- **HomeScreen** listens for SOS state changes and navigates automatically

### Bluetooth Integration
Connect with existing BLE manager:
```dart
// In your BluetoothManager or BLE setup
final sosBluetoothService = SOSBluetoothService();
sosBluetoothService.setDevice(bluetoothDevice);
sosBluetoothService.setCharactersistics(txCharacteristic, rxCharacteristic);
```

## Testing Strategy

### Test Cases
1. **False crash simulation** - Drop helmet, verify auto-cancel
2. **Real crash simulation** - Simulate crash, verify SOS sent
3. **Riding after trigger** - Start riding, verify auto-cancel
4. **Voice command** - Test voice cancellation in noisy environment
5. **Double tap** - Test tap detection sensitivity
6. **GPS accuracy** - Test speed detection at various speeds

### Manual Testing
```dart
// In SOSController, add test method:
void testSOS() {
  startSOS(); // Triggers countdown and all monitoring
}
```

## Production Improvements

### Required for Production
- [ ] **Background service** - Keep SOS active when app is backgrounded
- [ ] **Offline fallback** - Store SOS locally if no network
- [ ] **Retry logic** - Retry Bluetooth connection if lost
- [ ] **Battery optimization** - Handle low battery scenarios
- [ ] **Emergency API** - Implement actual SOS sending (SMS/API)
- [ ] **Emergency contacts** - Load from Firebase/Settings
- [ ] **Location sharing** - Send current location with SOS

### Optional Enhancements
- [ ] **Multiple emergency contacts** - Support multiple recipients
- [ ] **Emergency types** - Crash, Medical, Theft, etc.
- [ ] **Audio recording** - Record audio during emergency
- [ ] **Camera capture** - Take photo during emergency
- [ ] **Family notification** - Notify family members via Firebase
- [ ] **Emergency services** - Direct API to emergency services

## Troubleshooting

### Voice Not Working
- Check microphone permissions
- Ensure speech recognition is available on device
- Test in quiet environment first

### Motion Detection Issues
- Check location permissions
- Ensure GPS is enabled
- Verify speed threshold (currently 15 km/h)

### Bluetooth Not Connecting
- Ensure ESP32 is paired
- Check Bluetooth permissions
- Verify characteristics are set correctly

### Notifications Not Showing
- Check notification permissions
- Verify notification channel is created
- Test with app in foreground first

## File Structure

```
lib/
├── models/
│   └── sos_state.dart
├── providers/
│   └── sos_controller.dart
├── services/
│   ├── sos_bluetooth_service.dart
│   ├── sos_alert_service.dart
│   ├── sos_voice_service.dart
│   └── sos_motion_service.dart
└── screens/
    └── home/
        └── emergency_screen.dart
```

## Configuration

### Adjust Countdown Duration
In `lib/providers/sos_controller.dart`:
```dart
_state = _state.copyWith(
  isActive: true,
  countdown: 15, // Change this value
  status: 'Emergency Detected',
);
```

### Adjust Speed Threshold
In `lib/services/sos_motion_service.dart`:
```dart
static const double speedThreshold = 15.0; // km/h
```

### Adjust Vibration Pattern
In `lib/services/sos_alert_service.dart`:
```dart
Vibration.vibrate(pattern: [0, 500, 500, 500]);
```

### Add Cancellation Phrases
In `lib/services/sos_voice_service.dart`:
```dart
final cancellationPhrases = [
  'cancel',
  'cancel sos',
  // Add more phrases here
];
```

## Support

For issues or questions:
1. Check this README for troubleshooting
2. Review file-specific comments in source code
3. Test each service independently
4. Verify all permissions are granted

## License

Part of the Smart Helmet project.
