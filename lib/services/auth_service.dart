// lib/services/auth_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  /// Sign up with email & password and create user profile in Firestore.
  Future<UserCredential> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Update display name in Firebase Auth user profile
    await cred.user?.updateDisplayName(name);
    await cred.user?.reload();

    // Save minimal user profile to Firestore (overwrite if re-signup)
    await _firestore.collection('users').doc(cred.user!.uid).set({
      'name': name.trim(),
      'email': email.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    });

    // Optional: Send verification email
    await cred.user?.sendEmailVerification();

    return cred;
  }

  /// Sign in and ensure Firestore user profile exists.
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = cred.user;
    if (user != null) {
      // Ensure Firestore user profile exists
      final userDoc = _firestore.collection('users').doc(user.uid);
      final doc = await userDoc.get();
      if (!doc.exists) {
        await userDoc.set({
          'name': user.displayName ?? user.email ?? 'Unknown',
          'email': user.email ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Update last login timestamp
        await userDoc.update({'lastLoginAt': FieldValue.serverTimestamp()});
      }
    }

    return cred;
  }

  /// Sign out the current user
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Get the currently logged-in user (or null if not signed in)
  User? get currentUser => _auth.currentUser;
}
