import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/journey_model.dart';

class JourneyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'journeys';

  // Fetch the latest journey
  Future<JourneyData?> getLatestJourney() async {
    try {
      print('[JourneyService] Fetching latest journey from Firestore...');
      QuerySnapshot snapshot = await _firestore
          .collection(_collection)
          .orderBy('startTime', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (snapshot.docs.isNotEmpty) {
        return JourneyData.fromMap(
          snapshot.docs.first.data() as Map<String, dynamic>,
          snapshot.docs.first.id,
        );
      }
      return null;
    } catch (e) {
      print('[JourneyService] Error fetching latest journey: $e');
      return null;
    }
  }

  // Save journey data
  Future<void> saveJourney(JourneyData journey) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(journey.id)
          .set(journey.toMap());
    } catch (e) {
      print('Error saving journey: $e');
      rethrow;
    }
  }

  // Update journey data
  Future<void> updateJourney(JourneyData journey) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(journey.id)
          .update(journey.toMap());
    } catch (e) {
      print('Error updating journey: $e');
      rethrow;
    }
  }

  // Get all journeys - fetches from server to avoid stale cache
  Future<List<JourneyData>> getAllJourneys() async {
    try {
      print('[JourneyService] Fetching all journeys from Firestore server...');
      
      QuerySnapshot snapshot = await _firestore
          .collection(_collection)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      print('[JourneyService] Got ${snapshot.docs.length} documents from Firestore');

      final journeys = <JourneyData>[];
      for (var doc in snapshot.docs) {
        try {
          final journey = JourneyData.fromMap(
            doc.data() as Map<String, dynamic>,
            doc.id,
          );
          journeys.add(journey);
          print('[JourneyService] Parsed journey: ${journey.id} | turns: ${journey.turnEvents.length} | brakes: ${journey.brakingEvents.length}');
        } catch (parseError) {
          print('[JourneyService] Failed to parse doc ${doc.id}: $parseError');
        }
      }

      print('[JourneyService] Successfully parsed ${journeys.length} journeys');
      return journeys;
    } on TimeoutException {
      print('[JourneyService] TIMEOUT: Firestore took too long. Trying cache...');
      // Fallback to cache if server times out
      try {
        QuerySnapshot snapshot = await _firestore
            .collection(_collection)
            .get(const GetOptions(source: Source.cache));
        
        print('[JourneyService] Cache returned ${snapshot.docs.length} documents');
        return snapshot.docs
            .map((doc) => JourneyData.fromMap(
                doc.data() as Map<String, dynamic>, doc.id))
            .toList();
      } catch (cacheError) {
        print('[JourneyService] Cache also failed: $cacheError');
        return [];
      }
    } catch (e, stacktrace) {
      print('[JourneyService] ERROR getting journeys: $e');
      print(stacktrace);
      return [];
    }
  }

  // Get journey by ID
  Future<JourneyData?> getJourney(String id) async {
    try {
      DocumentSnapshot doc =
          await _firestore.collection(_collection).doc(id).get();
      if (doc.exists) {
        return JourneyData.fromMap(
            doc.data() as Map<String, dynamic>, doc.id);
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
