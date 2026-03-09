// lib/providers/ride_session_provider.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class RideSessionProvider with ChangeNotifier {
  String? _currentRideId;
  GeoPoint? _startLocation;
  GeoPoint? _endLocation;
  String? _destinationName;

  DateTime? _startTime;
  DateTime? _endTime;
  double _totalDistanceKm = 0.0;
  bool _isRideActive = false;
  String? get currentRideId => _currentRideId;
  GeoPoint? get startLocation => _startLocation;
  GeoPoint? get endLocation => _endLocation;
  String? get destinationName => _destinationName;
  DateTime? get startTime => _startTime;
  DateTime? get endTime => _endTime;
  double get totalDistanceKm => _totalDistanceKm;
  bool get isRideActive => _isRideActive;

  Future<void> startNewRide({
    required Position currentPosition,
    required String destination,
    required String userId, // Added userId parameter
  }) async {
    final firestore = FirebaseFirestore.instance;
    final rideRef = firestore.collection('rides').doc();

    _currentRideId = rideRef.id;
    _startLocation =
        GeoPoint(currentPosition.latitude, currentPosition.longitude);
    _destinationName = destination;

    _startTime = DateTime.now();
    _isRideActive = true;
    _totalDistanceKm = 0.0;

    await rideRef.set({
      'rideId': _currentRideId,
      'userId': userId, // Use dynamic userId
      'startLocation': _startLocation,
      'startTime': FieldValue.serverTimestamp(),
      'destination': destination,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });

    notifyListeners();
  }

  Future<void> endCurrentRide({
    required Position? finalPosition,
    required double totalDistance,
  }) async {
    if (_currentRideId == null || !_isRideActive) return;

    final firestore = FirebaseFirestore.instance;
    final rideRef = firestore.collection('rides').doc(_currentRideId);

    _endLocation = finalPosition != null
        ? GeoPoint(finalPosition.latitude, finalPosition.longitude)
        : null;
    _endTime = DateTime.now();
    _totalDistanceKm = totalDistance;
    _isRideActive = false;

    await rideRef.update({
      'endLocation': _endLocation,
      'endTime': FieldValue.serverTimestamp(),
      'totalDistanceKm': totalDistance,
      'status': 'completed',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    notifyListeners();
  }

  void clearRide() {
    _currentRideId = null;
    _startLocation = null;
    _endLocation = null;
    _destinationName = null;
    _startTime = null;
    _endTime = null;
    _totalDistanceKm = 0.0;
    _isRideActive = false;
    notifyListeners();
  }
}
