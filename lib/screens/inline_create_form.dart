import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../controllers/attendance_controller.dart';
import '../auth_provider.dart';
import '../ui/gradient_button.dart';

class InlineCreateForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl  = Provider.of<AttendanceController>(context);
    final staff = Provider.of<AuthProvider>(context, listen: false)
        .userProfile!
        .staffNumber!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Card(
        color: Colors.white.withOpacity(.95),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: ctrl.formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'New Session Details',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Date picker
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: ctrl.selectedDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) {
                      ctrl.selectedDate = d;
                      ctrl.notifyListeners();
                    }
                  },
                  child: InputDecorator(
                    decoration: _inputDecoration('Date'),
                    child: Text(DateFormat.yMMMMd().format(ctrl.selectedDate)),
                  ),
                ),
                const SizedBox(height: 16),

                // Subject dropdown
                FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(staff)
                      .collection('subjects')
                      .get(),
                  builder: (ctx, snap) {
                    if (snap.hasError) {
                      return const Text(
                        'Error loading subjects',
                        style: TextStyle(color: Colors.redAccent),
                      );
                    }
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return const Text(
                        'No subjects assigned to you.',
                        style: TextStyle(color: Colors.redAccent),
                      );
                    }
                    final pickSubjects = docs.map((d) => d.id).toList();

                    return DropdownButtonFormField<String>(
                      decoration: _inputDecoration('Subject'),
                      value: ctrl.createSubject,
                      items: pickSubjects
                          .map((subj) => DropdownMenuItem(
                        value: subj,
                        child: Text(subj),
                      ))
                          .toList(),
                      onChanged: (v) {
                        ctrl.createSubject = v;
                        ctrl.loadSubjectSections(staff, v!);
                      },
                      validator: (v) => v == null ? 'Required' : null,
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Sections checkboxes
                if (ctrl.availableSections.isNotEmpty) ...[
                  const Text(
                    'Sections',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ...ctrl.availableSections.map((sec) {
                    final checked = ctrl.createSections.contains(sec);
                    return CheckboxListTile(
                      title: Text(sec),
                      value: checked,
                      onChanged: (on) {
                        if (on == true) {
                          ctrl.createSections.add(sec);
                        } else {
                          ctrl.createSections.remove(sec);
                        }
                        ctrl.notifyListeners();
                      },
                    );
                  }).toList(),
                  if (ctrl.createSections.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(left: 16, bottom: 8),
                      child: Text(
                        'Pick at least one section',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],

                // Attendance type
                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Attendance Type'),
                  value: ctrl.attendanceType,
                  items: ['Lecture', 'Laboratory', 'Program', 'Exam']
                      .map((type) => DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  ))
                      .toList(),
                  onChanged: (v) {
                    ctrl.attendanceType = v;
                    ctrl.notifyListeners();
                  },
                  validator: (v) => v == null ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Hour-only dropdowns
                Row(
                  children: [
                    Expanded(child: _HourDropdown(isStart: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _HourDropdown(isStart: false)),
                  ],
                ),
                const SizedBox(height: 20),

                // Save button
                GradientButton(
                  label: 'Save Session',
                  icon: Icons.save,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF66BB6A), Color(0xFF43A047)],
                  ),
                  onTap: () => ctrl.createSession(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) =>
      InputDecoration(labelText: label, border: OutlineInputBorder());
}

class _HourDropdown extends StatelessWidget {
  final bool isStart;
  const _HourDropdown({required this.isStart});

  @override
  Widget build(BuildContext context) {
    final ctrl = Provider.of<AttendanceController>(context);
    final label = isStart ? 'Start Time' : 'End Time';
    final selectedHour = isStart
        ? ctrl.startTime?.hour
        : ctrl.endTime?.hour;

    // generate hours 0–23
    final hours = List<int>.generate(24, (i) => i);

    // filter so end > start, start < end
    final available = hours.where((h) {
      if (isStart) {
        final endH = ctrl.endTime?.hour;
        return endH == null || h < endH;
      } else {
        final startH = ctrl.startTime?.hour;
        return startH == null || h > startH;
      }
    }).toList();

    return DropdownButtonFormField<int>(
      decoration: InputDecoration(labelText: label, border: OutlineInputBorder()),
      value: (selectedHour != null && available.contains(selectedHour))
          ? selectedHour
          : null,
      items: available.map((h) {
        final text = '${h.toString().padLeft(2, '0')}:00';
        return DropdownMenuItem<int>(
          value: h,
          child: Text(text),
        );
      }).toList(),
      onChanged: (h) {
        if (h == null) return;
        final tod = TimeOfDay(hour: h, minute: 0);
        if (isStart) {
          ctrl.startTime = tod;
          // clear end if it’s now invalid
          if (ctrl.endTime != null && ctrl.endTime!.hour <= h) {
            ctrl.endTime = null;
          }
        } else {
          ctrl.endTime = tod;
        }
        ctrl.notifyListeners();
      },
      validator: (v) => v == null ? 'Required' : null,
    );
  }
}
