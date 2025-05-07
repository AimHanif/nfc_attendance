// lib/screens/forgot_password.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../ui/background.dart';

/// A fully featured "Forgot Password" screen:
/// - Animated background
/// - Connectivity monitoring (List<ConnectivityResult>)
/// - IC → email lookup in Firestore
/// - Countdown timer for resend
/// - Debug console
/// - Smooth animations
/// - Error handling and snackbars
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with TickerProviderStateMixin {
  // Form controllers & state
  final TextEditingController _icCtrl = TextEditingController();
  String? _email;
  bool _isLoading = false;

  // Connectivity
  bool _isConnected = true;
  String _connectivityStatus = 'Unknown';
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Debug logs
  final List<String> _debugLogs = [];

  // Resend timer
  Timer? _resendTimer;
  int _secondsRemaining = 0;

  // Animations
  late final AnimationController _mainController;
  late final Animation<double> _titleScale;
  late final Animation<double> _formFade;
  late final Animation<double> _buttonScale;

  @override
  void initState() {
    super.initState();
    _logDebug('initState called');
    _monitorConnectivity();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
    _titleScale = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.3, curve: Curves.elasticOut),
    );
    _formFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.3, 0.6, curve: Curves.easeIn),
    );
    _buttonScale = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _logDebug('dispose called');
    _connectivitySub?.cancel();
    _resendTimer?.cancel();
    _icCtrl.dispose();
    _mainController.dispose();
    super.dispose();
  }

  /// Monitor network connectivity (emits List<ConnectivityResult>)
  void _monitorConnectivity() {
    _logDebug('Starting connectivity monitoring');
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final primary = results.isNotEmpty
          ? results.first
          : ConnectivityResult.none;
      setState(() {
        _isConnected = primary != ConnectivityResult.none;
        _connectivityStatus = primary.toString().split('.').last;
      });
      _logDebug('Connectivity changed: $_connectivityStatus');
    });
  }

  /// Add a debug entry
  void _logDebug(String message) {
    final ts = DateTime.now().toIso8601String();
    final entry = '[$ts] DEBUG: $message';
    debugPrint(entry);
    _debugLogs.add(entry);
    if (_debugLogs.length > 500) _debugLogs.removeAt(0);
  }

  /// Lookup email in Firestore by IC
  Future<String?> _lookupEmail(String ic) async {
    _logDebug('Looking up email for IC: $ic');
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('ic', isEqualTo: ic)
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        _logDebug('No user doc for IC $ic');
        return null;
      }
      final email = query.docs.first.data()['email'] as String?;
      _logDebug('Found email: $email');
      return email;
    } catch (e) {
      _logDebug('Error looking up email: $e');
      return null;
    }
  }

  /// Send password reset link
  Future<void> _sendResetLink() async {
    final ic = _icCtrl.text.trim();
    if (!_isConnected) {
      _showSnack('No internet connection', Colors.orangeAccent);
      return;
    }
    if (!RegExp(r'^\d{12}$').hasMatch(ic)) {
      _showSnack('Please enter a valid 12-digit IC number', Colors.redAccent);
      return;
    }

    setState(() => _isLoading = true);

    final email = await _lookupEmail(ic);
    if (email == null) {
      _showSnack('No account found for IC $ic', Colors.redAccent);
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _email = email);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSnack('Reset link sent to $email', Colors.greenAccent);
      _startResendCountdown();
    } on FirebaseAuthException catch (e) {
      _logDebug('FirebaseAuthException: ${e.code} ${e.message}');
      _showSnack(e.message ?? 'Failed to send reset link', Colors.redAccent);
    } catch (e) {
      _logDebug('Unexpected error sending reset: $e');
      _showSnack('Unexpected error: $e', Colors.redAccent);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Countdown before allowing resend
  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _secondsRemaining = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 0) {
        timer.cancel();
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  /// Display a SnackBar
  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Forgot Password'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const AnimatedWebBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ScaleTransition(
                    scale: _titleScale,
                    child: Text(
                      'Forgot Your Password?',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FadeTransition(
                    opacity: _formFade,
                    child: Text(
                      'Enter your 12-digit IC and we’ll send a reset link to your registered email.',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 32),
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
                        _connectivityStatus,
                        style:
                        textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _formFade,
                    child: TextField(
                      controller: _icCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'IC Number',
                        labelStyle: const TextStyle(color: Colors.white70),
                        prefixIcon:
                        const Icon(Icons.badge, color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white12,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ScaleTransition(
                    scale: _buttonScale,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading || _secondsRemaining > 0
                          ? null
                          : _sendResetLink,
                      icon: _isLoading
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                          AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                          : const Icon(Icons.email),
                      label: Text(
                        _secondsRemaining > 0
                            ? 'Resend in $_secondsRemaining s'
                            : 'Send Reset Link',
                        style: textTheme.titleMedium
                            ?.copyWith(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        _isLoading ? Colors.grey : Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_email != null) ...[
                    Text(
                      'Link will be sent to:',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _email!,
                      style:
                      textTheme.bodyMedium?.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                  ],
                  ExpansionTile(
                    title: const Text('Debug Console',
                        style: TextStyle(color: Colors.white70)),
                    children: [
                      Container(
                        height: 200,
                        color: Colors.black87,
                        child: ListView.builder(
                          itemCount: _debugLogs.length,
                          itemBuilder: (ctx, i) => Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8.0, vertical: 2.0),
                            child: Text(
                              _debugLogs[i],
                              style: const TextStyle(
                                  color: Colors.greenAccent, fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '© YourAppName ${DateTime.now().year}',
                    style: const TextStyle(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
