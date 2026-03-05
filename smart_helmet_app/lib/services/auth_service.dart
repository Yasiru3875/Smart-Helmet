import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
  );

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  // ── Email/Password Sign In ───────────────────────────────────────────────
  Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Sign in failed';
    } catch (e) {
      debugPrint('Sign-in error: $e');
      return 'Sign in failed';
    }
  }

  // ── Email/Password Registration + Save profile to Firestore ──────────────
  Future<String?> register({
    required String username,
    required String email,
    required String password,
    required int age,
    required String gender,
    required double heightCm,
    required double weightKg,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;
      if (user == null) return 'Registration failed – no user returned';

      await _firestore.collection('users').doc(user.uid).set({
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'age': age,
        'gender': gender,
        'heightCm': heightCm,
        'weightKg': weightKg,
      });

      return null; // ← success = null error
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Authentication failed';
    } on FirebaseException catch (e) {
      return e.message ?? 'Database error';
    } catch (e) {
      return 'Unexpected error: $e';
    }
  }

  // ── Google Sign-In ───────────────────────────────────────────────────────
  Future<String?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return 'Google sign in cancelled';
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);

      // Optional: If this is a new user, you could create a Firestore doc here too
      // But most apps handle it via an auth state listener + onCreate trigger

      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Google sign in failed';
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      return 'Google sign in failed';
    }
  }

  // ── Sign Out ─────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
  }
}
