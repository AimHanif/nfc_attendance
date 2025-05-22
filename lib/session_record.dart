// lib/models/session_record.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single attendance session, pulling its first section
/// out of the Firestore `sections` array for display in the UI.
class SessionRecord {
  final String id;
  final DateTime date;
  final String subject;
  final String lecturer;
  final String section;
  final String attendanceType;
  final String start;         // e.g. "08:00"
  final String end;           // e.g. "10:00"
  final double durationHours; // e.g. 2.0

  SessionRecord({
    required this.id,
    required this.date,
    required this.subject,
    required this.lecturer,
    required this.section,
    required this.attendanceType,
    required this.start,
    required this.end,
    required this.durationHours,
  });

  /// Build a SessionRecord from a Firestore document.
  factory SessionRecord.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // ─── Extract the first section from the `sections` array ─────────────
    final rawSections = data['sections'] as List<dynamic>? ?? [];
    final section = rawSections.isNotEmpty
        ? rawSections.first.toString()
        : '–';

    // ─── Other fields (with safe defaults) ────────────────────────────────
    final attendanceType = data['attendanceType'] as String? ?? '–';
    final start          = data['start']         as String? ?? '00:00';
    final end            = data['end']           as String? ?? '00:00';

    // ─── Compute duration from stored or derived value ───────────────────
    double duration;
    if ((data['durationHours'] as num?) != null) {
      duration = (data['durationHours'] as num).toDouble();
    } else {
      int parseMin(String s) {
        final parts = s.split(':');
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
      final startMin = parseMin(start);
      final endMin   = parseMin(end);
      duration = ((endMin - startMin) / 60).clamp(0.0, double.infinity);
    }

    return SessionRecord(
      id:              doc.id,
      date:            (data['date'] as Timestamp).toDate(),
      subject:         data['subject']        as String? ?? '–',
      lecturer:        data['lecturer']       as String? ?? '–',
      section:         section,
      attendanceType:  attendanceType,
      start:           start,
      end:             end,
      durationHours:   duration,
    );
  }
}
