import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:connectivity_plus/connectivity_plus.dart';

import '../auth_provider.dart';
import '../ui/background.dart';
import '../main.dart'; // AppRoutes
import 'forgot_password.dart';
import 'first_time_login.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _matricCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isPressed = false;
  bool _isConnected = true;
  String _connectivityStatus = 'Unknown';

  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;
  final List<String> _debugLogs = [];

  late final AnimationController _logoController;
  late final Animation<double> _logoAnimation;
  late final AnimationController _fieldsController;
  late final Animation<double> _fieldsSlide;
  late final Animation<double> _fieldsFade;

  @override
  void initState() {
    super.initState();
    _monitorConnectivity();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _logoAnimation = CurvedAnimation(parent: _logoController, curve: Curves.elasticOut);

    _fieldsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _fieldsSlide = Tween<double>(begin: 50, end: 0).animate(
      CurvedAnimation(parent: _fieldsController, curve: Curves.easeOut),
    );
    _fieldsFade = CurvedAnimation(parent: _fieldsController, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _logoController.dispose();
    _fieldsController.dispose();
    _connectivitySub.cancel();
    _matricCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _monitorConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final primary = results.isNotEmpty ? results.first : ConnectivityResult.none;
      setState(() {
        _isConnected = primary != ConnectivityResult.none;
        _connectivityStatus = primary.toString().split('.').last;
        _logDebug('Connectivity: $_connectivityStatus');
      });
    });
  }

  void _logDebug(String msg) {
    final ts = DateTime.now().toIso8601String();
    final entry = '[$ts] DEBUG: $msg';
    debugPrint(entry);
    _debugLogs.insert(0, entry);
    if (_debugLogs.length > 1000) _debugLogs.removeLast();
  }

  void _togglePassword() => setState(() => _obscurePassword = !_obscurePassword);

  Future<void> _login() async {
    if (!_isConnected) {
      _showError('No internet connection');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _isPressed = false;
    });
    _logDebug('Login attempt MatricNo=${_matricCtrl.text.trim()}');

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);

      final profile = await auth.signInWithIdentifier(_matricCtrl.text.trim(), _passCtrl.text);

      _logDebug('Authenticated & profile loaded for ${profile.email}');

      if (profile.role == 'student') {
        Navigator.pushReplacementNamed(context, AppRoutes.studentDashboard);
      } else if (profile.role == 'lecturer') {
        Navigator.pushReplacementNamed(context, AppRoutes.lecturerDashboard);
      } else {
        _showError('Unknown role – please contact support.');
      }
    } on FirebaseAuthException catch (e) {
      final msg = {
        'user-not-found': 'No account for that Matric No.',
        'wrong-password': 'Incorrect password.',
      }[e.code] ?? e.message ?? 'Login failed.';
      _showError(msg);
      _logDebug('Auth error: ${e.code}');
    } catch (e) {
      _showError('Unexpected error: $e');
      _logDebug('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AnimatedWebBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _logoAnimation,
                      child: Icon(Icons.nfc, size: 100, color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    Text('NFC Attendance', style: textTheme.headlineMedium?.copyWith(color: Colors.white)),
                    const SizedBox(height: 32),

                    // Connectivity
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isConnected ? Icons.wifi : Icons.wifi_off,
                          color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Text(_connectivityStatus, style: textTheme.bodySmall?.copyWith(color: Colors.white70)),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Form fields...
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Matric No
                          AnimatedBuilder(
                            animation: _fieldsController,
                            builder: (_, child) => Opacity(
                              opacity: _fieldsFade.value,
                              child: Transform.translate(
                                offset: Offset(0, _fieldsSlide.value),
                                child: child,
                              ),
                            ),
                            child: TextFormField(
                              controller: _matricCtrl,
                              keyboardType: TextInputType.text,
                              style: textTheme.bodyLarge?.copyWith(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Matric No/Staff No',
                                labelStyle: const TextStyle(color: Colors.white70),
                                prefixIcon: const Icon(Icons.credit_card, color: Colors.white70),
                                filled: true,
                                fillColor: Colors.white24,
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.white54),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.white),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (v) {
                                final input = v?.trim() ?? '';
                                if (input.isEmpty) {
                                  return 'Matric No or Staff No is required';
                                }
                                final matricRegex = RegExp(r'^[A-Za-z]{2}\d{6}$');
                                final staffRegex = RegExp(r'^\d+$');
                                if (!matricRegex.hasMatch(input) && !staffRegex.hasMatch(input)) {
                                  return 'Enter a valid Matric No (e.g. DI230101) or Staff No (e.g. 1023)';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Password
                          AnimatedBuilder(
                            animation: _fieldsController,
                            builder: (_, child) => Opacity(
                              opacity: _fieldsFade.value,
                              child: Transform.translate(
                                offset: Offset(0, _fieldsSlide.value),
                                child: child,
                              ),
                            ),
                            child: TextFormField(
                              controller: _passCtrl,
                              obscureText: _obscurePassword,
                              style: textTheme.bodyLarge?.copyWith(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                labelStyle: const TextStyle(color: Colors.white70),
                                prefixIcon: const Icon(Icons.lock, color: Colors.white70),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                    color: Colors.white70,
                                  ),
                                  onPressed: _togglePassword,
                                ),
                                filled: true, fillColor: Colors.white24,
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.white54),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.white),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Password is required';
                                if (v.length < 6) return 'At least 6 characters';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Remember & Forgot
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberMe,
                                    checkColor: Colors.black,
                                    activeColor: Colors.white,
                                    side: const BorderSide(color: Colors.white70),
                                    onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                  ),
                                  const Text('Remember me', style: TextStyle(color: Colors.white70)),
                                ],
                              ),
                              TextButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                                ),
                                child: const Text(
                                  'Forgot Password?',
                                  style: TextStyle(color: Colors.white70, decoration: TextDecoration.underline),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Log In button (animated scale)
                          GestureDetector(
                            onTapDown: (_) => setState(() => _isPressed = true),
                            onTapUp: (_) {
                              _login();
                              setState(() => _isPressed = false);
                            },
                            onTapCancel: () => setState(() => _isPressed = false),
                            child: AnimatedScale(
                              scale: _isPressed ? 0.95 : 1.0,
                              duration: const Duration(milliseconds: 100),
                              child: SizedBox(
                                width: screenW, height: 52,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                    width: 24, height: 24,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                      : const Text(
                                    'Log In',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // First-Time Access – purple animated gradient
                          GradientButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const FirstTimeLoginScreen()),
                            ),
                            icon: const Icon(Icons.fingerprint, color: Colors.white),
                            label: const Text(
                              'First-Time Access',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Debug console
                    ExpansionTile(
                      title: const Text('Debug Console', style: TextStyle(color: Colors.white70)),
                      children: [
                        Container(
                          height: 200,
                          color: Colors.black87,
                          child: ListView.builder(
                            itemCount: _debugLogs.length,
                            itemBuilder: (_, i) => Text(
                              _debugLogs[i],
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    const Text('©️ 2025 NFC Attendance', style: TextStyle(color: Colors.white54)),
                    const SizedBox(height: 16),
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

class GradientButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget icon;
  final Widget label;

  const GradientButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -1.0, end: 2.0),
      duration: const Duration(seconds: 3),
      curve: Curves.linear,
      builder: (context, shift, child) {
        return Container(
          width: screenW,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-shift, 0),
              end: Alignment(shift, 0),
              colors: const [
                Color(0xFF8E2DE2), // deep purple
                Color(0xFF4A00E0), // vibrant violet
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Colors.black26, offset: Offset(0, 4), blurRadius: 6),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ElevatedButton.icon(
              onPressed: onPressed,
              icon: icon,
              label: label,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                elevation: 0,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        );
      },
    );
  }
}