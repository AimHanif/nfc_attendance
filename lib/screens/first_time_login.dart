// lib/screens/first_time_login.dart

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../ui/background.dart';

/// FirstTimeLoginScreen allows a user to request a one-time setup link via email.
/// It supports debug logging, connectivity checks, terms & privacy, and retry logic.
class FirstTimeLoginScreen extends StatefulWidget {
  const FirstTimeLoginScreen({Key? key}) : super(key: key);

  @override
  State<FirstTimeLoginScreen> createState() => _FirstTimeLoginScreenState();
}

class _FirstTimeLoginScreenState extends State<FirstTimeLoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _icCtrl = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = false;
  bool _isConnected = true;
  String _connectivityStatus = 'Unknown';
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  List<String> _debugLogs = [];

  @override
  void initState() {
    super.initState();
    _logDebug('initState called');
    _monitorConnectivity();
  }

  @override
  void dispose() {
    _logDebug('dispose called');
    _connectivitySub?.cancel();
    _icCtrl.dispose();
    super.dispose();
  }

  /// Monitors network connectivity and updates UI.
  void _monitorConnectivity() {
    _logDebug('Starting connectivity monitoring');
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      // pick the first available network type, if any
      final primary = results.isNotEmpty ? results.first : ConnectivityResult.none;
      setState(() {
        _connectivityStatus = results.toString();
        _isConnected = primary != ConnectivityResult.none;
      });
      _logDebug('Connectivity changed: $_connectivityStatus');
    });
  }

  /// Adds a message to debug log and prints to console.
  void _logDebug(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final log = '[$timestamp] DEBUG: $message';
    debugPrint(log);
    _debugLogs.add(log);
    if (_debugLogs.length > 1000) {
      _debugLogs.removeAt(0);
    }
  }

  /// Generates a random temporary password.
  String _generateTempPassword([int length = 16]) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _sendSetupLink() async {
    _logDebug('sendSetupLink called');
    if (!_isConnected) {
      _showSnack('Tiada sambungan internet.', Colors.orange);
      return;
    }
    if (!_formKey.currentState!.validate()) {
      _logDebug('Form validation failed');
      return;
    }
    setState(() => _isLoading = true);

    final ic = _icCtrl.text.trim();
    _logDebug('Looking up IC: $ic');

    try {
      final query = await _firestore
          .collection('users')
          .where('ic', isEqualTo: ic)
          .limit(1)
          .get();
      _logDebug('Firestore query returned ${query.docs.length} docs');

      if (query.docs.isEmpty) {
        _showSnack('Tiada akaun ditemui untuk IC tersebut.', Colors.redAccent);
        _logDebug('No user found for IC $ic');
      } else {
        final doc = query.docs.first;
        final data = doc.data();
        final email = data['email'] as String?;
        if (email == null || email.isEmpty) {
          _showSnack('Rekod pengguna tidak mempunyai email.', Colors.redAccent);
          _logDebug('Email field missing in Firestore for IC $ic');
        } else {
          // Ensure Auth user exists
          _logDebug('Checking sign-in methods for $email');
          final methods = await _auth.fetchSignInMethodsForEmail(email);
          _logDebug('Sign-in methods: $methods');

          if (methods.isEmpty) {
            final tempPwd = _generateTempPassword();
            _logDebug('Creating Auth user for $email with temp password.');
            final userCred = await _auth.createUserWithEmailAndPassword(
              email: email,
              password: tempPwd,
            );
            _logDebug('Auth user created: ${userCred.user?.uid}');
            // mark mustChangePassword
            await _firestore.collection('users').doc(doc.id).update({
              'mustChangePassword': true,
            });
            _logDebug('mustChangePassword flag set in Firestore');
          }

          _logDebug('Sending standard password reset email to $email');
          await _auth.sendPasswordResetEmail(email: email);  // ← no ActionCodeSettings
          _showSnack('Link reset dihantar ke $email', Colors.green);
          _logDebug('Password reset email sent');
        }
      }
    } catch (e, st) {
      _showSnack('Ralat: $e', Colors.redAccent);
      _logDebug('Error in sendSetupLink: $e\n$st');
    } finally {
      setState(() => _isLoading = false);
      _logDebug('sendSetupLink completed');
    }
  }

  /// Displays a SnackBar with given message and color.
  void _showSnack(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: bgColor,
      ),
    );
  }

  /// Builds the debug console widget.
  Widget _buildDebugConsole() {
    return ExpansionTile(
      title: const Text('Debug Console', style: TextStyle(color: Colors.white70)),
      children: [
        Container(
          height: 200,
          color: Colors.black87,
          child: ListView.builder(
            itemCount: _debugLogs.length,
            itemBuilder: (ctx, i) {
              return Text(
                _debugLogs[i],
                style: const TextStyle(color: Colors.greenAccent, fontSize: 10),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Log Masuk Pertama Kali', style: textTheme.titleLarge?.copyWith(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          const AnimatedWebBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Masukkan No. IC untuk menerima pautan reset kata laluan melalui emel terdaftar.',
                      style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 24),

                    // Connectivity status indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isConnected ? Icons.wifi : Icons.wifi_off,
                          color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Sambungan: $_connectivityStatus',
                          style: textTheme.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // IC input form
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _icCtrl,
                            keyboardType: TextInputType.number,
                            style: textTheme.bodyMedium?.copyWith(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'No. IC',
                              labelStyle: textTheme.bodyMedium?.copyWith(color: Colors.white70),
                              prefixIcon: const Icon(Icons.badge, color: Colors.white70),
                              filled: true,
                              fillColor: Colors.white24,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.white54),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.white),
                              ),
                            ),
                            validator: (v) {
                              final ic = v?.trim() ?? '';
                              if (ic.isEmpty) {
                                return 'IC diperlukan';
                              }
                              if (!RegExp(r'^\d{12}$').hasMatch(ic)) {
                                return 'Sila masukkan 12 digit IC yang sah';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 24),

                          // Terms & Privacy links
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () {
                                  _logDebug('Terms & Conditions tapped');
                                  // TODO: launch URL
                                },
                                child: const Text('Terma', style: TextStyle(decoration: TextDecoration.underline, color: Colors.white70)),
                              ),
                              const SizedBox(width: 16),
                              TextButton(
                                onPressed: () {
                                  _logDebug('Privacy Policy tapped');
                                  // TODO: launch URL
                                },
                                child: const Text('Privasi', style: TextStyle(decoration: TextDecoration.underline, color: Colors.white70)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: _isLoading
                            ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                            : const Icon(Icons.email, color: Colors.white),
                        label: Text(
                          _isLoading ? 'Menghantar...' : 'Hantar Pautan',
                          style: textTheme.titleMedium?.copyWith(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isConnected ? const Color(0xFF26A69A) : Colors.grey,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isLoading || !_isConnected ? null : _sendSetupLink,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Debug console
                    _buildDebugConsole(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
