// lib/screens/session_list_page.dart

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth_provider.dart';
import '../ui/background.dart';

/// SessionListPage: corporate-themed attendance overview,
/// with transparent AppBar, shimmer loading, animated expansion,
/// pull-to-refresh, and Hero transitions into detail view.
class SessionListPage extends StatefulWidget {
  const SessionListPage({Key? key}) : super(key: key);

  @override
  _SessionListPageState createState() => _SessionListPageState();
}

class _SessionListPageState extends State<SessionListPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final AnimationController _bgAnimController;
  final GlobalKey<RefreshIndicatorState> _refreshKey =
  GlobalKey<RefreshIndicatorState>();

  String? lecturerStaffNumber;
  String? lecturerName;

  @override
  void initState() {
    super.initState();
    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    _loadLecturer();
  }

  Future<void> _loadLecturer() async {
    final user = await AuthProvider.getCurrentLecturer();
    if (mounted && user != null) {
      setState(() {
        lecturerStaffNumber = user['staffNumber'];
        lecturerName = user['name'];
      });
    }
  }

  @override
  void dispose() {
    _bgAnimController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessions synchronized')),
      );
      setState(() {});
    }
  }

  // Placeholder for shimmer loading
  Widget _buildShimmerPlaceholder() {
    return const Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(),
      child: SizedBox(height: 80),
    );
  }

  // Animated expansion for each subject group
  Widget _buildAnimatedSessionCard(
      String subject,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> sessions,
      List<String> sessionIds,
      ) {
    return ExpansionTile(
      title: Text(subject, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${sessions.length} session${sessions.length == 1 ? '' : 's'}'),
      children: sessions.map((session) {
        final s = session.data();
        final section = s['section'];
        final attType = s['attendanceType'];
        final date = s['date'];
        final startTime = s['startTime'];
        final endTime = s['endTime'];
        final duration = s['duration'] ?? '';
        return ListTile(
          title: Text('Section $section'),
          subtitle: Text('$attType • $date • $startTime–$endTime ($duration)'),
          trailing: Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.blueAccent),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SessionDetailPage(
                  subject: subject,
                  sessions: sessions,
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.blue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('Attendance Sessions',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Stack(
        children: [
          // Animated background (replace with your own or remove)
          AnimatedBuilder(
            animation: _bgAnimController,
            builder: (_, __) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue, Colors.lightBlueAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // Sessions list with refresh
          RefreshIndicator(
            key: _refreshKey,
            onRefresh: _onRefresh,
            displacement: 80,
            color: Colors.white,
            backgroundColor: Colors.blueAccent,
            edgeOffset: 48,
            child: lecturerStaffNumber == null
                ? ListView(
              padding: const EdgeInsets.only(top: kToolbarHeight + 32),
              children: const [
                Center(child: CircularProgressIndicator()),
              ],
            )
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('attendanceSessions')
                  .where('lecturerStaffNumber', isEqualTo: lecturerStaffNumber)
                  .orderBy('date', descending: true)
                  .snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return ListView.builder(
                    padding: const EdgeInsets.only(top: kToolbarHeight + 16),
                    itemCount: 4,
                    itemBuilder: (_, __) => _buildShimmerPlaceholder(),
                  );
                }
                if (snap.hasError) {
                  return ListView(
                    padding: const EdgeInsets.only(top: kToolbarHeight + 32),
                    children: [
                      Center(
                        child: Text(
                          'Error loading sessions: ${snap.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.only(top: kToolbarHeight + 32),
                    children: const [
                      Center(child: Text('No sessions found', style: TextStyle(fontSize: 16))),
                    ],
                  );
                }
                final bySubject = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
                for (var d in docs) {
                  final subj = (d.data()['subject'] as String?)?.trim() ?? '—';
                  bySubject.putIfAbsent(subj, () => []).add(d);
                }
                final subjects = bySubject.keys.toList()..sort();

                return ListView.builder(
                  padding: const EdgeInsets.only(top: kToolbarHeight + 16),
                  itemCount: subjects.length,
                  itemBuilder: (context, index) {
                    final subj = subjects[index];
                    final sessions = bySubject[subj]!;
                    final sessionIds = sessions.map((d) => d.id).toList();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildAnimatedSessionCard(subj, sessions, sessionIds),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer-loading without GradientTransform.
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  const ShimmerLoading({required this.child, Key? key})
      : super(key: key);

  @override
  _ShimmerLoadingState createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final width =
            MediaQuery.of(context).size.width - 32;
        const height = 80.0;
        final shimmerWidth = width / 3;
        final dx = (width + shimmerWidth) *
            _shimmerController.value -
            shimmerWidth;
        final shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            Colors.grey,
            Colors.white54,
            Colors.grey,
          ],
          stops: const [0.1, 0.5, 0.9],
        ).createShader(Rect.fromLTWH(
            -shimmerWidth + dx, 0, width + shimmerWidth * 2, height));
        return ShaderMask(
          shaderCallback: (_) => shader,
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
      child: widget.child,
    );
  }
}

/// AnimatedExpansionTile: expand/collapse with fade & size.
class AnimatedExpansionTile extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Object heroTag;

  const AnimatedExpansionTile({
    required this.title,
    this.subtitle,
    required this.children,
    required this.heroTag,
    Key? key,
  }) : super(key: key);

  @override
  _AnimatedExpansionTileState createState() =>
      _AnimatedExpansionTileState();
}

class _AnimatedExpansionTileState
    extends State<AnimatedExpansionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expController;
  late final Animation<double> _expandAnim;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _expController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnim = CurvedAnimation(
      parent: _expController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _expController.dispose();
    super.dispose();
  }

  void _toggleExpansion() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) _expController.forward();
      else _expController.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: Column(
        children: [
          ListTile(
            title: Text(widget.title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: widget.subtitle != null
                ? Text(widget.subtitle!)
                : null,
            trailing: RotationTransition(
              turns: Tween(begin: 0.0, end: 0.5)
                  .animate(_expandAnim),
              child: const Icon(Icons.expand_more),
            ),
            onTap: _toggleExpansion,
          ),
          ClipRect(
            child: SizeTransition(
              sizeFactor: _expandAnim,
              axisAlignment: 1,
              child: FadeTransition(
                opacity: _expandAnim,
                child: Column(children: widget.children),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Details of sessions with Hero animation.
class SessionDetailPage extends StatelessWidget {
  final String subject;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> sessions;

  const SessionDetailPage({
    required this.subject,
    required this.sessions,
    Key? key,
  }) : super(key: key);

  String _formatDate(dynamic dateValue) {
    // Handles both Timestamp and String
    if (dateValue is Timestamp) {
      return DateFormat('yyyy-MM-dd').format(dateValue.toDate());
    }
    if (dateValue is String) {
      return dateValue;
    }
    return '—';
  }

  String _formatTime(dynamic t) {
    if (t == null) return '—';
    return t.toString();
  }

  String _formatLecturer(dynamic name) {
    if (name is String && name.trim().isNotEmpty) return name;
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.blue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Session Details',
            style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // Replace with your animated background widget
          const AnimatedWebBackground(),
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(
                  top: kToolbarHeight + 16, bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: subject,
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 6,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          children: [
                            const Icon(Icons.menu_book_rounded,
                                color: Colors.blue, size: 32),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                subject,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...sessions.map((doc) {
                    final data = doc.data();
                    final section = data['section'] ?? '—';
                    final attendanceType =
                        data['attendanceType'] ?? '—';
                    final lecturer = _formatLecturer(data['lecturerName']);
                    final date = _formatDate(data['date']);
                    final startTime = _formatTime(data['startTime']);
                    final endTime = _formatTime(data['endTime']);
                    final duration = _formatTime(data['duration']);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Text(
                            section.toString(),
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          'Section $section – $attendanceType',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Lecturer: $lecturer'),
                              Text('Date: $date'),
                              Text('Time: $startTime - $endTime ($duration)'),
                            ],
                          ),
                        ),
                        trailing: const Icon(Icons.event_note, color: Colors.blueAccent),
                      ),
                    );
                  }),
                  if (sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 32.0),
                      child: Center(
                        child: Text(
                          'No sessions for this subject.',
                          style: TextStyle(color: Colors.white, fontSize: 18),
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
  }
}