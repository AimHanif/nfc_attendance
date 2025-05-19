import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart' as local_auth;
import '../main.dart';
import '../ui/background.dart';

class FirstTimeLoginScreen extends StatefulWidget {
  const FirstTimeLoginScreen({Key? key}) : super(key: key);

  @override
  State<FirstTimeLoginScreen> createState() => _FirstTimeLoginScreenState();
}

class _FirstTimeLoginScreenState extends State<FirstTimeLoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _matricCtrl = TextEditingController();
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
    _matricCtrl.dispose();
    super.dispose();
  }

  void _monitorConnectivity() {
    _logDebug('Starting connectivity monitoring');
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final primary = results.isNotEmpty ? results.first : ConnectivityResult.none;
      setState(() {
        _connectivityStatus = results.toString();
        _isConnected = primary != ConnectivityResult.none;
      });
      _logDebug('Connectivity changed: $_connectivityStatus');
    });
  }

  void _logDebug(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final log = '[$timestamp] DEBUG: $message';
    debugPrint(log);
    _debugLogs.add(log);
    if (_debugLogs.length > 1000) {
      _debugLogs.removeAt(0);
    }
  }

  String _generateTempPassword([int length = 16]) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _sendSetupLink() async {
    setState(() => _isLoading = true);

    try {
      await Provider.of<local_auth.AuthProvider>(context, listen: false)
          .sendResetLinkByMatricNo(_matricCtrl.text.trim());

      _showSnack(
        'A password setup link has been sent to your registered email.',
        Colors.green,
      );

      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
    } catch (e) {
      _showSnack('Error: $e', Colors.redAccent);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: bgColor,
      ),
    );
  }

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
        title: Text(
          'First-Time Login',
          style: textTheme.titleLarge?.copyWith(color: Colors.white),
        ),
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
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Enter your Matric No to receive a password reset link via your registered email.',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isConnected ? Icons.wifi : Icons.wifi_off,
                          color:
                          _isConnected ? Colors.greenAccent : Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Status: $_connectivityStatus',
                          style: textTheme.bodySmall
                              ?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _matricCtrl,
                            keyboardType: TextInputType.text,
                            style: textTheme.bodyMedium
                                ?.copyWith(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Matric No',
                              labelStyle: textTheme.bodyMedium
                                  ?.copyWith(color: Colors.white70),
                              prefixIcon:
                              const Icon(Icons.credit_card, color: Colors.white70),
                              filled: true,
                              fillColor: Colors.white24,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                const BorderSide(color: Colors.white54),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.white),
                              ),
                            ),
                            validator: (v) {
                              final matric = v?.trim() ?? '';
                              if (matric.isEmpty) {
                                return 'Matric No required';
                              }
                              if (!RegExp(r'^[A-Za-z]{2}\d{6}$')
                                  .hasMatch(matric)) {
                                return 'Example: DI230101';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: _isLoading
                            ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(Icons.email, color: Colors.white),
                        label: Text(
                          _isLoading ? 'Sending...' : 'Send Link',
                          style: textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                          _isConnected ? const Color(0xFF26A69A) : Colors.grey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _isLoading || !_isConnected
                            ? null
                            : _sendSetupLink,
                      ),
                    ),
                    const SizedBox(height: 32),
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
