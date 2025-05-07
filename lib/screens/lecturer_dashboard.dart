// lib/screens/lecturer_dashboard.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../auth_provider.dart';
import '../ui/background.dart';
import '../main.dart';        // for AppRoutes
import 'read_card_page.dart';
import 'write_card_page.dart';

/// A dashboard for lecturers to view and manage attendance sessions.
/// — Supports sorting by Date, Subject, or Lecturer.
/// — Filters by Subject and Lecturer.
/// — Detailed per-student stats with warn functionality.
class LecturerDashboard extends StatefulWidget {
  const LecturerDashboard({Key? key}) : super(key: key);

  @override
  _LecturerDashboardState createState() => _LecturerDashboardState();
}

class _LecturerDashboardState extends State<LecturerDashboard>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final AnimationController _listAnimController;
  final Duration _staggerInterval = const Duration(milliseconds: 100);

  // --- Sort & Filter state ---
  final List<String> _sortOptions = ['Date', 'Subject', 'Lecturer'];
  String _sortBy = 'Date';
  String _filterSubject = 'All';
  String _filterLecturer = 'All';

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

  /// Triggers a quick fade-out/fade-in animation on the list.
  Future<void> _handleRefresh() async {
    _listAnimController
      ..reset()
      ..forward();
    await Future.delayed(const Duration(milliseconds: 200));
  }

  /// Appends a warning entry to the given user's document.
  Future<void> _sendWarning(String userId, String studentName) async {
    final ref = _db.collection('users').doc(userId);
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final warning = 'Absent without excuse on $date';

    try {
      await ref.update({
        'warnings': FieldValue.arrayUnion([warning])
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Warning sent to $studentName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send warning: $e')),
        );
      }
    }
  }

  /// Aggregates presence count across the given session IDs for a student.
  Future<Map<String, int>> _fetchStudentStats(
      String uid, List<String> sessionIds) async {
    final allAttendees = await _db.collectionGroup('attendees').get();
    final presentIds = allAttendees.docs
        .where((d) => d.id == uid)
        .map((d) => d.reference.parent.parent!.id)
        .toSet();
    final presentCount = sessionIds.where(presentIds.contains).length;
    return {'present': presentCount, 'total': sessionIds.length};
  }

  /// A loading placeholder card.
  Card _loadingCard() => Card(
    color: Colors.grey.shade800,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: const Padding(
      padding: EdgeInsets.all(12),
      child: Center(child: CircularProgressIndicator(color: Colors.white70)),
    ),
  );

  /// An error placeholder card.
  Card _errorCard(String msg) => Card(
    color: Colors.red.shade100,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(msg, style: const TextStyle(color: Colors.red)),
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
      if (profile == null || profile.role != 'lecturer') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacementNamed(context, AppRoutes.login);
        });
        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()),
        );
      }

      // ———————— Move dynamic greeting here ————————
      final userName = profile.name.trim().isNotEmpty
          ? profile.name.trim()
          : 'Lecturer';

      return Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: Text(
            'Hi $userName',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            _buildBarButton(Icons.refresh, 'Refresh', _handleRefresh),
            _buildBarButton(Icons.nfc, 'Scan', () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ReadCardPage()));
            }),
            _buildBarButton(Icons.post_add, 'Write', () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const WriteCardPage()));
            }),
            _buildBarButton(Icons.logout, 'Logout', auth.signOut),
          ],
        ),
        body: Stack(
          children: [
            const AnimatedWebBackground(),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 80),

                  // --- SORT & FILTER PANEL ---
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
                            _buildSortRow(),
                            const SizedBox(height: 8),
                            _buildSubjectFilterRow(),
                            const SizedBox(height: 8),
                            _buildLecturerFilterRow(),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- SESSION LIST ---
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _handleRefresh,
                      child: StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>>(
                        stream:
                        _db.collection('attendanceSessions').snapshots(),
                        builder: (ctx, snap) {
                          if (snap.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          if (snap.hasError) {
                            return Center(
                              child: Text('Error loading sessions',
                                  style: TextStyle(
                                      color: Colors.red.shade300)),
                            );
                          }

                          // 1. Raw documents (guard against null data)
                          final allDocs = snap.data?.docs ?? [];

                          // 2. Apply subject & lecturer filters
                          var filteredDocs = List.of(allDocs);
                          if (_filterSubject != 'All') {
                            filteredDocs = filteredDocs
                                .where((d) =>
                            ((d.data()?['subject'] as String?)
                                ?.trim() ??
                                '') ==
                                _filterSubject)
                                .toList();
                          }
                          if (_filterLecturer != 'All') {
                            filteredDocs = filteredDocs
                                .where((d) =>
                            ((d.data()?['lecturer'] as String?)
                                ?.trim() ??
                                '') ==
                                _filterLecturer)
                                .toList();
                          }

                          // 3. Group by subject
                          final bySubject = <String,
                              List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
                          for (var d in filteredDocs) {
                            final subj = (d.data()?['subject'] as String?)
                                ?.trim() ??
                                '—';
                            bySubject.putIfAbsent(subj, () => []).add(d);
                          }
                          var subjects = bySubject.keys.toList();

                          // 4. Sort groups dynamically
                          switch (_sortBy) {
                            case 'Subject':
                              subjects.sort();
                              break;
                            case 'Lecturer':
                              subjects.sort((a, b) {
                                final la = (bySubject[a]!.first
                                    .data()?['lecturer'] as String?)
                                    ?.trim() ??
                                    '';
                                final lb = (bySubject[b]!.first
                                    .data()?['lecturer'] as String?)
                                    ?.trim() ??
                                    '';
                                return la.compareTo(lb);
                              });
                              break;
                            case 'Date':
                            default:
                              subjects.sort((a, b) {
                                DateTime newestA = bySubject[a]!
                                    .map((d) => (d.data()?['date']
                                as Timestamp?)
                                    ?.toDate() ??
                                    DateTime.fromMillisecondsSinceEpoch(
                                        0))
                                    .reduce((x, y) =>
                                x.isAfter(y) ? x : y);
                                DateTime newestB = bySubject[b]!
                                    .map((d) => (d.data()?['date']
                                as Timestamp?)
                                    ?.toDate() ??
                                    DateTime.fromMillisecondsSinceEpoch(
                                        0))
                                    .reduce((x, y) =>
                                x.isAfter(y) ? x : y);
                                return newestB.compareTo(newestA);
                              });
                          }

                          // 5. Build list
                          return ListView.builder(
                            physics:
                            const AlwaysScrollableScrollPhysics(),
                            itemCount: subjects.length,
                            itemBuilder: (ctx2, i) {
                              final subj = subjects[i];
                              final sessions = bySubject[subj]!;
                              final sessionIds =
                              sessions.map((d) => d.id).toList();

                              final start = (i *
                                  _staggerInterval.inMilliseconds) /
                                  _listAnimController.duration!
                                      .inMilliseconds;
                              final end =
                              (start + 0.3).clamp(0.0, 1.0);
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
                                  child: _buildSessionCard(
                                      subj, sessions, sessionIds),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text('© Tech Ventura',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Encapsulates each subject block with an ExpansionTile.
  Widget _buildSessionCard(String subject,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> sessions,
      List<String> sessionIds) {
    return Card(
      color: Colors.white12,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      margin:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        title: Text(subject,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${sessions.length} session${sessions.length == 1 ? '' : 's'}',
          style:
          const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        children: [
          StreamBuilder<
              QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('users')
                .where('role', isEqualTo: 'student')
                .snapshots(),
            builder: (c2, stuSnap) {
              if (stuSnap.connectionState ==
                  ConnectionState.waiting) {
                return _loadingCard();
              }
              if (stuSnap.hasError) {
                return _errorCard('Error loading students');
              }
              final students = stuSnap.data?.docs ?? [];
              if (students.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No students registered',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }
              return Column(
                children: students.map((stuDoc) {
                  final sid = stuDoc.id;
                  final sname = (stuDoc.data()?['name']
                  as String?)
                      ?.trim() ??
                      '—';
                  return FutureBuilder<Map<String, int>>(
                      future: _fetchStudentStats(
                          sid, sessionIds),
                      builder: (c3, statSnap) {
                        if (statSnap.connectionState !=
                            ConnectionState.done ||
                            statSnap.data == null) {
                          return _loadingCard();
                        }
                        final stats = statSnap.data!;
                        final present = stats['present']!;
                        final total = stats['total']!;
                        final percent = total > 0
                            ? ((present / total) * 100)
                            .round()
                            : 0;
                        final isPerfect = percent == 100;
                        return ListTile(
                          leading: Icon(
                            isPerfect
                                ? Icons
                                .check_circle_outline
                                : Icons.highlight_off,
                            color: isPerfect
                                ? Colors.greenAccent
                                : Colors.redAccent,
                          ),
                          title: Text(sname,
                              style: const TextStyle(
                                  color: Colors.white)),
                          subtitle: Text(
                            '$percent% ($present/$total)',
                            style: const TextStyle(
                                color: Colors.white70),
                          ),
                          trailing: isPerfect
                              ? null
                              : _RedWarnButton(
                            onPressed: () => _sendWarning(
                                sid, sname),
                          ),
                        );
                      });
                }).toList(),
              );
            },
          )
        ],
      ),
    );
  }

  /// Builds one of the AppBar icon+label buttons.
  Widget _buildBarButton(
      IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 4),
            Text(label,
                style:
                const TextStyle(color: Colors.white, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  /// Sort dropdown row.
  Widget _buildSortRow() {
    return Row(
      children: [
        const Icon(Icons.sort, color: Colors.white70),
        const SizedBox(width: 8),
        const Text('Sort by:', style: TextStyle(color: Colors.white70)),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: _sortBy,
          dropdownColor: Colors.black87,
          style: const TextStyle(color: Colors.white),
          underline: const SizedBox(),
          items: _sortOptions
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _sortBy = v);
          },
        ),
      ],
    );
  }

  /// Subject filter dropdown row.
  Widget _buildSubjectFilterRow() {
    return Row(
      children: [
        const Icon(Icons.subject, color: Colors.white70),
        const SizedBox(width: 8),
        const Text('Subject:', style: TextStyle(color: Colors.white70)),
        const SizedBox(width: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db.collection('attendanceSessions').snapshots(),
          builder: (ctx, snap) {
            final docs = snap.data?.docs ?? [];
            final subjects = <String>{'All'};
            for (var d in docs) {
              final s = (d.data()?['subject'] as String?)
                  ?.trim();
              if (s?.isNotEmpty == true) {
                subjects.add(s!);
              }
            }
            final items = subjects.toList()..sort();
            final current = items.contains(_filterSubject)
                ? _filterSubject
                : 'All';

            return DropdownButton<String>(
              value: current,
              dropdownColor: Colors.black87,
              style: const TextStyle(color: Colors.white),
              underline: const SizedBox(),
              items: items
                  .map((s) => DropdownMenuItem(
                  value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _filterSubject = v);
              },
            );
          },
        ),
      ],
    );
  }

  /// Lecturer filter dropdown row.
  Widget _buildLecturerFilterRow() {
    return Row(
      children: [
        const Icon(Icons.person, color: Colors.white70),
        const SizedBox(width: 8),
        const Text('Lecturer:', style: TextStyle(color: Colors.white70)),
        const SizedBox(width: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db.collection('attendanceSessions').snapshots(),
          builder: (ctx, snap) {
            final docs = snap.data?.docs ?? [];
            final lecs = <String>{'All'};
            for (var d in docs) {
              final l = (d.data()?['lecturer'] as String?)
                  ?.trim();
              if (l?.isNotEmpty == true) {
                lecs.add(l!);
              }
            }
            final items = lecs.toList()..sort();
            final current = items.contains(_filterLecturer)
                ? _filterLecturer
                : 'All';

            return DropdownButton<String>(
              value: current,
              dropdownColor: Colors.black87,
              style: const TextStyle(color: Colors.white),
              underline: const SizedBox(),
              items: items
                  .map((l) => DropdownMenuItem(
                  value: l, child: Text(l)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _filterLecturer = v);
              },
            );
          },
        ),
      ],
    );
  }
}

/// A rounded red gradient button used to send a warning.
class _RedWarnButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _RedWarnButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE53935), Color(0xFFD32F2F)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('Warn',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
