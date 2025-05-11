// lib/screens/session_list_page.dart

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    // Animate background subtly
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

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessions synchronized')),
      );
      setState(() {});
    }
  }

  Future<Map<String, int>> _fetchStudentStats(
      String uid, List<String> sessionIds) async {
    final query = await _db.collectionGroup('attendees').get();
    final presentIds = query.docs
        .where((d) => d.id == uid)
        .map((d) => d.reference.parent.parent!.id)
        .toSet();
    final present = sessionIds.where(presentIds.contains).length;
    return {'present': present, 'total': sessionIds.length};
  }

  Widget _buildShimmerPlaceholder() {
    return const ShimmerLoading(
      child: Card(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(),
        child: SizedBox(height: 80),
      ),
    );
  }

  Widget _buildAnimatedSessionCard(
      String subject,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> sessions,
      List<String> sessionIds,
      ) {
    return AnimatedExpansionTile(
      title: subject,
      subtitle: '${sessions.length} session${sessions.length == 1 ? '' : 's'}',
      heroTag: subject,
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('users')
              .where('role', isEqualTo: 'student')
              .snapshots(),
          builder: (ctx, stuSnap) {
            if (stuSnap.connectionState == ConnectionState.waiting) {
              return _buildShimmerPlaceholder();
            }
            if (stuSnap.hasError) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Error loading students',
                    style: TextStyle(color: Colors.red)),
              );
            }
            final students = stuSnap.data?.docs ?? [];
            if (students.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No students registered'),
              );
            }
            return Column(
              children: students.map((stu) {
                final uid = stu.id;
                final name = (stu.data()['name'] as String?)?.trim() ?? '—';
                return FutureBuilder<Map<String, int>>(
                  future: _fetchStudentStats(uid, sessionIds),
                  builder: (c3, statSnap) {
                    if (statSnap.connectionState != ConnectionState.done ||
                        statSnap.data == null) {
                      return _buildShimmerPlaceholder();
                    }
                    final stats = statSnap.data!;
                    final present = stats['present']!;
                    final total = stats['total']!;
                    final percent = total > 0
                        ? ((present / total) * 100).round()
                        : 0;
                    final isPerfect = percent == 100;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: Icon(
                          isPerfect
                              ? Icons.check_circle_outline
                              : Icons.highlight_off,
                          color: isPerfect ? Colors.green : Colors.redAccent,
                          size: 28,
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontSize: 16),
                        ),
                        subtitle: Text(
                          '$percent% ($present/$total)',
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: isPerfect
                            ? null
                            : ElevatedButton(
                          onPressed: () async {
                            final warning =
                                'Absent on ${DateFormat('yyyy-MM-dd').format(DateTime.now())}';
                            await _db
                                .collection('users')
                                .doc(uid)
                                .update({
                              'warnings':
                              FieldValue.arrayUnion([warning])
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content:
                                Text('Warning sent to $name'),
                              ));
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            elevation: 2,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'WARN',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            );
          },
        ),
      ],
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
          // full-bleed animated background
          AnimatedBuilder(
            animation: _bgAnimController,
            builder: (_, __) => const AnimatedWebBackground(),
          ),

          // content with pull-to-refresh
          RefreshIndicator(
            key: _refreshKey,
            onRefresh: _onRefresh,
            displacement: 80,
            color: Colors.white,
            backgroundColor: Colors.blueAccent,
            edgeOffset: 48,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
              _db.collection('attendanceSessions').snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState ==
                    ConnectionState.waiting) {
                  return ListView.builder(
                    padding: const EdgeInsets.only(
                        top: kToolbarHeight + 16),
                    itemCount: 4,
                    itemBuilder: (_, __) =>
                        _buildShimmerPlaceholder(),
                  );
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error loading sessions: ${snap.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.only(
                        top: kToolbarHeight + 16),
                    children: const [
                      Center(child: Text('No sessions found')),
                    ],
                  );
                }
                final bySubject = <String,
                    List<QueryDocumentSnapshot<
                        Map<String, dynamic>>>>{};
                for (var d in docs) {
                  final subj = (d.data()['subject']
                  as String?)
                      ?.trim() ??
                      '—';
                  bySubject
                      .putIfAbsent(subj, () => [])
                      .add(d);
                }
                final subjects = bySubject.keys.toList()
                  ..sort();

                return ListView.builder(
                  padding: const EdgeInsets.only(
                      top: kToolbarHeight + 16),
                  itemCount: subjects.length,
                  itemBuilder: (context, index) {
                    final subj = subjects[index];
                    final sessions = bySubject[subj]!;
                    final sessionIds =
                    sessions.map((d) => d.id).toList();
                    return Padding(
                      padding:
                      const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          PageRouteBuilder(
                            transitionDuration:
                            const Duration(
                                milliseconds: 600),
                            pageBuilder:
                                (ctx, anim1, anim2) =>
                                FadeTransition(
                                  opacity: anim1,
                                  child: SessionDetailPage(
                                    subject: subj,
                                    sessions: sessions,
                                  ),
                                ),
                          ),
                        ),
                        child: Hero(
                          tag: subj,
                          child: _buildAnimatedSessionCard(
                              subj, sessions, sessionIds),
                        ),
                      ),
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
  final List<QueryDocumentSnapshot<Map<String, dynamic>>>
  sessions;

  const SessionDetailPage({
    required this.subject,
    required this.sessions,
    Key? key,
  }) : super(key: key);

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
          icon:
          const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // direct background; no controller needed here
          const AnimatedWebBackground(),
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(
                  top: kToolbarHeight + 16, bottom: 32),
              child: Column(
                children: [
                  Hero(
                    tag: subject,
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(12)),
                      elevation: 6,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(subject,
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight:
                                FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var doc in sessions)
                    Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(
                          DateFormat(
                              'yyyy-MM-dd – HH:mm')
                              .format((doc.data()[
                          'date']
                          as Timestamp)
                              .toDate()),
                        ),
                        subtitle: Text(
                            'Subject: ${(doc.data()['subject']
                            as String?)
                                ?.trim() ??
                                '—'}'),
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

// -----------------------------------------------------------------------------
// End of session_list_page.dart — 400+ lines complete
// -----------------------------------------------------------------------------
