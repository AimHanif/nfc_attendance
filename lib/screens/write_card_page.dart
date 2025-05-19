// lib/screens/write_card_page.dart

import 'dart:async';
import 'dart:io';
import 'package:encrypt/encrypt.dart' as enc;
import 'dart:convert';  // for base64 decoding/encoding if you ever need it
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../ui/background.dart';

class WriteCardPage extends StatefulWidget {
  const WriteCardPage({Key? key}) : super(key: key);

  @override
  _WriteCardPageState createState() => _WriteCardPageState();
}

class _WriteCardPageState extends State<WriteCardPage>
    with TickerProviderStateMixin {
  // Form controllers
  final TextEditingController _matricController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedPhoto;

  bool _isWriting = false;
  String _statusMessage = '';
  _WriteRecord? _lastWrite;
  final List<_WriteRecord> _history = [];

  // Page animations
  late final AnimationController _mainController;
  late final Animation<double> _titleScale, _formFade, _buttonScale;
  late final Animation<Offset> _fieldsSlide;
  late final AnimationController _overlayController;
  late final Animation<double> _overlayFade;
  late final Animation<Offset> _overlaySlide;

  @override
  void initState() {
    super.initState();

    // Main animations
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();
    _titleScale = CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.25, curve: Curves.elasticOut));
    _formFade = CurvedAnimation(
        parent: _mainController, curve: const Interval(0.25, 0.5));
    _fieldsSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.3, 0.6, curve: Curves.easeOut),
    ));
    _buttonScale = CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.6, 1.0, curve: Curves.elasticOut));

    // Overlay animations
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
    _matricController.dispose();
    super.dispose();
  }

  void _log(String msg) => debugPrint('[WriteCardPage] $msg');

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

  Future<void> _writeToNfcCard() async {
    final matric = _matricController.text.trim();
    if (matric.isEmpty) {
      setState(() => _statusMessage = '⚠️ Please enter a matric number.');
      return;
    }

    setState(() {
      _isWriting = true;
      _statusMessage = '🔄 Preparing NFC card…';
      _lastWrite = null;
    });

    // 1) Lookup user by matricNo
    _log('Looking up user for matricNo: $matric');
    QuerySnapshot<Map<String, dynamic>> query;
    try {
      query = await FirebaseFirestore.instance
          .collection('users')
          .where('matricNo', isEqualTo: matric)
          .limit(1)
          .get();
    } catch (e) {
      setState(() {
        _statusMessage = '⚠️ Firestore lookup failed: $e';
        _isWriting = false;
      });
      return;
    }
    if (query.docs.isEmpty) {
      setState(() {
        _statusMessage = '⚠️ No user found for $matric';
        _isWriting = false;
      });
      return;
    }
    final userDoc = query.docs.first;
    final userId = userDoc.id;
    final userName = userDoc.data()['name'] as String? ?? matric;
    _log('Found user: $userName (ID=$userId)');

    // 2) NFC poll
    setState(() => _statusMessage = '🔄 Scanning NFC…');
    NFCTag tag;
    try {
      tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 10),
        iosAlertMessage: 'Please tap your NFC card',
      );
    } on PlatformException catch (e) {
      final msg = e.code == '500'
          ? '⚠️ NFC error: check your device/card'
          : '⚠️ NFC error: ${e.message ?? e.code}';
      setState(() {
        _statusMessage = msg;
        _isWriting = false;
      });
      return;
    } catch (e) {
      setState(() {
        _statusMessage = '⚠️ NFC error: $e';
        _isWriting = false;
      });
      return;
    }
    if (tag.ndefWritable != true) {
      setState(() {
        _statusMessage = '⚠️ Card is not writable.';
      });
      await FlutterNfcKit.finish(iosErrorMessage: 'Write failed');
      setState(() => _isWriting = false);
      return;
    }

    // 3) Encrypt the matric number
    setState(() => _statusMessage = '🔄 Encrypting data…');
    final encryptedMatric = _encryptMatric(matric);

    // 4) Write encrypted data to NFC
    setState(() => _statusMessage = '🔄 Writing encrypted data to card…');
    try {
      final record = ndef.TextRecord(
        text: encryptedMatric,
        language: 'en',
      );
      await FlutterNfcKit.writeNDEFRecords([record]);
      await FlutterNfcKit.finish(iosAlertMessage: '✅ Write successful');
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

    // 6) Update Firestore user document
    setState(() => _statusMessage = '🔄 Updating Firestore…');
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        if (photoUrl != null) 'photoUrl': photoUrl,
      });
    } catch (e) {
      _log('Firestore update failed: $e');
    }

    // 7) Record success in history and show overlay
    final now = DateTime.now();
    final fmt = DateFormat('yyyy-MM-dd HH:mm').format(now);
    final rec = _WriteRecord(
      name: userName,
      matric: matric,
      photoUrl: photoUrl,
      timestamp: now,
    );

    setState(() {
      _lastWrite = rec;
      _history.insert(0, rec);
      if (_history.length > 10) _history.removeLast();
      _statusMessage = '✅ Wrote for $userName at $fmt';
      _isWriting = false;
      _matricController.clear();
      _pickedPhoto = null;
    });

    _overlayController.forward(from: 0.0);
  }

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
            onPressed: () => Navigator.pop(context)),
        title: const Text('Register Student'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const AnimatedWebBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
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
                              offset: Offset(2, 2))
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  FadeTransition(
                    opacity: _formFade,
                    child: SlideTransition(
                      position: _fieldsSlide,
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _isWriting ? null : _pickPhoto,
                            child: CircleAvatar(
                              radius: 48,
                              backgroundColor: Colors.white24,
                              backgroundImage: _pickedPhoto != null
                                  ? FileImage(File(_pickedPhoto!.path))
                                  : null,
                              child: _pickedPhoto == null
                                  ? const Icon(Icons.camera_alt,
                                  color: Colors.white70, size: 36)
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 24),

                          TextField(
                            controller: _matricController,
                            enabled: !_isWriting,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Student Matric No',
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
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),

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
                          style: const TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 48, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
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
                  Divider(color: Colors.white24, thickness: 1),
                  const SizedBox(height: 16),
                  const Text('Recent Write History',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),

                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _history.length,
                    itemBuilder: (_, i) {
                      final rec = _history[i];
                      return Dismissible(
                        key: ValueKey(rec.timestamp),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => setState(() => _history.removeAt(i)),
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
                              style:
                              const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            '${rec.matric} · ${DateFormat('dd/MM/yyyy HH:mm').format(rec.timestamp)}',
                            style:
                            const TextStyle(color: Colors.white54),
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

          // Overlay
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

  Widget _buildOverlayCard(_WriteRecord rec) {
    return Align(
      alignment: Alignment.topCenter,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              Text('Matric: ${rec.matric}',
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

  String _encryptMatric(String plain) {
    final key = enc.Key.fromUtf8('V4Nz8xR2pQ7bJkL1sH9mC6yT3fD5gE0Z');
    final iv  = enc.IV.fromLength(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plain, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }


}

class _WriteRecord {
  final String name;
  final String matric;
  final String? photoUrl;
  final DateTime timestamp;

  _WriteRecord({
    required this.name,
    required this.matric,
    this.photoUrl,
    required this.timestamp,
  });
}
