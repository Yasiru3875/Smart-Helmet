// ============================================================
// risky_events_service.dart - Manage risky events in Firebase
// Saves ONLY risky movements, not all sensor readings
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/journey_model.dart';

class RiskyEventsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  String? get _currentUserId => _auth.currentUser?.uid;
  
  // ============================================================
  // LOAD RISKY EVENTS FOR A RIDE
  // ============================================================
  
  /// Load all risky events for a specific ride ID
  Future<List<Map<String, dynamic>>> getRiskyEventsForRide(String rideId) async {
    try {
      final snapshot = await _firestore
          .collection("risky_events")
          .where("rideId", isEqualTo: rideId)
          .orderBy("timestamp")
          .get();
      
      return snapshot.docs.map((doc) => {
        ...doc.data(),
        "docId": doc.id,
      }).toList();
    } catch (e) {
      print("Error loading risky events: $e");
      return [];
    }
  }
  
  /// Load risky events for current user (all rides)
  Future<List<Map<String, dynamic>>> getAllUserRiskyEvents() async {
    final userId = _currentUserId;
    if (userId == null) return [];
    
    try {
      final snapshot = await _firestore
          .collection("risky_events")
          .where("userId", isEqualTo: userId)
          .orderBy("createdAt", descending: true)
          .limit(100)
          .get();
      
      return snapshot.docs.map((doc) => {
        ...doc.data(),
        "docId": doc.id,
      }).toList();
    } catch (e) {
      print("Error loading user risky events: $e");
      return [];
    }
  }
  
  /// Get recent risky events (last 24 hours)
  Future<List<Map<String, dynamic>>> getRecentRiskyEvents() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      
      final snapshot = await _firestore
          .collection("risky_events")
          .where("createdAt", isGreaterThan: Timestamp.fromDate(cutoff))
          .orderBy("createdAt", descending: true)
          .get();
      
      return snapshot.docs.map((doc) => {
        ...doc.data(),
        "docId": doc.id,
      }).toList();
    } catch (e) {
      print("Error loading recent risky events: $e");
      return [];
    }
  }
  
  // ============================================================
  // CONVERT RISKY EVENTS TO JOURNEY MODEL FORMAT
  // ============================================================
  
  /// Convert Firebase risky events to TurnEvent list for visualization
  List<TurnEvent> convertToTurnEvents(List<Map<String, dynamic>> riskyEvents) {
    return riskyEvents
        .where((e) => e['eventType'] == 'risky_turn' || e['eventType'] == 'sharp_turn')
        .map((e) => TurnEvent(
          timestamp: DateTime.parse(e['timestamp']),
          severity: e['eventType'] == 'risky_turn' ? 'risky' : 'sharp',
          turnRate: (e['turnRateDegPerSec'] ?? 0.0).toDouble(),
          latitude: (e['latitude'] ?? 0.0).toDouble(),
          longitude: (e['longitude'] ?? 0.0).toDouble(),
        ))
        .toList();
  }
  
  /// Convert Firebase risky events to BrakingEvent list for visualization
  List<BrakingEvent> convertToBrakeEvents(List<Map<String, dynamic>> riskyEvents) {
    return riskyEvents
        .where((e) => e['eventType'] == 'harsh_brake' || e['eventType'] == 'sudden_brake')
        .map((e) => BrakingEvent(
          timestamp: DateTime.parse(e['timestamp']),
          severity: e['eventType'] == 'harsh_brake' ? 'harsh' : 'moderate',
          deceleration: (e['accelX']?.abs() ?? 0.0).toDouble(),
          latitude: (e['latitude'] ?? 0.0).toDouble(),
          longitude: (e['longitude'] ?? 0.0).toDouble(),
          speedBefore: (e['speedKmh'] ?? 0.0).toDouble(),
        ))
        .toList();
  }
  
  /// Create a JourneyData object from risky events for report visualization
  JourneyData createJourneyFromRiskyEvents({
    required String rideId,
    required List<Map<String, dynamic>> riskyEvents,
    required DateTime startTime,
    DateTime? endTime,
    String? startLocation,
    String? destination,
    double totalDistance = 0.0,
    double averageSpeed = 0.0,
    double maxSpeed = 0.0,
  }) {
    final turnEvents = convertToTurnEvents(riskyEvents);
    final brakeEvents = convertToBrakeEvents(riskyEvents);
    
    // Build GPS track from risky event locations
    final gpsTrack = riskyEvents
        .where((e) => e['latitude'] != null && e['longitude'] != null)
        .map((e) => GpsPoint(
          latitude: (e['latitude']).toDouble(),
          longitude: (e['longitude']).toDouble(),
          timestamp: DateTime.parse(e['timestamp']),
          speedKmh: (e['speedKmh'] ?? 0.0).toDouble(),
        ))
        .toList();
    
    final sharpTurns = turnEvents.where((e) => e.severity == 'sharp').length;
    final riskyTurns = turnEvents.where((e) => e.severity == 'risky').length;
    final suddenBrakes = brakeEvents.length;
    
    // Calculate risk score based on events
    final riskScore = _calculateRiskScore(sharpTurns, riskyTurns, suddenBrakes);
    
    return JourneyData(
      id: rideId,
      startTime: startTime,
      endTime: endTime ?? DateTime.now(),
      startLocation: startLocation,
      destination: destination,
      sharpTurns: sharpTurns,
      riskyTurns: riskyTurns,
      suddenBrakes: suddenBrakes,
      averageSpeed: averageSpeed,
      maxSpeed: maxSpeed,
      totalDistance: totalDistance,
      riskScore: riskScore,
      turnEvents: turnEvents,
      brakeEvents: brakeEvents,
      gpsTrack: gpsTrack,
      recommendations: _generateRecommendations(sharpTurns, riskyTurns, suddenBrakes),
    );
  }
  
  double _calculateRiskScore(int sharpTurns, int riskyTurns, int suddenBrakes) {
    // Start at 100 (perfect score) and deduct for each risky event
    double score = 100.0;
    score -= riskyTurns * 8;  // -8 per risky turn
    score -= sharpTurns * 4;  // -4 per sharp turn
    score -= suddenBrakes * 5; // -5 per sudden brake
    return score.clamp(0.0, 100.0);
  }
  
  List<String> _generateRecommendations(int sharpTurns, int riskyTurns, int suddenBrakes) {
    final recommendations = <String>[];
    
    if (riskyTurns > 3) {
      recommendations.add("⚠️ Multiple risky turns detected. Consider reducing speed before curves.");
    }
    if (sharpTurns > 5) {
      recommendations.add("🔄 Frequent sharp turns. Plan your route to avoid tight corners when possible.");
    }
    if (suddenBrakes > 2) {
      recommendations.add("🛑 Several sudden brakes recorded. Maintain safe following distance.");
    }
    if (riskyTurns == 0 && sharpTurns < 3 && suddenBrakes < 2) {
      recommendations.add("✅ Great job! Your riding was smooth and safe this trip.");
    }
    
    return recommendations;
  }
  
  // ============================================================
  // DELETE RISKY EVENTS
  // ============================================================
  
  /// Delete all risky events for a specific ride
  Future<void> deleteRiskyEventsForRide(String rideId) async {
    try {
      final batch = _firestore.batch();
      final snapshot = await _firestore
          .collection("risky_events")
          .where("rideId", isEqualTo: rideId)
          .get();
      
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      print("Deleted ${snapshot.docs.length} risky events for ride: $rideId");
    } catch (e) {
      print("Error deleting risky events: $e");
      rethrow;
    }
  }
  
  // ============================================================
  // STATISTICS
  // ============================================================
  
  /// Get risky events count for a ride
  Future<int> getRiskyEventsCount(String rideId) async {
    try {
      final snapshot = await _firestore
          .collection("risky_events")
          .where("rideId", isEqualTo: rideId)
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      print("Error getting count: $e");
      return 0;
    }
  }
}
