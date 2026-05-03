// lib/providers/user_profile_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class EmergencyContact {
  final String name;
  final String phone;

  EmergencyContact({required this.name, required this.phone});

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone};

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    return EmergencyContact(
      name: (map['name'] as String?) ?? '',
      phone: (map['phone'] as String?) ?? '',
    );
  }
}

class UserProfileProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Profile fields
  String? _userName;
  int? _age;
  String? _gender; // "Male" / "Female" / "Other"
  double? _heightCm;
  double? _weightKg;
  List<EmergencyContact> _emergencyContacts = [];
  bool _isLoading = false;
  bool _profileLoaded = false;

  // ── Getters ──────────────────────────────────────────────────────────────
  String get userName => _userName ?? 'Rider';
  int? get age => _age;
  String? get gender => _gender;
  double? get heightCm => _heightCm;
  double? get weightKg => _weightKg;
  List<EmergencyContact> get emergencyContacts =>
      List.unmodifiable(_emergencyContacts);
  bool get isLoading => _isLoading;
  bool get profileLoaded => _profileLoaded;

  /// BMI calculated from height and weight (returns null if not available)
  double? get bmi {
    if (_heightCm == null || _weightKg == null || _heightCm! <= 0) return null;
    final heightM = _heightCm! / 100.0;
    return _weightKg! / (heightM * heightM);
  }

  /// Gender as numeric for TFLite model: 0 = Male, 1 = Female, 0.5 = Other
  double get genderNumeric {
    switch (_gender?.toLowerCase()) {
      case 'male':
        return 0.0;
      case 'female':
        return 1.0;
      default:
        return 0.5;
    }
  }

  /// Whether profile has at least 1 emergency contact
  bool get isProfileComplete =>
      _emergencyContacts.isNotEmpty && _profileLoaded;

  List<String> get emergencyPhoneNumbers =>
      _emergencyContacts.map((c) => c.phone).toList();

  // ── Load from Firestore ───────────────────────────────────────────────────
  Future<void> loadProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        _userName = data['userName'] as String?;
        _age = (data['age'] as num?)?.toInt();
        _gender = data['gender'] as String?;
        _heightCm = (data['heightCm'] as num?)?.toDouble();
        _weightKg = (data['weightKg'] as num?)?.toDouble();

        final rawContacts = data['emergencyContacts'];
        if (rawContacts is List) {
          _emergencyContacts = rawContacts
              .whereType<Map<String, dynamic>>()
              .map((m) => EmergencyContact.fromMap(m))
              .toList();
        }
        _profileLoaded = true;
        debugPrint(
            '✅ UserProfile loaded: $_userName | age=$_age | contacts=${_emergencyContacts.length}');
      }
    } catch (e) {
      debugPrint('❌ Error loading user profile: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Update emergency contacts ─────────────────────────────────────────────
  Future<String?> updateEmergencyContacts(
      List<EmergencyContact> contacts) async {
    if (contacts.isEmpty || contacts.length > 3) {
      return 'Please provide 1 to 3 emergency contacts';
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 'Not logged in';

    try {
      await _firestore.collection('users').doc(uid).update({
        'emergencyContacts': contacts.map((c) => c.toMap()).toList(),
      });
      _emergencyContacts = List.from(contacts);
      notifyListeners();
      return null; // success
    } catch (e) {
      debugPrint('❌ Error updating emergency contacts: $e');
      return 'Failed to save: $e';
    }
  }

  // ── Update profile fields ─────────────────────────────────────────────────
  Future<String?> updateProfileField(String field, dynamic value) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 'Not logged in';

    try {
      await _firestore.collection('users').doc(uid).update({field: value});

      // Refresh local state
      switch (field) {
        case 'age':
          _age = (value as num?)?.toInt();
          break;
        case 'gender':
          _gender = value as String?;
          break;
        case 'heightCm':
          _heightCm = (value as num?)?.toDouble();
          break;
        case 'weightKg':
          _weightKg = (value as num?)?.toDouble();
          break;
        case 'userName':
          _userName = value as String?;
          break;
      }
      notifyListeners();
      return null;
    } catch (e) {
      return 'Update failed: $e';
    }
  }

  /// Call on sign-out to clear cached data
  void clearProfile() {
    _userName = null;
    _age = null;
    _gender = null;
    _heightCm = null;
    _weightKg = null;
    _emergencyContacts = [];
    _profileLoaded = false;
    notifyListeners();
  }
}
