import 'package:nfc_attendance/session_record.dart';

/// Scan history model
class ScanRecord {
  final String name;
  final String ic;
  final String time;
  final String? photoUrl;
  final SessionRecord session;
  final DateTime timestamp;

  ScanRecord({
    required this.name,
    required this.ic,
    this.photoUrl,
    required this.session,
    required this.time,
    required this.timestamp,
  });
}
