// lib/auth_provider.dart

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a user profile in Firestore `users/{docId}`
class UserProfile {
  final String uid;               // Firestore doc ID
  final String name;
  final String email;
  final String role;
  final bool mustChangePassword;

  UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.mustChangePassword,
  });

  factory UserProfile.fromFirestore(String docId, Map<String, dynamic> data) {
    return UserProfile(
      uid                : docId,
      name               : data['name']               as String? ?? '',
      email              : data['email']              as String? ?? '',
      role               : data['role']               as String? ?? 'student',
      mustChangePassword : data['mustChangePassword'] as bool?   ?? false,
    );
  }
}

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth      _auth      = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  UserProfile? _profile;
  bool         _loading = true;

  UserProfile? get userProfile => _profile;
  bool         get isLoading   => _loading;

  AuthProvider() {
    // Keep _profile in sync, but don't force a sign-out on missing Firestore doc.
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? user) async {
    _loading = true;
    if (user == null) {
      // user signed out externally
      _profile = null;

    } else {
      // hydrate profile by matching email
      try {
        final snapshot = await _firestore
            .collection('users')
            .where('email', isEqualTo: user.email)
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          final doc      = snapshot.docs.first;
          _profile = UserProfile.fromFirestore(doc.id, doc.data());
        } else {
          // No Firestore record: just clear local profile, but don't auto sign-out
          debugPrint(
              '[AuthProvider] ⚠️ No user document for ${user.email}; _profile set to null.'
          );
          _profile = null;
        }
      } catch (e) {
        // On any Firestore error, leave profile null but keep the auth session
        debugPrint('[AuthProvider] ❌ Firestore lookup failed: $e');
        _profile = null;
      }
    }

    _loading = false;
    notifyListeners();
  }

  /// Sign in by IC + password.
  /// Immediately returns a concrete UserProfile on success.
  Future<UserProfile> signInWithIC(String ic, String password) async {
    // 1) Lookup Firestore record by IC
    final query = await _firestore
        .collection('users')
        .where('ic', isEqualTo: ic)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw FirebaseAuthException(
        code   : 'user-not-found',
        message: 'No account found for IC $ic.',
      );
    }

    final data  = query.docs.first.data();
    final email = data['email'] as String?;
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code   : 'invalid-user',
        message: 'User record for IC $ic is missing an email.',
      );
    }

    // 2) Delegate to FirebaseAuth
    await _auth.signInWithEmailAndPassword(email: email, password: password);

    // 3) Hydrate profile immediately to avoid race
    final postQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    final doc      = postQuery.docs.first;
    final profile  = UserProfile.fromFirestore(doc.id, doc.data());

    _profile = profile;
    _loading = false;
    notifyListeners();
    return profile;
  }

  /// Send reset link by IC (unchanged)
  Future<void> sendResetLinkByIC(String ic) async {
    final query = await _firestore
        .collection('users')
        .where('ic', isEqualTo: ic)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return;

    final doc   = query.docs.first;
    final data  = doc.data();
    final email = data['email'] as String?;
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code   : 'invalid-user',
        message: 'User record for IC $ic has no email.',
      );
    }

    final methods = await _auth.fetchSignInMethodsForEmail(email);
    if (methods.isEmpty) {
      const chars   = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final rnd     = Random.secure();
      final tempPwd = List.generate(16, (_) => chars[rnd.nextInt(chars.length)]).join();

      await _auth.createUserWithEmailAndPassword(email: email, password: tempPwd);
      await _auth.signOut();
      await _firestore.collection('users').doc(doc.id).update({
        'mustChangePassword': true,
      });
    }

    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() => _auth.signOut();
}
