// lib/screens/read_card_page.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'package:intl/intl.dart';

import '../ui/background.dart';

/// Attendance Scanner Screen
/// — Transparent AppBar
/// — Subject filter + Session dropdown
/// — Inline Create-Session with Subject dropdown
/// — NFC → attendanceSessions/{sessionId}/attendees/{userId}
/// — Persistent scan history in Firestore
/// — Gradient buttons, corporate styling
class ReadCardPage extends StatefulWidget {
  const ReadCardPage({Key? key}) : super(key: key);
  @override
  _ReadCardPageState createState() => _ReadCardPageState();
}

class _ReadCardPageState extends State<ReadCardPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Live sessions & selection
  List<_SessionRecord> _sessions = [];
  _SessionRecord? _activeSession;
  bool _loadingSessions = true;

  // Subject‐filter
  String? _filterSubject;

  // Inline “Create Session” form toggle
  bool _showCreateForm = false;

  // Create-form controllers
  late final TextEditingController _lecturerCtrl;
  String? _createSubject;
  DateTime _selectedDate = DateTime.now();
  final _createFormKey = GlobalKey<FormState>();

  // NFC scan + history
  bool _isScanning = false;
  String _statusMessage =
      'Select or create a session, then tap “Scan Card.”';
  final List<_ScanRecord> _history = [];

  // Animations
  late final AnimationController _animController;
  late final Animation<double> _fadeIn, _slideUp;

  @override
  void initState() {
    super.initState();
    _lecturerCtrl = TextEditingController();

    // Fetch sessions, then load history for the selected (or first) session
    _fetchSessions().then((_) => _loadHistoryForSession());

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _fadeIn = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
    );
    _slideUp = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _lecturerCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  /// Fetch sessions, preserve current selection if still valid.
  Future<void> _fetchSessions() async {
    setState(() => _loadingSessions = true);
    final oldId = _activeSession?.id;

    final snap = await _db
        .collection('attendanceSessions')
        .orderBy('date', descending: true)
        .get();

    _sessions = snap.docs.map((d) {
      final data = d.data();
      return _SessionRecord(
        id: d.id,
        date: (data['date'] as Timestamp).toDate(),
        subject: data['subject'] as String? ?? '–',
        lecturer: data['lecturer'] as String? ?? '–',
      );
    }).toList();

    if (_sessions.isEmpty) {
      _activeSession = null;
    } else if (oldId == null) {
      _activeSession = _sessions.first;
    } else {
      _activeSession = _sessions.firstWhere(
            (s) => s.id == oldId,
        orElse: () => _sessions.first,  // always returns a valid _SessionRecord
      );
    }

    setState(() => _loadingSessions = false);
  }

  void _toggleCreateForm() {
    setState(() {
      _showCreateForm = !_showCreateForm;
      if (!_showCreateForm) {
        _createSubject = null;
        _lecturerCtrl.clear();
        _selectedDate = DateTime.now();
      }
    });
  }

  /// Build a document ID like "MATH_ALICE"
  String _buildDocId(String subject, String lecturer) {
    final s = subject.trim().replaceAll(RegExp(r'\s+'), '_').toUpperCase();
    final l = lecturer.trim().replaceAll(RegExp(r'\s+'), '_').toUpperCase();
    return '${s}_$l';
  }

  Future<void> _createSession() async {
    if (!_createFormKey.currentState!.validate()) return;
    final subj = _createSubject!;
    final lect = _lecturerCtrl.text.trim();
    final docId = _buildDocId(subj, lect);

    final ref = _db.collection('attendanceSessions').doc(docId);
    if ((await ref.get()).exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ This session already exists.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    await ref.set({
      'date': Timestamp.fromDate(_selectedDate),
      'subject': subj,
      'lecturer': lect,
    });

    await _fetchSessions();
    // re-fetch history for the newly created/selected session
    await _loadHistoryForSession();

    setState(() {
      _showCreateForm = false;
    });
  }

  /// Scan NFC, record attendance and persist both to `attendees` and `scanHistory`.
  Future<void> _scanCard() async {
    if (_activeSession == null) {
      setState(() => _statusMessage =
      '⚠️ Please select or create a session first.');
      return;
    }
    setState(() {
      _isScanning = true;
      _statusMessage = '🔄 Scanning NFC…';
    });

    NFCTag tag;
    try {
      tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 10),
        iosAlertMessage: 'Hold card near device',
      );
    } catch (e) {
      setState(() {
        _statusMessage = '⚠️ NFC poll error: $e';
        _isScanning = false;
      });
      return;
    }

    String ic = '';
    try {
      if (tag.ndefAvailable == true) {
        final recs = await FlutterNfcKit.readNDEFRecords();
        if (recs.isNotEmpty && recs.first is ndef.TextRecord) {
          ic = (recs.first as ndef.TextRecord).text ?? '';
        }
      }
      if (ic.isEmpty) ic = tag.id;
      await FlutterNfcKit.finish(iosAlertMessage: '✅ Read OK');
    } catch (e) {
      setState(() {
        _statusMessage = '⚠️ NFC read error: $e';
        _isScanning = false;
      });
      return;
    }

    // Lookup user
    final users = await _db
        .collection('users')
        .where('ic', isEqualTo: ic)
        .limit(1)
        .get();
    if (users.docs.isEmpty) {
      setState(() {
        _statusMessage = '❌ Unknown IC: $ic';
        _isScanning = false;
      });
      return;
    }
    final user = users.docs.first;
    final data = user.data();
    final name = data['name'] as String? ?? ic;
    final photo = data['photoUrl'] as String?;

    final sessionRef =
    _db.collection('attendanceSessions').doc(_activeSession!.id);
    final timeStr = DateFormat.Hm().format(DateTime.now());

    // 1) Mark attendance for reporting
    try {
      await sessionRef
          .collection('attendees')
          .doc(user.id)
          .set({
        'timestamp': FieldValue.serverTimestamp(),
        'time': timeStr,
      }, SetOptions(merge: true));
    } catch (e) {
      setState(() {
        _statusMessage = '⚠️ Save failed: $e';
        _isScanning = false;
      });
      return;
    }

    // 2) Persist scan history for recall
    try {
      await sessionRef.collection('scanHistory').add({
        'name': name,
        'ic': ic,
        'photoUrl': photo,
        'time': timeStr,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // non-critical: we log but still proceed
      debugPrint('[ReadCardPage] Warning: failed to save history: $e');
    }

    // 3) Refresh in-memory history
    await _loadHistoryForSession();

    setState(() {
      _statusMessage = '✅ $name recorded at $timeStr';
      _isScanning = false;
    });
  }

  /// Load last 15 scanHistory records for the current session.
  Future<void> _loadHistoryForSession() async {
    if (_activeSession == null) {
      setState(() => _history.clear());
      return;
    }
    final snap = await _db
        .collection('attendanceSessions')
        .doc(_activeSession!.id)
        .collection('scanHistory')
        .orderBy('timestamp', descending: true)
        .limit(15)
        .get();
    final loaded = snap.docs.map((d) {
      final data = d.data();
      return _ScanRecord(
        name: data['name'] as String? ?? '',
        ic: data['ic'] as String? ?? '',
        photoUrl: data['photoUrl'] as String?,
        session: _activeSession!,
        time: data['time'] as String? ?? '',
        timestamp:
        (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();
    setState(() {
      _history
        ..clear()
        ..addAll(loaded);
    });
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade400),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // derive distinct subjects for filter & create-dropdown
    final subjects = <String>{
      for (var s in _sessions) s.subject
    }.toList()
      ..sort();
    subjects.insert(0, 'All Subjects');

    // filter sessions by subject
    final filtered = _filterSubject == null ||
        _filterSubject == 'All Subjects'
        ? _sessions
        : _sessions.where((s) => s.subject == _filterSubject).toList();

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Attendance Scanner',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload sessions & history',
            onPressed: () async {
              await _fetchSessions();
              await _loadHistoryForSession();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const AnimatedWebBackground(),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 100),

                  // 1) Subject filter
                  FadeTransition(
                    opacity: _fadeIn,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        color: Colors.white.withOpacity(0.9),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: DropdownButton<String>(
                            isExpanded: true,
                            underline: const SizedBox(),
                            value: _filterSubject ?? 'All Subjects',
                            items: subjects.map((subj) {
                              return DropdownMenuItem(
                                value: subj,
                                child: Text(subj,
                                    style: const TextStyle(
                                        color: Colors.black87, fontSize: 16)),
                              );
                            }).toList(),
                            onChanged: (v) async {
                              setState(() => _filterSubject = v);
                              await _loadHistoryForSession();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2) Session selector
                  FadeTransition(
                    opacity: _fadeIn,
                    child: _loadingSessions
                        ? const Center(
                        child:
                        CircularProgressIndicator(color: Colors.white))
                        : Padding(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        color: Colors.white.withOpacity(0.9),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: DropdownButton<_SessionRecord>(
                            isExpanded: true,
                            underline: const SizedBox(),
                            hint: const Text('Select session',
                                style: TextStyle(color: Colors.grey)),
                            value: _activeSession != null &&
                                filtered.any((s) =>
                                s.id == _activeSession!.id)
                                ? _activeSession
                                : null,
                            items: filtered.map((s) {
                              return DropdownMenuItem<
                                  _SessionRecord>(
                                value: s,
                                child: Text(
                                  '${DateFormat.yMMMd().format(s.date)} · ${s.subject}',
                                  style: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 16),
                                ),
                              );
                            }).toList(),
                            onChanged: (s) async {
                              setState(() => _activeSession = s);
                              await _loadHistoryForSession();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 3) Toggle inline create form
                  FadeTransition(
                    opacity: _fadeIn,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: GradientButton(
                        label: _showCreateForm
                            ? 'Cancel Creation'
                            : 'Create New Session',
                        icon: _showCreateForm ? Icons.close : Icons.add_circle,
                        gradient: _showCreateForm
                            ? const LinearGradient(colors: [
                          Color(0xFFB0BEC5),
                          Color(0xFF90A4AE)
                        ])
                            : const LinearGradient(colors: [
                          Color(0xFF29B6F6),
                          Color(0xFF0288D1)
                        ]),
                        onTap: _toggleCreateForm,
                      ),
                    ),
                  ),

                  // 4) Inline create form
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: _buildInlineCreateForm(subjects),
                    crossFadeState: _showCreateForm
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 300),
                  ),

                  const SizedBox(height: 24),

                  // 5) Scan button
                  FadeTransition(
                    opacity: _slideUp,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: GradientButton(
                        label: _isScanning ? 'Scanning…' : 'Scan Card',
                        icon: _isScanning
                            ? Icons.hourglass_top
                            : Icons.nfc,
                        gradient: const LinearGradient(colors: [
                          Color(0xFF66BB6A),
                          Color(0xFF388E3C)
                        ]),
                        onTap: _isScanning ? null : _scanCard,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Status message
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Divider(
                      color: Colors.white.withOpacity(0.3),
                      thickness: 1),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Recent Scans',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // History
                  ..._history.map(_buildHistoryTile),

                  const SizedBox(height: 24),
                  const Center(
                    child: Text(
                      '© Tech Ventura',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineCreateForm(List<String> subjects) {
    final pickSubjects =
    subjects.where((s) => s != 'All Subjects').toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Card(
        color: Colors.white.withOpacity(0.95),
        elevation: 4,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _createFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'New Session Details',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Date picker
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 30)),
                      lastDate:
                      DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat.yMMMMd().format(_selectedDate),
                          style: const TextStyle(fontSize: 16),
                        ),
                        const Icon(Icons.calendar_today,
                            color: Colors.black54),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Subject dropdown
                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Subject'),
                  value: _createSubject,
                  items: pickSubjects.map((subj) {
                    return DropdownMenuItem(
                      value: subj,
                      child: Text(subj),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _createSubject = v),
                  validator: (v) =>
                  v == null || v.isEmpty ? 'Required' : null,
                ),

                const SizedBox(height: 12),

                // Lecturer free text
                TextFormField(
                  controller: _lecturerCtrl,
                  decoration: _inputDecoration('Lecturer Name'),
                  validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
                ),

                const SizedBox(height: 20),

                // Save button
                GradientButton(
                  label: 'Save Session',
                  icon: Icons.save,
                  gradient: const LinearGradient(colors: [
                    Color(0xFF66BB6A),
                    Color(0xFF43A047)
                  ]),
                  onTap: _createSession,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTile(_ScanRecord record) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        color: Colors.black.withOpacity(0.7),
        elevation: 2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: CircleAvatar(
            radius: 24,
            backgroundImage: record.photoUrl != null
                ? NetworkImage(record.photoUrl!)
                : null,
            backgroundColor:
            record.photoUrl == null ? Colors.grey : null,
            child: record.photoUrl == null
                ? const Icon(Icons.person, color: Colors.white)
                : null,
          ),
          title: Text(record.name,
              style: const TextStyle(color: Colors.white)),
          subtitle: Text(
            '${DateFormat.yMMMd().format(record.session.date)} · ${record.time}',
            style: const TextStyle(color: Colors.white70),
          ),
          trailing: const Icon(Icons.check, color: Colors.greenAccent),
        ),
      ),
    );
  }
}

/// Reusable gradient button
class GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final VoidCallback? onTap;

  const GradientButton({
    required this.label,
    required this.icon,
    required this.gradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.6 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: gradient.colors.last.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Session model
class _SessionRecord {
  final String id;
  final DateTime date;
  final String subject;
  final String lecturer;

  _SessionRecord({
    required this.id,
    required this.date,
    required this.subject,
    required this.lecturer,
  });
}

/// Scan history model
class _ScanRecord {
  final String name;
  final String ic;
  final String time;
  final String? photoUrl;
  final _SessionRecord session;
  final DateTime timestamp;

  _ScanRecord({
    required this.name,
    required this.ic,
    this.photoUrl,
    required this.session,
    required this.time,
    required this.timestamp,
  });
}
