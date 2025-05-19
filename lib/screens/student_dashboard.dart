// lib/screens/student_dashboard.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../ui/background.dart';
import '../main.dart';

/// Student Dashboard
/// — Lists only those attendanceSessions for subjects the student is enrolled in
/// — Color-coded present or absent
/// — Expands for check-in timestamp
/// — Sort by Date, Subject, or Lecturer
/// — Filter by Subject only
/// — Auto-redirect to login if unauthorized
class StudentDashboard extends StatefulWidget {
  const StudentDashboard({Key? key}) : super(key: key);

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _uid;
  late final AnimationController _listAnimController;
  final Duration _staggerInterval = const Duration(milliseconds: 100);

  final List<String> _sortOptions = ['Date', 'Subject', 'Lecturer'];
  String _sortBy = 'Date';
  String _filterSubject = 'All';

  @override
  void initState() {
    super.initState();
    _listAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _listAnimController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    _listAnimController
      ..reset()
      ..forward();
    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<bool> _didAttend(String uid, String sessionId) async {
    final doc = await _db
        .collection('attendanceSessions')
        .doc(sessionId)
        .collection('attendees')
        .doc(uid)
        .get();
    return doc.exists;
  }

  Future<DateTime?> _attendanceTimestamp(String uid, String sessionId) async {
    final doc = await _db
        .collection('attendanceSessions')
        .doc(sessionId)
        .collection('attendees')
        .doc(uid)
        .get();
    final map = doc.data();
    if (map == null) return null;
    return (map['timestamp'] as Timestamp?)?.toDate();
  }

  Widget _loadingCard() => Card(
    color: Colors.grey.shade800,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: const Padding(
      padding: EdgeInsets.all(12),
      child:
      Center(child: CircularProgressIndicator(color: Colors.white70)),
    ),
  );

  Widget _errorCard(String title) => Card(
    color: Colors.red.shade100,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(title, style: const TextStyle(color: Colors.red)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(builder: (ctx, auth, _) {
      if (auth.isLoading) {
        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()),
        );
      }
      final profile = auth.userProfile;
      if (profile == null || profile.role != 'student') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacementNamed(context, AppRoutes.login);
        });
        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()),
        );
      }
      _uid = profile.uid;

      return Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title:
          const Text('My Attendance', style: TextStyle(color: Colors.white)),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.refresh, color: Colors.white),
              label:
              const Text('Refresh', style: TextStyle(color: Colors.white)),
              onPressed: _handleRefresh,
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: auth.signOut,
            ),
          ],
        ),
        body: Stack(
          children: [
            const AnimatedWebBackground(),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 80),

                  // sort and subject filter
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      color: Colors.white24,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.sort, color: Colors.white70),
                                const SizedBox(width: 8),
                                const Text('Sort by:',
                                    style: TextStyle(color: Colors.white70)),
                                const SizedBox(width: 8),
                                _buildSortDropdown(),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.subject,
                                    color: Colors.white70),
                                const SizedBox(width: 8),
                                const Text('Subject:',
                                    style: TextStyle(color: Colors.white70)),
                                const SizedBox(width: 8),
                                _subjectFilterDropdown(),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // session list filtered to enrolled subjects
                  Expanded(
                    child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: _db.collection('users').doc(_uid).get(),
                      builder: (ctx1, userSnap) {
                        if (userSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (!userSnap.hasData || !userSnap.data!.exists) {
                          return Center(
                            child: Text(
                              'Error loading your enrollment data',
                              style: TextStyle(color: Colors.red.shade300),
                            ),
                          );
                        }

                        // pull student subjects from their user doc
                        final userData = userSnap.data!.data()!;
                        final enrolledSubs = (userData['subjects']
                        as List<dynamic>?)
                            ?.map((e) => (e['name'] as String).trim())
                            .toList() ??
                            <String>[];

                        return StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>>(
                          stream:
                          _db.collection('attendanceSessions').snapshots(),
                          builder: (ctx2, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            if (snap.hasError) {
                              return Center(
                                child: Text('Error loading sessions',
                                    style:
                                    TextStyle(color: Colors.red.shade300)),
                              );
                            }
                            var docs = snap.data?.docs ?? [];

                            // only sessions for enrolled subjects
                            docs = docs
                                .where((d) => enrolledSubs.contains(
                                (d.data()['subject'] as String).trim()))
                                .toList();

                            // apply subject filter
                            if (_filterSubject != 'All') {
                              docs = docs
                                  .where((d) =>
                              (d.data()['subject'] as String).trim() ==
                                  _filterSubject)
                                  .toList();
                            }

                            // apply sorting
                            switch (_sortBy) {
                              case 'Subject':
                                docs.sort((a, b) => (a.data()['subject']
                                as String)
                                    .compareTo(b.data()['subject'] as String));
                                break;
                              case 'Lecturer':
                                docs.sort((a, b) => (a.data()['lecturer']
                                as String)
                                    .compareTo(b.data()['lecturer'] as String));
                                break;
                              case 'Date':
                              default:
                                docs.sort((a, b) {
                                  final da = (a.data()['date'] as Timestamp)
                                      .toDate();
                                  final db_ = (b.data()['date'] as Timestamp)
                                      .toDate();
                                  return db_.compareTo(da);
                                });
                            }

                            return RefreshIndicator(
                              onRefresh: _handleRefresh,
                              child: ListView.builder(
                                physics:
                                const AlwaysScrollableScrollPhysics(),
                                itemCount: docs.length,
                                itemBuilder: (ctx3, i) {
                                  final session = docs[i];
                                  final data = session.data();
                                  final id = session.id;
                                  final date = (data['date'] as Timestamp?)
                                      ?.toDate();
                                  final subj = (data['subject'] as String)
                                      .trim();

                                  final start = (i *
                                      _staggerInterval.inMilliseconds) /
                                      _listAnimController
                                          .duration!
                                          .inMilliseconds;
                                  final end = (start + 0.3).clamp(0.0, 1.0);
                                  final anim = CurvedAnimation(
                                    parent: _listAnimController,
                                    curve: Interval(start, end,
                                        curve: Curves.easeOut),
                                  );

                                  return FadeTransition(
                                    opacity: anim,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                          begin: const Offset(0, .1),
                                          end: Offset.zero)
                                          .animate(anim),
                                      child: FutureBuilder<bool>(
                                        future: _didAttend(_uid!, id),
                                        builder: (c1, attSnap) {
                                          if (!attSnap.hasData &&
                                              attSnap.connectionState !=
                                                  ConnectionState.done) {
                                            return _loadingCard();
                                          }
                                          if (attSnap.hasError) {
                                            return _errorCard(
                                                'Error loading attendance');
                                          }
                                          final present = attSnap.data!;
                                          return Card(
                                            color: present
                                                ? Colors.green.shade300
                                                : Colors.red.shade300,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                BorderRadius.circular(12)),
                                            margin: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 8),
                                            child: ExpansionTile(
                                              backgroundColor:
                                              Colors.transparent,
                                              collapsedBackgroundColor:
                                              Colors.transparent,
                                              title: Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    date != null
                                                        ? DateFormat('yyyy-MM-dd')
                                                        .format(date)
                                                        : 'Unknown date',
                                                    style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 14),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(subj,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 18,
                                                          fontWeight:
                                                          FontWeight.bold)),
                                                ],
                                              ),
                                              subtitle: Text(
                                                'Status: ${present ? 'Present' : 'Absent'}',
                                                style: const TextStyle(
                                                    color: Colors.white70),
                                              ),
                                              children: [
                                                FutureBuilder<DateTime?>(
                                                  future: _attendanceTimestamp(
                                                      _uid!, id),
                                                  builder: (c2, tsSnap) {
                                                    if (tsSnap.connectionState ==
                                                        ConnectionState.waiting) {
                                                      return const Padding(
                                                        padding:
                                                        EdgeInsets.all(12),
                                                        child: Center(
                                                            child:
                                                            CircularProgressIndicator(
                                                              color:
                                                              Colors.white70,
                                                            )),
                                                      );
                                                    }
                                                    final dt = tsSnap.data;
                                                    final msg = dt != null
                                                        ? 'Checked in on ${DateFormat('yyyy-MM-dd HH:mm').format(dt)}'
                                                        : 'No record';
                                                    return Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 16,
                                                          vertical: 12),
                                                      child: Text(msg,
                                                          style: const TextStyle(
                                                              color: Colors
                                                                  .white70)),
                                                    );
                                                  },
                                                )
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text('© Tech Ventura',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildSortDropdown() {
    return DropdownButton<String>(
      value: _sortBy,
      dropdownColor: Colors.black87,
      style: const TextStyle(color: Colors.white),
      underline: const SizedBox(),
      items: _sortOptions
          .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
          .toList(),
      onChanged: (v) {
        if (v != null) {
          setState(() => _sortBy = v);
          _handleRefresh();
        }
      },
    );
  }

  Widget _subjectFilterDropdown() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('attendanceSessions').snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        final subjects = <String>{};
        for (var d in docs) {
          final s = (d.data()['subject'] as String?)?.trim();
          if (s?.isNotEmpty == true) subjects.add(s!);
        }
        final items = ['All', ...subjects.toList()..sort()];
        final current =
        items.contains(_filterSubject) ? _filterSubject : 'All';

        return DropdownButton<String>(
          value: current,
          dropdownColor: Colors.black87,
          style: const TextStyle(color: Colors.white),
          underline: const SizedBox(),
          items: items
              .map((subj) => DropdownMenuItem(value: subj, child: Text(subj)))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => _filterSubject = v);
              _handleRefresh();
            }
          },
        );
      },
    );
  }
}
