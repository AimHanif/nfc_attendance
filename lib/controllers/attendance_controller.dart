import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'package:intl/intl.dart';
import 'package:encrypt/encrypt.dart' as enc;

import '../scan_record.dart';
import '../session_record.dart';

class AttendanceController extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── General state ──────────────────────────────────────────────────────
  List<SessionRecord> sessions = [];
  SessionRecord?      activeSession;
  bool                loadingSessions = true;

  // ─── Filters & toggles ──────────────────────────────────────────────────
  String? filterSubject;
  bool   showCreateForm      = false;
  bool   showSessionSelector = false;

  // ─── New-session form state ─────────────────────────────────────────────
  final formKey = GlobalKey<FormState>();
  DateTime      selectedDate     = DateTime.now();
  List<String>  createSections   = [];
  String?       createSubject;
  String?       attendanceType;
  TimeOfDay?    startTime;
  TimeOfDay?    endTime;

  // ─── Inline fetchers ────────────────────────────────────────────────────
  List<String> availableSubjects = [];
  List<String> availableSections = [];

  // ─── NFC scan + history ─────────────────────────────────────────────────
  bool            isScanning     = false;
  String          statusMessage  = 'Select or create a session, then tap “Scan Card.”';
  List<ScanRecord> history       = [];

  /// Initialize by loading sessions + history
  Future<void> init() async {
    await fetchSessions();
    await loadHistoryForSession();
  }

  /// Fetch the list of attendance sessions
  Future<void> fetchSessions() async {
    loadingSessions = true;
    notifyListeners();

    final oldId = activeSession?.id;
    final snap  = await _db
        .collection('attendanceSessions')
        .orderBy('date', descending: true)
        .get();

    sessions = snap.docs.map((d) => SessionRecord.fromDoc(d)).toList();
    if (sessions.isEmpty) {
      activeSession = null;
    } else if (oldId == null) {
      activeSession = sessions.first;
    } else {
      activeSession = sessions.firstWhere(
            (s) => s.id == oldId,
        orElse: () => sessions.first,
      );
    }

    loadingSessions = false;
    notifyListeners();
  }

  /// Load the last 15 scanHistory docs for the current session
  Future<void> loadHistoryForSession() async {
    if (activeSession == null) {
      history = [];
      notifyListeners();
      return;
    }

    final snap = await _db
        .collection('attendanceSessions')
        .doc(activeSession!.id)
        .collection('scanHistory')
        .orderBy('timestamp', descending: true)
        .limit(15)
        .get();

    history = snap.docs.map((d) {
      final data = d.data();
      return ScanRecord(
        name:      data['name']     as String? ?? '',
        ic:        data['ic']       as String? ?? '',
        photoUrl:  data['photoUrl'] as String?,
        session:   activeSession!,
        time:      data['time']     as String? ?? '',
        timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();

    notifyListeners();
  }

  // ─── Filters & toggles ──────────────────────────────────────────────────

  /// Picks a new subject filter and immediately re‐selects
  /// the first session in that filtered list (or null).
  void setFilterSubject(String? subject) {
    // “All Subjects” means “no filter”
    if (subject == 'All Subjects') {
      filterSubject = null;
    } else {
      filterSubject = subject;
    }

    // Rebuild the filtered list
    final filtered = sessions.where((s) =>
    filterSubject == null || s.subject == filterSubject).toList();

    // Pick the first one (or clear)
    if (filtered.isNotEmpty) {
      activeSession = filtered.first;
    } else {
      activeSession = null;
    }

    notifyListeners();
  }


  void toggleCreateForm() {
    showCreateForm = !showCreateForm;
    if (showCreateForm) showSessionSelector = false;
    else {
      formKey.currentState?.reset();
      createSubject = null;
      createSections.clear();
      attendanceType = null;
      startTime = endTime = null;
      selectedDate = DateTime.now();
      availableSections.clear();
      availableSubjects.clear();
    }
    notifyListeners();
  }

  void toggleSessionSelector() {
    showSessionSelector = !showSessionSelector;
    if (showSessionSelector) showCreateForm = false;
    notifyListeners();
  }

  /// User picked an existing session
  Future<void> selectSession(SessionRecord s) async {
    activeSession = s;
    await loadHistoryForSession();
    showSessionSelector = false;
    notifyListeners();
  }

  // ─── Inline data loaders ─────────────────────────────────────────────────

  /// Pre‐fetch the list of subject names under `/users/{staff}/subjects`
  Future<void> loadAvailableSubjects(String staffNumber) async {
    final snap = await _db
        .collection('users')
        .doc(staffNumber)
        .collection('subjects')
        .get();
    availableSubjects = snap.docs.map((d) => d.id).toList();
    notifyListeners();
  }

  /// Given a selected subject, load its `sections` array
  Future<void> loadSubjectSections(String staffNumber, String subject) async {
    final doc = await _db
        .collection('users')
        .doc(staffNumber)
        .collection('subjects')
        .doc(subject)
        .get();
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final raw  = data['sections'] as List<dynamic>? ?? [];
    availableSections = raw.map((e) => e.toString()).toList();
    createSections.clear();
    notifyListeners();
  }

  // ─── Create / merge a session document ──────────────────────────────────

  Future<void> createSession(BuildContext context) async {
    if (!formKey.currentState!.validate()) return;
    if (createSections.isEmpty || startTime == null || endTime == null) return;

    final startMin = startTime!.hour * 60 + startTime!.minute;
    final endMin   = endTime!.hour * 60 + endTime!.minute;
    if (endMin <= startMin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final dateStr = DateFormat('yyyyMMdd').format(selectedDate);
    final docId   = '${dateStr}_${createSubject!}_$attendanceType';
    final ref     = _db.collection('attendanceSessions').doc(docId);

    final payload = <String, dynamic>{
      'date':           Timestamp.fromDate(selectedDate),
      'subject':        createSubject,
      'lecturer':       '', // you can fill if you like
      'attendanceType': attendanceType,
      'start':          startTime!.format(context),
      'end':            endTime!.format(context),
      'durationHours':  (endMin - startMin) / 60,
      'sections':       createSections,
    };

    final snap = await ref.get();
    if (snap.exists) {
      // merge any newly chosen sections
      await ref.update({
        'sections': FieldValue.arrayUnion(createSections),
      });
    } else {
      await ref.set(payload);
    }

    await fetchSessions();
    await loadHistoryForSession();
    toggleCreateForm();
  }


  /// ─── NFC scan & attendance logic ────────────────────────────────────────
// Add this import at the top of your file (once)

  String _decryptMatric(String payload) {
    final parts = payload.split(':');
    if (parts.length != 2) throw FormatException('Invalid encrypted payload');
    final iv        = enc.IV.fromBase64(parts[0]);
    final encrypted = enc.Encrypted.fromBase64(parts[1]);
    final key       = enc.Key.fromUtf8('V4Nz8xR2pQ7bJkL1sH9mC6yT3fD5gE0Z');
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt(encrypted, iv: iv);
  }

  Future<void> scanCard() async {
    if (activeSession == null) {
      statusMessage = '⚠️ Please select or create a session first.';
      notifyListeners();
      return;
    }

    isScanning    = true;
    statusMessage = '🔄 Scanning NFC…';
    notifyListeners();

    // 1️⃣ Poll the tag
    NFCTag tag;
    try {
      tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 10),
        iosAlertMessage: 'Hold card near device',
      );
    } catch (e) {
      statusMessage = '⚠️ NFC poll error: $e';
      isScanning    = false;
      notifyListeners();
      return;
    }

    // 2️⃣ Read raw payload (encrypted or tag.id)
    String raw = '';
    try {
      if (tag.ndefAvailable == true) {
        final recs = await FlutterNfcKit.readNDEFRecords();
        if (recs.isNotEmpty && recs.first is ndef.TextRecord) {
          raw = (recs.first as ndef.TextRecord).text ?? '';
        }
      }
      if (raw.isEmpty) raw = tag.id;
      await FlutterNfcKit.finish(iosAlertMessage: '✅ Read OK');
    } catch (e) {
      statusMessage = '⚠️ NFC read error: $e';
      isScanning    = false;
      notifyListeners();
      return;
    }

    // 3️⃣ Decrypt if needed
    String matric;
    try {
      matric = _decryptMatric(raw);
    } catch (_) {
      matric = raw;
    }

    // 4️⃣ Lookup user by matricNo
    final usersSnap = await _db
        .collection('users')
        .where('matricNo', isEqualTo: matric)
        .limit(1)
        .get();
    if (usersSnap.docs.isEmpty) {
      statusMessage = '❌ Unknown Matric: $matric';
      isScanning    = false;
      notifyListeners();
      return;
    }
    final userDoc = usersSnap.docs.first;
    final data    = userDoc.data();
    final name    = data['name']     as String? ?? 'Unknown';
    final photo   = data['photoUrl'] as String?;
    final timeStr = DateFormat.Hm().format(DateTime.now());

    final sessionRef = _db
        .collection('attendanceSessions')
        .doc(activeSession!.id);

    // ─── Prevent duplicate ──────────────────────────────────────────────
    final attendeeRef  = sessionRef.collection('attendees').doc(userDoc.id);
    final attendeeSnap = await attendeeRef.get();
    if (attendeeSnap.exists) {
      final recordedTime = attendeeSnap.data()?['time'] as String? ?? timeStr;
      statusMessage = '✅ $name already recorded at $recordedTime';
      isScanning    = false;
      notifyListeners();
      return;
    }

    // 5️⃣ Mark attendance
    try {
      await attendeeRef.set({
        'timestamp': FieldValue.serverTimestamp(),
        'time':      timeStr,
      });
    } catch (e) {
      statusMessage = '⚠️ Save failed: $e';
      isScanning    = false;
      notifyListeners();
      return;
    }

    // 6️⃣ Persist scan history (optional)
    try {
      await sessionRef.collection('scanHistory').add({
        'name':      name,
        'ic':        matric,
        'photoUrl':  photo,
        'time':      timeStr,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // non‐critical if history logging fails
    }

    // 7️⃣ Refresh UI
    await loadHistoryForSession();
    statusMessage = '✅ $name recorded at $timeStr';
    isScanning    = false;
    notifyListeners();
  }
}
