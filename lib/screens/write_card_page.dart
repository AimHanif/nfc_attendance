// lib/screens/write_card_page.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../ui/background.dart';

/// A page for registering students by writing their IC onto an NFC card,
/// uploading an optional photo, and selecting their class.
/// Features:
/// - Animated form entry with fade & slide transitions
/// - Smooth, bouncing write button with built-in progress indicator
/// - Live status overlay with animated result card
/// - Recent write history with dismissal support
/// - Debug logging for each step
class WriteCardPage extends StatefulWidget {
  const WriteCardPage({Key? key}) : super(key: key);

  @override
  _WriteCardPageState createState() => _WriteCardPageState();
}

class _WriteCardPageState extends State<WriteCardPage>
    with TickerProviderStateMixin {
  // --------------------------------------------------------------------------
  // FORM CONTROLLERS & STATE
  // --------------------------------------------------------------------------
  final TextEditingController _icController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final List<String> _classOptions = [
    'Form 1A',
    'Form 1B',
    'Form 2A',
    'Form 2B',
    'Form 3A',
    'Form 3B',
  ];
  String? _selectedClass;
  XFile? _pickedPhoto;

  bool _isWriting = false;
  String _statusMessage = '';
  _WriteRecord? _lastWrite;
  final List<_WriteRecord> _history = [];

  // --------------------------------------------------------------------------
  // ANIMATION CONTROLLERS
  // --------------------------------------------------------------------------
  late final AnimationController _mainController;
  late final Animation<double> _titleScale;
  late final Animation<double> _formFade;
  late final Animation<Offset> _fieldsSlide;
  late final Animation<double> _buttonScale;
  late final AnimationController _overlayController;
  late final Animation<double> _overlayFade;
  late final Animation<Offset> _overlaySlide;

  @override
  void initState() {
    super.initState();

    // Main page animations (2 seconds for smooth effect)
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();

    _titleScale = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.25, curve: Curves.elasticOut),
    );
    _formFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.25, 0.5, curve: Curves.easeIn),
    );
    _fieldsSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.3, 0.6, curve: Curves.easeOut),
    ));
    _buttonScale = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.6, 1.0, curve: Curves.elasticOut),
    );

    // Overlay animations for result card
    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _overlayFade = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeIn,
    );
    _overlaySlide = Tween<Offset>(
      begin: const Offset(0, -0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeOutBack,
    ));
  }

  @override
  void dispose() {
    _mainController.dispose();
    _overlayController.dispose();
    _icController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // DEBUG
  // --------------------------------------------------------------------------
  void _log(String msg) {
    debugPrint('[WriteCardPage] $msg');
  }

  // --------------------------------------------------------------------------
  // PHOTO PICKER
  // --------------------------------------------------------------------------
  Future<void> _pickPhoto() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() => _pickedPhoto = picked);
      }
    } catch (e) {
      setState(() => _statusMessage = '⚠️ Failed to pick photo: $e');
    }
  }

  // --------------------------------------------------------------------------
  // WRITE NFC & FIRESTORE
  // --------------------------------------------------------------------------
  Future<void> _writeToNfcCard() async {
    final ic = _icController.text.trim();
    final studentClass = _selectedClass;

    // Validate form
    if (ic.isEmpty || studentClass == null) {
      setState(() => _statusMessage = '⚠️ Please enter IC and select a class.');
      return;
    }

    setState(() {
      _isWriting = true;
      _statusMessage = '🔄 Preparing NFC card…';
      _lastWrite = null;
    });

    // 1) Lookup user in Firestore
    _log('Looking up user for IC: $ic');
    QuerySnapshot<Map<String, dynamic>> query;
    try {
      query = await FirebaseFirestore.instance
          .collection('users')
          .where('ic', isEqualTo: ic)
          .limit(1)
          .get();
    } catch (e) {
      setState(() {
        _statusMessage = '⚠️ Firestore connection failed: $e';
        _isWriting = false;
      });
      return;
    }
    if (query.docs.isEmpty) {
      setState(() {
        _statusMessage = '⚠️ No user found for IC $ic';
        _isWriting = false;
      });
      return;
    }

    final userDoc = query.docs.first;
    final userId = userDoc.id;
    final userName = userDoc.data()['name'] as String? ?? ic;
    _log('User found: $userName (ID=$userId)');

    // 2) Poll NFC card
    NFCTag tag;
    setState(() => _statusMessage = '🔄 Scanning NFC…');
    try {
      tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 10),
        iosAlertMessage: 'Please tap your NFC card',
      );
    } on PlatformException catch (e) {
      final friendly = e.code == '500'
          ? '⚠️ NFC error: check your device and card'
          : '⚠️ NFC error: ${e.message ?? e.code}';
      setState(() {
        _statusMessage = friendly;
        _isWriting = false;
      });
      return;
    } catch (e) {
      setState(() {
        _statusMessage = '⚠️ Unexpected NFC error: $e';
        _isWriting = false;
      });
      return;
    }

    // 3) Check writable
    if (tag.ndefWritable != true) {
      setState(() {
        _statusMessage = '⚠️ This card is not writable.';
      });
      await FlutterNfcKit.finish(iosErrorMessage: 'Write failed');
      setState(() => _isWriting = false);
      return;
    }

    // 4) Write record to NFC
    setState(() => _statusMessage = '🔄 Writing IC to card…');
    try {
      final record = ndef.TextRecord(text: ic, language: 'en');
      await FlutterNfcKit.writeNDEFRecords([record]);
      await FlutterNfcKit.finish(iosAlertMessage: '✅ NFC write successful');
    } catch (e) {
      setState(() {
        _statusMessage = '⚠️ NFC write failed: $e';
        _isWriting = false;
      });
      return;
    }

    // 5) Upload photo if selected
    String? photoUrl;
    if (_pickedPhoto != null) {
      setState(() => _statusMessage = '🔄 Uploading photo…');
      try {
        final ref = FirebaseStorage.instance.ref('student_photos/$userId.jpg');
        await ref.putFile(File(_pickedPhoto!.path));
        photoUrl = await ref.getDownloadURL();
        _log('Photo uploaded: $photoUrl');
      } catch (e) {
        _log('Photo upload failed: $e');
      }
    }

    // 6) Update Firestore user doc
    setState(() => _statusMessage = '🔄 Updating record…');
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        'class': studentClass,
        if (photoUrl != null) 'photoUrl': photoUrl,
      });
    } catch (e) {
      _log('Firestore update failed: $e');
    }

    // 7) Success
    final now = DateTime.now();
    final formatted = DateFormat('yyyy-MM-dd HH:mm').format(now);

    final record = _WriteRecord(
      name: userName,
      ic: ic,
      studentClass: studentClass,
      photoUrl: photoUrl,
      timestamp: now,
    );

    setState(() {
      _lastWrite = record;
      _history.insert(0, record);
      if (_history.length > 10) _history.removeLast();
      _statusMessage = '✅ Card written for $userName at $formatted';
      _isWriting = false;
      _icController.clear();
      _selectedClass = null;
      _pickedPhoto = null;
    });

    // Animate overlay
    _overlayController.forward(from: 0.0);
  }

  // --------------------------------------------------------------------------
  // BUILD
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Register Student'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const AnimatedWebBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Title
                  ScaleTransition(
                    scale: _titleScale,
                    child: const Text(
                      'Write NFC Card',
                      style: TextStyle(
                        fontSize: 32,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 8,
                            offset: Offset(2, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Form
                  FadeTransition(
                    opacity: _formFade,
                    child: SlideTransition(
                      position: _fieldsSlide,
                      child: Column(
                        children: [
                          // Photo picker
                          GestureDetector(
                            onTap: _isWriting ? null : _pickPhoto,
                            child: CircleAvatar(
                              radius: 48,
                              backgroundColor: Colors.white24,
                              backgroundImage: _pickedPhoto != null
                                  ? FileImage(File(_pickedPhoto!.path))
                                  : null,
                              child: _pickedPhoto == null
                                  ? const Icon(
                                Icons.camera_alt,
                                color: Colors.white70,
                                size: 36,
                              )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // IC field
                          TextField(
                            controller: _icController,
                            enabled: !_isWriting,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Student IC Number',
                              labelStyle:
                              const TextStyle(color: Colors.white70),
                              filled: true,
                              fillColor: Colors.white12,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Class dropdown
                          InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Select Class',
                              labelStyle:
                              const TextStyle(color: Colors.white70),
                              filled: true,
                              fillColor: Colors.white12,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedClass,
                                hint: const Text(
                                  'Please select',
                                  style: TextStyle(color: Colors.white54),
                                ),
                                isExpanded: true,
                                dropdownColor: Colors.black87,
                                style: const TextStyle(color: Colors.white),
                                iconEnabledColor: Colors.white,
                                items: _classOptions.map((c) {
                                  return DropdownMenuItem(
                                    value: c,
                                    child: Text(c),
                                  );
                                }).toList(),
                                onChanged: _isWriting
                                    ? null
                                    : (v) =>
                                    setState(() => _selectedClass = v),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),

                  // Write button
                  ScaleTransition(
                    scale: _buttonScale,
                    child: ElevatedButton.icon(
                      onPressed:
                      _isWriting ? null : () => _writeToNfcCard(),
                      icon: _isWriting
                          ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                          AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                          : const Icon(Icons.nfc, size: 24),
                      label: Text(
                        _isWriting ? 'Writing…' : 'Write to Card',
                        style: const TextStyle(fontSize: 18),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isWriting
                            ? Colors.grey
                            : null, // use gradient below
                        padding: const EdgeInsets.symmetric(
                            horizontal: 48, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ).copyWith(
                        backgroundColor: MaterialStateProperty.resolveWith(
                                (states) => null),
                        elevation: MaterialStateProperty.all(4),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Status message
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusMessage.startsWith('✅')
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Divider
                  Container(
                    height: 1,
                    color: Colors.white24,
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                  ),

                  const SizedBox(height: 16),

                  // History title
                  const Text(
                    'Recent Write History',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),

                  // History list
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _history.length,
                    itemBuilder: (_, i) {
                      final rec = _history[i];
                      return Dismissible(
                        key: ValueKey(rec.timestamp),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) {
                          setState(() => _history.removeAt(i));
                        },
                        background: Container(
                          color: Colors.redAccent,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete_forever,
                              color: Colors.white),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundImage: rec.photoUrl != null
                                ? NetworkImage(rec.photoUrl!)
                                : null,
                            backgroundColor: rec.photoUrl == null
                                ? Colors.grey.shade700
                                : null,
                            child: rec.photoUrl == null
                                ? const Icon(Icons.person,
                                color: Colors.white)
                                : null,
                          ),
                          title: Text(rec.name,
                              style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            DateFormat('dd/MM/yyyy HH:mm')
                                .format(rec.timestamp),
                            style: const TextStyle(color: Colors.white54),
                          ),
                          trailing: const Icon(Icons.check_circle,
                              color: Colors.greenAccent),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),
                  const Text('© Tech Ventura',
                      style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Overlay result card
          if (_lastWrite != null)
            Positioned.fill(
              child: FadeTransition(
                opacity: _overlayFade,
                child: SlideTransition(
                  position: _overlaySlide,
                  child: _buildOverlayCard(_lastWrite!),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // OVERLAY CARD
  // --------------------------------------------------------------------------
  Widget _buildOverlayCard(_WriteRecord rec) {
    return Align(
      alignment: Alignment.topCenter,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        elevation: 12,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Success!',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
              const SizedBox(height: 12),
              CircleAvatar(
                radius: 36,
                backgroundImage: rec.photoUrl != null
                    ? NetworkImage(rec.photoUrl!)
                    : null,
                backgroundColor:
                rec.photoUrl == null ? Colors.grey.shade300 : null,
                child: rec.photoUrl == null
                    ? const Icon(Icons.person, size: 36)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(rec.name, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 4),
              Text('IC: ${rec.ic}',
                  style: const TextStyle(color: Colors.grey)),
              Text('Class: ${rec.studentClass}',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  _overlayController.reverse();
                  setState(() => _lastWrite = null);
                },
                child: const Text('Close'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------
// MODEL FOR A WRITE RECORD
// ------------------------------------------------------------------------------
class _WriteRecord {
  final String name;
  final String ic;
  final String studentClass;
  final String? photoUrl;
  final DateTime timestamp;

  _WriteRecord({
    required this.name,
    required this.ic,
    required this.studentClass,
    this.photoUrl,
    required this.timestamp,
  });
}
