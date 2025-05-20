import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String? staffNumber;
  final String? matricNumber;
  final String name;
  final String email;
  final String role;
  final bool mustChangePassword;
  final String? photoUrl;

  UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.matricNumber,
    required this.staffNumber,
    required this.mustChangePassword,
    this.photoUrl,
  });

  factory UserProfile.fromFirestore(String docId, Map<String, dynamic> data) {
    return UserProfile(
      uid: docId,
      staffNumber: data['staffNumber'] as String?,
      matricNumber: data['matricNumber'] as String?,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'student',
      mustChangePassword: data['mustChangePassword'] as bool? ?? false,
      photoUrl: data['photoUrl'] as String?,
    );
  }
}

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  UserProfile? _profile;
  bool _loading = true;

  UserProfile? get userProfile => _profile;
  bool get isLoading => _loading;

  AuthProvider() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? user) async {
    _loading = true;
    if (user == null) {
      _profile = null;
    } else {
      try {
        final snapshot = await _firestore
            .collection('users')
            .where('email', isEqualTo: user.email)
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          final profileData = doc.data();
          final profile = UserProfile.fromFirestore(doc.id, profileData);

          // If mustChangePassword is true, set to false automatically
          if (profile.mustChangePassword) {
            await _firestore.collection('users').doc(doc.id).update({
              'mustChangePassword': false,
            });

            // Create a new UserProfile with mustChangePassword: false
            _profile = UserProfile(
              uid: profile.uid,
              name: profile.name,
              email: profile.email,
              role: profile.role,
              matricNumber: profile.matricNumber,
              staffNumber: profile.staffNumber,
              mustChangePassword: false,
              photoUrl: profile.photoUrl,
            );
          } else {
            _profile = profile;
          }
        } else {
          _profile = null;
        }
      } catch (e) {
        _profile = null;
      }
    }

    _loading = false;
    notifyListeners();
  }

  /// AuthProvider: Unified login by matricNo or staffNumber
  Future<UserProfile> signInWithIdentifier(String identifier, String password) async {
    // Attempt lookup by matricNo
    var query = await _firestore
        .collection('users')
        .where('matricNo', isEqualTo: identifier)
        .limit(1)
        .get();

    // If not found, try staffNumber
    if (query.docs.isEmpty) {
      query = await _firestore
          .collection('users')
          .where('staffNumber', isEqualTo: identifier)
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'No account found for $identifier.',
        );
      }
    }

    // Extract email for Firebase Auth
    final data = query.docs.first.data();
    final email = data['email'] as String?;
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-user',
        message: 'User record for $identifier is missing an email.',
      );
    }

    // Sign in with email & password
    await _auth.signInWithEmailAndPassword(email: email, password: password);

    // Reload user profile
    final postQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    final doc = postQuery.docs.first;
    final profile = UserProfile.fromFirestore(doc.id, doc.data());

    _profile = profile;
    _loading = false;
    notifyListeners();
    return profile;
  }

  /// Send reset link by Matric No
  Future<void> sendResetLinkByIdentifier(String identifier) async {
    QuerySnapshot<Map<String, dynamic>> query;

    // First try matricNo
    query = await _firestore
        .collection('users')
        .where('matricNo', isEqualTo: identifier)
        .limit(1)
        .get();

    // If not found, try staffNumber
    if (query.docs.isEmpty) {
      query = await _firestore
          .collection('users')
          .where('staffNumber', isEqualTo: identifier)
          .limit(1)
          .get();
    }

    if (query.docs.isEmpty) {
      debugPrint('[DEBUG] No account found for $identifier');
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No account found for identifier $identifier.',
      );
    }

    final doc = query.docs.first;
    final data = doc.data();
    final email = data['email'] as String?;
    debugPrint('[DEBUG] Fetched email: $email');

    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-user',
        message: 'User record for $identifier is missing an email.',
      );
    }

    final methods = await _auth.fetchSignInMethodsForEmail(email);
    debugPrint('[DEBUG] Sign in methods for $email: $methods');

    if (methods.isEmpty) {
      final tempPwd = _generateTempPassword();
      try {
        await _auth.createUserWithEmailAndPassword(email: email, password: tempPwd);
        debugPrint('[DEBUG] Firebase user created.');
      } catch (e) {
        debugPrint('[DEBUG] Firebase user might already exist: $e');
      }
      await _auth.signOut();
      await _firestore.collection('users').doc(doc.id).update({
        'mustChangePassword': true,
      });
    } else {
      debugPrint('[DEBUG] User already exists, updating flag.');
      await _firestore.collection('users').doc(doc.id).update({
        'mustChangePassword': true,
      });
    }

    debugPrint('[DEBUG] Sending reset email to $email...');
    await _auth.sendPasswordResetEmail(email: email);
    await _auth.signOut();
  }

  /// Generates a cryptographically secure temporary password of [length].
  String _generateTempPassword([int length = 16]) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> signOut() => _auth.signOut();

  static Future<Map<String, dynamic>?> getCurrentLecturer() async {
    // TODO: Replace this stub with real logic to fetch the logged-in staff number.
    String? staffNumber = await _getLoggedInStaffNumber();
    if (staffNumber == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(staffNumber)
        .get();
    if (!doc.exists) return null;
    return doc.data();
  }

  static Future<String?> _getLoggedInStaffNumber() async {
    // Replace with real authentication/user state logic.
    return '1024';
  }
}
