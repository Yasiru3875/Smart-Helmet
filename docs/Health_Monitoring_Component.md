# Health Monitoring Component Documentation

## Overview

The Health Monitoring component is a comprehensive real-time health tracking system designed for the Smart Helmet application. It provides continuous vital signs monitoring, AI-powered risk assessment, emotional analytics, and detailed health reporting capabilities.

## Architecture

### Core Components

1. **Member1Page** (`member1_page.dart`) - Main health monitoring interface
2. **WeeklyReportPage** (`weekly_report_page.dart`) - Comprehensive health analytics and reporting
3. **Medical UI Components** - Professional medical-grade UI components
4. **Real-time Data Processing** - Sensor data processing and visualization

### Key Features

#### 🏥 Real-time Vital Signs Monitoring
- **Heart Rate Monitoring**: Real-time BPM tracking with risk assessment
- **Body Temperature Monitoring**: Continuous temperature monitoring with alerts
- **Bluetooth Connectivity**: Auto-connect and reconnection to SmartWatch_ESP32
- **Live Data Visualization**: Real-time charts with 30-point rolling window

#### 🧠 AI-Powered Risk Assessment
- **TFLite Model Integration**: Heart attack risk prediction using TensorFlow Lite
- **Dynamic Risk Calculation**: 3-tier risk classification (Normal/Medium/High Risk)
- **Emotion-Aware Risk**: Risk adjustment based on emotional state
- **User Profile Integration**: Personalized risk assessment using user demographics

#### 📊 Advanced Analytics
- **7-Day Trend Analysis**: Emotional and vital sign trends
- **EEG Brain Activity Monitor**: Real-time brain wave monitoring
- **Stress Level Tracking**: Continuous stress assessment
- **Health Score Calculation**: Overall health status scoring

#### 📋 Comprehensive Reporting
- **Weekly Health Reports**: Detailed PDF reports with medical recommendations
- **Custom Period Selection**: Weekly, monthly, or custom date ranges
- **Export Capabilities**: PDF generation and sharing
- **Clinical Data Summaries**: Daily averages and statistics

#### 🔔 Intelligent Alerts
- **Sustained Risk Monitoring**: 30-second sustained risk detection
- **Personalized Recommendations**: Context-aware health recommendations
- **Real-time Notifications**: Immediate alerts for critical conditions

#### 🚨 SOS Emergency System
- **Automatic SOS Trigger**: Heart attack risk > 70% for 30+ seconds
- **Manual SOS Activation**: Physical button or UI emergency trigger
- **Emergency Contact Notification**: SMS/email to predefined contacts
- **Location Sharing**: Real-time GPS coordinates with emergency alerts
- **Medical Data Transmission**: Critical vitals sent to emergency services
- **Emergency Response Integration**: Direct connection to emergency medical services
- **SOS Status Tracking**: Real-time monitoring of emergency response
- **Post-Incident Reporting**: Automatic incident documentation and follow-up

## Technical Implementation

### Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  tflite_flutter: ^latest
  fl_chart: ^latest
  provider: ^latest
  cloud_firestore: ^latest
  firebase_auth: ^latest
  geolocator: ^latest
  intl: ^latest
  pdf: ^latest
  printing: ^latest
  share_plus: ^latest
  url_launcher: ^latest      # For emergency calls
  sms_launcher: ^latest       # For emergency SMS
  flutter_email_sender: ^latest # For emergency emails
  permission_handler: ^latest  # For emergency permissions
```

### Data Models

#### Health Reading Model
```dart
class HealthReading {
  final DateTime timestamp;
  final double heartRate;
  final double bodyTemperature;
  final String riskLevel;
  final Color riskColor;
  final String userId;
  final String deviceName;
  final GeoPoint? location;
  final String? rideId;
}
```

#### Daily Summary Model
```dart
class DailySummary {
  final DateTime date;
  final double avgHR;
  final double avgTemp;
  final double minHR;
  final double maxHR;
  final double minTemp;
  final double maxTemp;
  final int readingsCount;
  final double highRiskPercent;
}
```

#### SOS Emergency Model
```dart
class SOSEvent {
  final String id;
  final DateTime timestamp;
  final SOSStatus status;
  final GeoPoint location;
  final double heartRate;
  final double bodyTemperature;
  final int riskPercentage;
  final String triggerType; // 'automatic' or 'manual'
  final List<EmergencyContact> notifiedContacts;
  final String? emergencyServiceId;
  final DateTime? resolvedAt;
  final String? notes;
}

class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final String email;
  final bool isPrimary;
  final String relationship;
  final DateTime notifiedAt;
}
```

### Core Services

#### BluetoothManager Integration
- Auto-discovery of ESP32 devices
- Real-time data streaming
- Connection retry logic (max 3 attempts)
- Flexible device matching (ESP32, SmartWatch, Helmet, HR)

#### TFLite Model Integration
- **Model**: `assets/heart_attack_model.tflite`
- **Input Features**: [HR, Temp, Age, Gender, Weight, Height, BMI]
- **Preprocessing**: StandardScaler normalization
- **Output**: Heart attack risk probability (0-100%)

#### Firestore Integration
- **Collection**: `health_readings`
- **Real-time Updates**: Live data synchronization
- **Query Optimization**: Memory-based date filtering
- **Data Aliases**: Multiple field names for robustness

### UI Components

#### MedicalVitalCard
Professional medical-grade vital sign display with:
- Semi-circular gauge visualization
- Animated icons (heart, thermometer)
- Dynamic color coding based on risk levels
- Real-time percentage indicators

#### BrainActivityMonitor
EEG brain wave visualization featuring:
- 5 brainwave bands (Alpha, Beta, Theta, Delta, Gamma)
- Real-time power level indicators
- Focus and calm metrics
- Remote feed status indicators

#### EmotionalStateDisplay
Live emotional state monitoring with:
- Real-time emotion detection
- Emoji-based visualization
- Color-coded emotional states
- EEG sync status indicators

## Configuration

### Bluetooth Device Setup
```dart
static const String deviceName = "SmartWatch_ESP32";
```

### Risk Assessment Thresholds
```dart
// Heart Rate Risk Levels
- High Risk: HR > 120 or < 40 bpm
- Medium Risk: 100-120 bpm or 50-59 bpm  
- Normal: 60-100 bpm

// Temperature Risk Levels
- High Risk: > 38.0°C
- Medium Risk: 37.3-38.0°C
- Normal: 36.1-37.2°C
```

### TFLite Model Configuration
```dart
// Feature Standardization
List<double> means = [79.317, 36.748, 53.412, 0.491, 74.969, 1.751, 24.954];
List<double> scales = [11.491, 0.430, 20.797, 0.500, 14.388, 0.144, 6.331];

// Risk Classification
- High Risk: > 70% probability
- Medium Risk: 30-70% probability  
- Normal: < 30% probability
```

### SOS System Configuration
```dart
// Automatic SOS Trigger Thresholds
const int sosRiskThreshold = 70; // Heart attack risk percentage
const Duration sosSustainedDuration = Duration(seconds: 30); // Sustained high risk

// Emergency Contact Configuration
class EmergencyContact {
  final String name;
  final String phone;
  final String email;
  final bool isPrimary;
}

// SOS Status States
enum SOSStatus {
  idle,           // No emergency
  monitoring,      // High risk detected, monitoring
  triggered,       // SOS activated
  responding,      // Emergency services notified
  resolved        // Emergency resolved
}
```

## API Reference

### Core Methods

#### `_parseAndUpdateData(String jsonString)`
Processes incoming Bluetooth sensor data:
- JSON parsing with error handling
- Moving average filter for heart rate
- Real-time UI updates
- Firestore data persistence

#### `_predictWithTFLite(double hr, double temp)`
AI-powered risk assessment:
- Feature preprocessing and normalization
- TFLite model inference
- Emotion-aware risk adjustment
- Alert engine integration

#### `_saveToFirestore(double hr, double temp)`
Cloud data persistence:
- Throttled saving (500ms intervals)
- Ride session metadata integration
- Location data inclusion
- Error handling with user feedback

#### `_triggerSOSEmergency()`
Automatic emergency response activation:
- Risk threshold validation (>70% for 30+ seconds)
- Emergency contact notification via SMS/email
- Real-time location sharing with emergency services
- Critical medical data transmission
- Emergency service integration and dispatch

#### `_manualSOSTrigger()`
Manual emergency activation:
- User-initiated SOS via UI button or physical trigger
- Immediate emergency notification bypassing thresholds
- Location and medical data transmission
- Emergency contact cascade notification
- Real-time status tracking

#### `_monitorSOSStatus()`
SOS state management and tracking:
- Continuous monitoring of emergency response
- Status updates to emergency contacts
- Post-incident documentation generation
- Resolution confirmation and system reset

### Provider Integration

#### SensorDataProvider
```dart
sensorProvider.updateHeartRate(hr.toInt());
sensorProvider.updateTemperature(temp);
sensorProvider.updateDangerAlert(hr > 110 || temp > 38.0);
```

#### EmotionProvider
```dart
final currentEmotion = emotionProvider.stressState.emotion;
final emotionMultiplier = _getEmotionRiskMultiplier(currentEmotion);
```

#### AlertEngine
```dart
alertEngine.onNewRiskReading(
  riskPercent: riskPercentage,
  hr: hr,
  temp: temp,
  profile: profile,
  btManager: btManager,
);
```

#### SOSProvider
```dart
sosProvider.updateRiskLevel(riskPercentage);
sosProvider.monitorSOSTrigger(
  heartRate: hr,
  temperature: temp,
  location: _currentPosition,
  userId: userId,
);
sosProvider.manualSOSTrigger();
```

## Data Flow

### Real-time Monitoring Flow
1. **Bluetooth Connection** → Auto-connect to SmartWatch_ESP32
2. **Data Reception** → JSON sensor data parsing
3. **Signal Processing** → Moving average filtering
4. **Risk Assessment** → TFLite model inference
5. **UI Update** → Real-time visualization
6. **Data Persistence** → Firestore storage
7. **Alert Processing** → Sustained risk monitoring
8. **SOS Monitoring** → Continuous emergency trigger assessment
9. **Emergency Response** → Automatic/manual SOS activation if needed

### Report Generation Flow
1. **Data Aggregation** → Fetch historical data
2. **Statistical Analysis** → Calculate daily summaries
3. **Emotional Analytics** → Process emotion trends
4. **Report Generation** → Create PDF document
5. **Export Options** → Print or share functionality

### SOS Emergency System Flow
1. **Risk Threshold Monitoring** → Continuous assessment of heart attack risk
2. **Sustained Risk Detection** → 30+ seconds above 70% risk threshold
3. **Automatic SOS Trigger** → Emergency activation without user intervention
4. **Manual SOS Override** → User-initiated emergency via UI/physical button
5. **Emergency Contact Notification** → SMS/email to predefined contacts
6. **Location Services Integration** → Real-time GPS coordinate sharing
7. **Medical Data Transmission** → Critical vitals sent to emergency services
8. **Emergency Service Dispatch** → Direct integration with emergency responders
9. **Response Status Tracking** → Real-time monitoring of emergency response
10. **Post-Incident Documentation** → Automatic report generation and follow-up

## Error Handling

### Connection Errors
- Automatic retry mechanism (3 attempts)
- User-friendly error messages
- Manual reconnection options
- Fallback device discovery

### Model Loading Errors
- Graceful fallback to local risk assessment
- User notification of model unavailability
- Continued basic functionality

### Data Validation
- Sensor data range validation
- Timestamp sanity checks
- Missing data handling
- Outlier detection and filtering

### SOS System Errors
- **Permission Denied**: Request emergency permissions (location, SMS, calls)
- **Network Unavailable**: Cache emergency data and retry when connected
- **Location Services Disabled**: Prompt user to enable GPS for accurate location
- **Emergency Contact Missing**: Validate emergency contacts during setup
- **SMS/Email Failure**: Fallback to emergency service direct call
- **False Positive Prevention**: Multi-factor validation before SOS trigger
- **Battery Critical**: Optimize SOS transmission for low power scenarios

## Performance Optimization

### Memory Management
- Rolling window data (30 points max)
- Efficient chart data structures
- Subscription cleanup on dispose
- Image and animation optimization

### Network Optimization
- Throttled Firestore writes
- Batch data processing
- Efficient query patterns
- Offline capability considerations

### UI Performance
- Lazy loading for charts
- Efficient widget rebuilding
- Smooth animations (60fps)
- Responsive design patterns

## Security Considerations

### Data Privacy
- User-specific data isolation
- Secure Firebase rules
- Local data encryption options
- GDPR compliance considerations

### Authentication
- Firebase Auth integration
- User session validation
- Secure data access patterns
- Role-based access controls

## Testing

### Unit Tests
- Risk assessment algorithms
- Data parsing logic
- Model inference accuracy
- Statistical calculations

### Integration Tests
- Bluetooth connectivity
- Firestore operations
- Provider state management
- Navigation flows

### Performance Tests
- Memory usage monitoring
- CPU usage optimization
- Battery impact assessment
- Network efficiency testing

### SOS System Tests
- **Automatic Trigger Validation**: Test 70% risk threshold for 30+ seconds
- **Manual Trigger Testing**: Verify UI and physical button SOS activation
- **Emergency Contact Notification**: Test SMS/email delivery to all contacts
- **Location Accuracy**: Validate GPS coordinate sharing during emergencies
- **Emergency Service Integration**: Test direct emergency responder connection
- **False Positive Prevention**: Verify multi-factor validation prevents accidental triggers
- **Battery Impact**: Test SOS functionality under low power conditions
- **Network Failure Handling**: Test offline emergency response protocols

## Troubleshooting

### Common Issues

#### Bluetooth Connection Failures
1. Verify device is powered and paired
2. Check Bluetooth permissions
3. Ensure device name matches `SmartWatch_ESP32`
4. Restart Bluetooth service

#### Model Loading Errors
1. Verify `assets/heart_attack_model.tflite` exists
2. Check model file integrity
3. Ensure TFLite Flutter plugin is properly configured
4. Clear app cache and restart

#### Data Sync Issues
1. Check Firebase connectivity
2. Verify user authentication
3. Check Firestore rules
4. Monitor network connectivity

#### Performance Issues
1. Reduce chart data points
2. Optimize animation complexity
3. Check memory usage
4. Monitor background processes

#### SOS System Issues
1. **Emergency Permissions Not Granted**: 
   - Go to Settings → Apps → Smart Helmet → Permissions
   - Enable Location, SMS, Phone, and Storage permissions
2. **SOS Not Triggering Automatically**:
   - Verify risk threshold is set to 70%
   - Check sustained duration is 30 seconds
   - Ensure TFLite model is loaded correctly
3. **Emergency Contacts Not Receiving Alerts**:
   - Validate contact phone numbers and emails
   - Check network connectivity
   - Verify SMS/email permissions
4. **Location Not Sharing During SOS**:
   - Enable GPS/location services
   - Check location permissions
   - Verify geolocator is functioning
5. **False SOS Triggers**:
   - Adjust risk threshold if too sensitive
   - Check sensor data accuracy
   - Verify moving average filter is working

## Future Enhancements

### Planned Features
- Multi-device support
- Advanced predictive analytics
- Telemedicine integration
- Wearable OS optimization
- Cloud ML model updates

### Scalability Considerations
- Distributed architecture
- Load balancing strategies
- Data archiving policies
- Performance monitoring

## Support and Maintenance

### Regular Maintenance Tasks
- Model accuracy validation
- Performance monitoring
- Security audits
- User feedback analysis

### Update Procedures
- Model versioning strategy
- Database schema updates
- API compatibility maintenance
- Rollback procedures

---

**Last Updated**: April 26, 2026  
**Version**: 1.0.0  
**Maintainer**: Smart Helmet Development Team
