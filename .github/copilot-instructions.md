# Copilot Instructions for Smart Helmet App

## Project Overview
Smart Helmet is a Flutter-based mobile application for cyclists and motorcyclists that monitors riding behavior, detects risky turns via IMU sensors, tracks health metrics via EEG/biometric sensors, and provides post-journey analytics via Firebase.

## Architecture Layers

### 1. **State Management (Provider Pattern)**
- **Primary Tool**: `provider` package with `ChangeNotifier` and `MultiProvider`
- **Initialization**: `main.dart` sets up three core providers:
  - `AuthService`: Firebase authentication state
  - `BluetoothManager`: Bluetooth connection management
  - `JourneyProvider`: Active journey data and turn events
- **Key Pattern**: All providers must be created in `MultiProvider` at app root (`lib/main.dart`). Widgets access via `Provider.of<T>(context, listen: false)` or `Consumer<T>`
- **Example**: `Member3Page` accesses `JourneyProvider` to record turn events during active journeys (line 374 in member3_page.dart)

### 2. **Services Layer** (`lib/services/`)
Services handle business logic and external integrations:
- **AuthService**: Firebase Auth integration, user session management
- **BluetoothManager**: ESP32 connection, BLE/Serial communication (from `flutter_bluetooth_serial`)
- **JourneyService**: Firestore CRUD operations for journey data
  - **Pattern**: Service methods return `Future` and handle errors gracefully with `print()` and `rethrow`
  - **Example**: `getAllJourneys()` queries Firestore with `orderBy('startTime', descending: true)`

### 3. **Models Layer** (`lib/models/`)
Data classes with serialization support:
- **JourneyData**: Core entity with `toMap()`/`fromMap()` for Firestore serialization
- **TurnEvent**: Nested model with severity ("sharp"/"risky"), turnRate (°/s), GPS coords, timestamp
- **SensorReading**: Health metrics (heartRate, temperature, stressLevel)
- **Key Pattern**: DateTime fields serialize to ISO8601 strings in Firestore, parse back with `DateTime.parse()`

### 4. **Screens/UI Layer** (`lib/screens/`)
Hierarchical organization:
- `screens/auth/` - Login/authentication UI
- `screens/home/` - Main app container
- `screens/home/members/` - Member-specific dashboards
  - `Post_Journey/member3_page.dart` - Risk assessment (tabs: journey history + live monitoring)
- **Pattern**: Stateful widgets use `setState()` for local UI state; pull from providers for shared app state

## Critical Data Flows

### Journey Recording Flow
1. User starts journey via HomeScreen (GPS location captured)
2. `JourneyProvider.startJourney()` creates new `JourneyData` instance
3. Live IMU data from ESP32 streams via `BluetoothManager` → parsed to JSON → `_processIMUData()`
4. Turn events detected via `gyroZ` threshold checks → `journeyProvider.addTurnEvent()` adds to current journey
5. On journey end: `JourneyProvider.endJourney()` calculates aggregates (sharp/risky counts) → `JourneyService.saveJourney()` persists to Firestore

### IMU Data Processing (Real-time)
- **Source**: ESP32 sends newline-delimited JSON: `{"gyroX":0.5,"gyroY":-0.2,"gyroZ":120.5,...}`
- **Parser**: `_parseIMUData()` → `json.decode()` → `_processIMUData()` updates local state + journey provider
- **Thresholds**: 
  - Sharp turn: gyroZ.abs() > 100°/s
  - Risky turn: gyroZ.abs() > 150°/s
- **Location**: [Member3Page#_processIMUData](lib/screens/home/members/Post_Journey/member3_page.dart)

## Key Dependencies & Configuration

### Firebase
- **Config**: `lib/firebase_options.dart` (auto-generated via `flutterfire configure`)
- **Collections**: 
  - `journeys/` - JourneyData documents with nested `turnEvents[]` and `sensorReadings[]`
  - Ordered by `startTime` descending for recency
- **Auth**: Firebase Auth manages user sessions; `AuthService` wraps the SDK

### Bluetooth
- **Library**: `flutter_bluetooth_serial` (classic Bluetooth, not BLE)
- **Flow**: Scan bonded devices → match device name "SmartHelmet_ESP32" → connect → listen to input stream
- **Data Format**: UTF-8 encoded newline-delimited JSON from ESP32
- **Permissions** (required): Bluetooth, BluetoothConnect, BluetoothScan, Location (Android 12+)

### ML/Sensing
- **EEG Model**: `assets/eeg_stress_model_final.tflite` (loaded via `tflite_flutter`)
- **FFT**: `fftea` package for signal processing
- **Purpose**: Real-time stress level inference from biometric sensors

### UI & Visualization
- **Charts**: `fl_chart` for post-journey analytics graphs
- **Text-to-Speech**: `flutter_tts` for notifications/alerts
- **Maps**: `google_maps_flutter` for route visualization (integrated in journey details)

## Common Patterns & Conventions

### Error Handling
- **Async Errors**: Catch and `print()` errors, optionally `rethrow` for upstream handling
- **UI Errors**: Show `SnackBar` via `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))`
- **Example**: `JourneyService.getAllJourneys()` returns empty list `[]` on error, logged to console

### Imports & Package Structure
- **Use package imports, not relative paths**: 
  - ✅ `import 'package:smart_helmet_app/models/journey_model.dart';`
  - ❌ `import '../models/journey_model.dart';`
- **Organize by feature**: Services, models, providers all have dedicated folders

### DateTime Handling
- **Firestore Serialization**: Use `.toIso8601String()` for save, `DateTime.parse()` for load
- **Duration Calculation**: `journey.endTime?.difference(journey.startTime)` for elapsed time
- **UI Formatting**: Use `intl` package (imported) with `DateFormat('MMM dd, yyyy • HH:mm').format(date)`

### Provider Patterns
- **Read without listening**: `Provider.of<T>(context, listen: false)` (used in `_processIMUData()`)
- **Listen for updates**: `Consumer<T>` widget or `Provider.of<T>(context)` for rebuilds
- **Notify changes**: Call `notifyListeners()` after state mutations in ChangeNotifier

## Testing & Debugging

### Hot Restart vs. Hot Reload
- **Hot Reload**: Works for UI changes; **does NOT reinitialize providers**
- **Hot Restart**: Required after adding new providers to `MultiProvider` (e.g., when fixing JourneyProvider error)
- **Command**: `R` (hot reload), `Shift+R` (hot restart) in Flutter run terminal

### Common Runtime Errors
- **ProviderNotFoundError**: Provider not in `MultiProvider` or wrong context scope
  - Fix: Add provider to `main.dart` MultiProvider, then hot restart
- **JSON decode errors**: Malformed data from ESP32 or incomplete message buffering
  - Debug: Check `_dataBuffer` accumulation; ensure newline-delimited JSON format

### Firebase Emulator (Optional Setup)
- Config in `firebase.json`; useful for local Firestore testing without hitting live database

## Workflow for Common Tasks

### Adding a New Screen
1. Create file in `lib/screens/[category]/[name]_page.dart`
2. If needs shared state: access via `Provider.of<RequiredProvider>(context)`
3. If needs new state: create `ChangeNotifier` in `lib/providers/`, add to `main.dart` MultiProvider
4. Organize child widgets as separate methods (e.g., `_buildConnectionCard()`)

### Recording New Journey Data
1. Call `journeyProvider.startJourney(startLoc, dest)` at journey start
2. As IMU/sensor data arrives, call `journeyProvider.addTurnEvent()` or `addSensorReading()`
3. On journey end: call `endJourney()`, then `journeyService.saveJourney()`
4. UI auto-updates via provider listeners

### Querying Journey History
- Use `JourneyService.getAllJourneys()` → returns sorted `List<JourneyData>`
- Parse nested `turnEvents` and `sensorReadings` for detailed analysis
- Example: [Member3Page#_buildJourneyHistoryTab](lib/screens/home/members/Post_Journey/member3_page.dart) (~line 530)

## File Navigation Guide

```
lib/
├── main.dart                          # App entry, MultiProvider setup
├── firebase_options.dart              # Firebase config (auto-generated)
├── models/
│   └── journey_model.dart             # JourneyData, TurnEvent, SensorReading
├── providers/
│   └── journey_provider.dart          # Journey state management
├── services/
│   ├── auth_service.dart              # Firebase Auth wrapper
│   ├── bluetooth_manager.dart         # ESP32 connection logic
│   └── journey_service.dart           # Firestore CRUD
└── screens/
    ├── auth/
    │   └── login_screen.dart          # Authentication UI
    └── home/
        ├── home_screen.dart           # Main app shell
        └── members/
            ├── Health_Monitoring/
            │   └── member1_page.dart  # EEG/health dashboard
            └── Post_Journey/
                └── member3_page.dart  # Risk assessment (MAIN REFERENCE)
```

---

**Last Updated**: December 2025  
**Key Maintainers**: Smart Helmet development team
