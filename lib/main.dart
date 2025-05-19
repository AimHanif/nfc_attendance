// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

// Firebase Options (generated via flutterfire CLI)
import 'firebase_options.dart';

// Core State Management
import 'auth_provider.dart';

// UI & Screens
import 'ui/background.dart';
import 'screens/login.dart';
import 'screens/first_time_login.dart';
import 'screens/write_card_page.dart';
import 'screens/read_card_page.dart';
import 'screens/lecturer_dashboard.dart';
import 'screens/student_dashboard.dart';

/// Entry point for the NFC Attendance application.
/// Ensures that all Flutter bindings and Firebase SDKs are initialized
/// before the UI is rendered.
Future<void> main() async {
  // 1️⃣ Wire up platform channels for plugins
  WidgetsFlutterBinding.ensureInitialized();

  // 2️⃣ Initialize Firebase with the current platform's options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 3️⃣ Launch the app within a provider scope
  runApp(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(),
      child: const MyApp(),
    ),
  );
}

/// Root widget that configures theme, routing, and the authentication wrapper.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NFC Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // Start with a branded splash screen
      home: const SplashScreen(),
      // Define named routes for maintainability
      routes: {
        AppRoutes.login: (_) => const LoginScreen(),
        AppRoutes.firstTimeLogin: (_) => const FirstTimeLoginScreen(),
        AppRoutes.write: (_) => const WriteCardPage(),
        AppRoutes.read: (_) => ReadCardPage(),
        AppRoutes.lecturerDashboard: (_) => const LecturerDashboard(),
        AppRoutes.studentDashboard: (_) => const StudentDashboard(),
      },
    );
  }
}

/// Centralized definition of all named routes.
class AppRoutes {
  static const String login               = '/login';
  static const String firstTimeLogin      = '/firstTimeLogin';
  static const String home                = '/home';
  static const String write               = '/write';
  static const String read                = '/read';
  static const String lecturerDashboard   = '/lecturer';
  static const String studentDashboard    = '/student';
}

/// The design system: typography, color palette, and component themes.
class AppTheme {
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.blue,
    textTheme: GoogleFonts.poppinsTextTheme().apply(
      bodyColor: Colors.black87,
      displayColor: Colors.blueAccent,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.blueAccent,
      titleTextStyle: GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      elevation: 2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      labelStyle: GoogleFonts.poppins(color: Colors.grey.shade700),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// Splash screen with logo animation, then transitions to auth logic.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double>   _animation;

  @override
  void initState() {
    super.initState();
    // Bounce animation for the logo
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    // After branding display, navigate to the authentication wrapper
    Future.delayed(const Duration(seconds: 4), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedWebBackground(),
          Center(
            child: ScaleTransition(
              scale: _animation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.nfc, size: 100, color: Colors.white70),
                  const SizedBox(height: 16),
                  Text(
                    'NFC Attendance',
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: const [
                        Shadow(offset: Offset(2, 2), blurRadius: 4, color: Colors.black45)
                      ],
                    ),
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

/// Chooses the correct landing page based on authentication state.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (auth.userProfile == null) {
          return const LoginScreen();
        }
        // only force password-change flow for non-students
        if (auth.userProfile!.role != 'student'
            && auth.userProfile!.mustChangePassword) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await auth.signOut();
            Navigator.of(context).pushReplacementNamed(AppRoutes.login);
          });
          return const Scaffold(
            body: Center(
              child: Text(
                'You must set your password. Check your email for the link.',
              ),
            ),
          );
        }
        return auth.userProfile!.role == 'student'
            ? const StudentDashboard()
            : const LecturerDashboard();
      },
    );
  }
}


// ---------------------------------------------------------------------------
// Decorative UI components (AppHeader, AppFooter, NavButton, etc).
// These can be imported into individual screens if needed.
// ---------------------------------------------------------------------------

/// Standard AppBar wrapper with Poppins typography.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  const AppHeader({super.key, required this.title, this.actions});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// Simple footer widget with corporate credit.
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: Colors.blueAccent.withOpacity(0.8),
      alignment: Alignment.center,
      child: Text(
        '© 2025 Tech Ventura — All Rights Reserved',
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
      ),
    );
  }
}

/// Reusable button combining icon + label.
class NavButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const NavButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.poppins(fontSize: 16),
      ),
    );
  }
}

/// Section header for grouping UI elements.
class SectionHeader extends StatelessWidget {
  final String text;
  const SectionHeader({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.blueAccent,
      ),
    );
  }
}

/// Spacing utility widget.
class VerticalSpacer extends StatelessWidget {
  final double height;
  const VerticalSpacer(this.height, {super.key});

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}
