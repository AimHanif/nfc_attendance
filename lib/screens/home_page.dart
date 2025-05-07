// lib/screens/home_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../ui/background.dart';
import 'write_card_page.dart';
import 'read_card_page.dart';
import 'student_dashboard.dart';

/// Toggle this to `false` to hide the Write Card button at runtime.
const bool showWriteButton = true;

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final Animation<double> _logoScale;
  late final AnimationController _writeBtnController;
  late final Animation<double> _writeBtnScale;
  late final AnimationController _readBtnController;
  late final Animation<double> _readBtnScale;
  late final AnimationController _footerController;
  late final Animation<double> _footerFade;

  @override
  void initState() {
    super.initState();

    // Logo animation
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _logoScale = CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    );
    _logoController.forward();

    // Write button animation
    _writeBtnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _writeBtnScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _writeBtnController, curve: Curves.easeOutBack),
    );
    Future.delayed(const Duration(milliseconds: 600), () {
      if (showWriteButton) _writeBtnController.forward();
    });

    // Read button animation
    _readBtnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _readBtnScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _readBtnController, curve: Curves.easeOutBack),
    );
    Future.delayed(const Duration(milliseconds: 900), () {
      _readBtnController.forward();
    });

    // Footer fade-in
    _footerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _footerFade = CurvedAnimation(
      parent: _footerController,
      curve: Curves.easeIn,
    );
    Future.delayed(const Duration(milliseconds: 1200), () {
      _footerController.forward();
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _writeBtnController.dispose();
    _readBtnController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        // While loading auth state, show a spinner
        if (auth.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // If not signed in, redirect to login
        if (auth.userProfile == null) {
          // You might navigate to /login here instead
          return const Scaffold(
            body: Center(child: Text('Please log in to continue')),
          );
        }

        final role = auth.userProfile!.role;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text(''),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: Stack(
            children: [
              const AnimatedWebBackground(),
              SafeArea(
                child: Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      ScaleTransition(
                        scale: _logoScale,
                        child: Column(
                          children: [
                            Text(
                              'NFC Attendance',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                                color: Colors.white,
                                shadows: const [
                                  BoxShadow(
                                    offset: Offset(2, 2),
                                    blurRadius: 6,
                                    color: Colors.black45,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.8),
                                    Colors.white.withOpacity(0.3)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.nfc,
                                size: 64,
                                color: Colors.blueAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 80),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            if (role == 'student')
                              ScaleTransition(
                                scale: _readBtnScale,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: _AnimatedGradientButton(
                                    label: 'View My Attendance',
                                    icon: Icons.list_alt,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const StudentDashboard(),
                                        ),
                                      );
                                    },
                                    gradient: const LinearGradient(
                                      colors: [Colors.teal, Colors.lightGreenAccent],
                                    ),
                                  ),
                                ),
                              )
                            else if (role == 'lecturer') ...[
                              if (showWriteButton)
                                ScaleTransition(
                                  scale: _writeBtnScale,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: _AnimatedGradientButton(
                                      label: 'Write Card',
                                      icon: Icons.credit_card,
                                      onTap: () => Navigator.pushNamed(context, '/write'),
                                      gradient: const LinearGradient(
                                        colors: [Colors.deepPurple, Colors.purpleAccent],
                                      ),
                                    ),
                                  ),
                                ),
                              ScaleTransition(
                                scale: _readBtnScale,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: _AnimatedGradientButton(
                                    label: 'Read Card',
                                    icon: Icons.nfc,
                                    onTap: () => Navigator.pushNamed(context, '/read'),
                                    gradient: const LinearGradient(
                                      colors: [Colors.teal, Colors.lightGreenAccent],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      FadeTransition(
                        opacity: _footerFade,
                        child: const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Developed by Tech Ventura',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A custom button widget with gradient background, shadow, and ripple effect.
class _AnimatedGradientButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Gradient gradient;

  const _AnimatedGradientButton({
    Key? key,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.gradient,
  }) : super(key: key);

  @override
  __AnimatedGradientButtonState createState() =>
      __AnimatedGradientButtonState();
}

class __AnimatedGradientButtonState extends State<_AnimatedGradientButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _elevationAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _elevationAnim = Tween<double>(begin: 4, end: 12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _elevationAnim,
      builder: (context, child) {
        return GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: Container(
            width: 260,
            height: 56,
            decoration: BoxDecoration(
              gradient: widget.gradient,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: _elevationAnim.value,
                  offset: const Offset(2, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
