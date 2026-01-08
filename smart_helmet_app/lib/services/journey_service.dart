import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/journey_model.dart';

class JourneyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'journeys';
  
  // Save journey data
  Future<void> saveJourney(JourneyData journey) async {
    try {
      await _firestore.collection(_collection).doc(journey.id).set(journey.toMap());
    } catch (e) {
      print('Error saving journey: $e');
      rethrow;
    }
  }
  
  // Update journey data
  Future<void> updateJourney(JourneyData journey) async {
    try {
      await _firestore.collection(_collection).doc(journey.id).update(journey.toMap());
    } catch (e) {
      print('Error updating journey: $e');
      rethrow;
    }
  }
  
  // Get all journeys
  Future<List<JourneyData>> getAllJourneys() async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection(_collection)
          .orderBy('startTime', descending: true)
          .get();
      
      return snapshot.docs
          .map((doc) => JourneyData.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      print('Error getting journeys: $e');
      return [];
    }
  }
  
  // Get journey by ID
  Future<JourneyData?> getJourney(String id) async {
    try {
      DocumentSnapshot doc = await _firestore.collection(_collection).doc(id).get();
      if (doc.exists) {
        return JourneyData.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }
      return null;
    } catch (e) {
      print('Error getting journey: $e');
      return null;
    }
  }
  
  // Delete journey
  Future<void> deleteJourney(String id) async {
    try {
      await _firestore.collection(_collection).doc(id).delete();
    } catch (e) {
      print('Error deleting journey: $e');
      rethrow;
    }
  }
}