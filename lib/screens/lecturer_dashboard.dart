// lib/screens/lecturer_dashboard.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:nfc_attendance/screens/session_list.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../ui/background.dart';
import 'read_card_page.dart';
import 'write_card_page.dart';

/// LecturerDashboard: corporate-grade UX with greeting aligned to header icons,
/// user profile, and 2×2 + “Sessions” action grid.
class LecturerDashboard extends StatefulWidget {
  const LecturerDashboard({Key? key}) : super(key: key);

  @override
  _LecturerDashboardState createState() => _LecturerDashboardState();
}

class _LecturerDashboardState extends State<LecturerDashboard>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final AnimationController _bgAnimController;

  @override
  void initState() {
    super.initState();
    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgAnimController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session list refreshed')),
      );
    }
  }

  /// Builds the lecturer's avatar by:
  /// 1) using profile.photoUrl if available, or
  /// 2) fetching 'student_photos/{uid}.jpg' from Storage.
  Widget _buildAvatar(String? photoUrl, String uid) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 32,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: NetworkImage(photoUrl),
      );
    } else {
      return FutureBuilder<String>(
        future: FirebaseStorage.instance
            .ref('student_photos/$uid.jpg')
            .getDownloadURL(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const CircleAvatar(
              radius: 32,
              backgroundColor: Colors.grey,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            );
          }
          if (snap.hasError) {
            return const CircleAvatar(
              radius: 32,
              backgroundColor: Colors.grey,
              child: Icon(Icons.person, size: 32, color: Colors.white),
            );
          }
          return CircleAvatar(
            radius: 32,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: NetworkImage(snap.data!),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(builder: (ctx, auth, _) {
      if (auth.isLoading || auth.userProfile == null) {
        return const Scaffold(
          backgroundColor: Colors.blue,
          body: Center(child: CircularProgressIndicator(color: Colors.white)),
        );
      }

      final profile = auth.userProfile!;
      final name = profile.name.trim().isNotEmpty
          ? profile.name.trim()
          : 'Lecturer';
      final photoUrl = profile.photoUrl;

      return Scaffold(
        backgroundColor: Colors.blue,
        body: Stack(
          children: [
            // Animated corporate backdrop
            SafeArea(
              child: AnimatedBuilder(
                animation: _bgAnimController,
                builder: (_, __) => AnimatedWebBackground(),
              ),
            ),

            // Content overlay
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Greeting + header icons aligned
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Hi, $name',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Row(
                          children: const [
                            Icon(Icons.menu, color: Colors.white, size: 28),
                            SizedBox(width: 16),
                            Icon(Icons.notifications,
                                color: Colors.white, size: 28),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Profile card
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            _buildAvatar(photoUrl, profile.uid),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    profile.role.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Action grid
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildActionCard(
                            icon: Icons.refresh,
                            label: 'Refresh',
                            onTap: _handleRefresh,
                          ),
                          _buildActionCard(
                            icon: Icons.nfc,
                            label: 'Scan',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ReadCardPage()),
                            ),
                          ),
                          _buildActionCard(
                            icon: Icons.post_add,
                            label: 'Write',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const WriteCardPage()),
                            ),
                          ),
                          _buildActionCard(
                            icon: Icons.list_alt,
                            label: 'Sessions',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SessionListPage()),
                            ),
                          ),
                          _buildActionCard(
                            icon: Icons.logout,
                            label: 'Logout',
                            onTap: auth.signOut,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Footer
                  const Center(
                    child: Text(
                      '© Tech Ventura',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Central builder for each action tile.
  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Card(
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.blue.shade50,
                child: Icon(icon, size: 32, color: Colors.blue),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
