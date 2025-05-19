import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../controllers/attendance_controller.dart';
import '../widgets/inline_create_form.dart';
import '../ui/background.dart';
import '../ui/gradient_button.dart';
import '../session_record.dart';
import '../auth_provider.dart';
import 'inline_create_form.dart';

class ReadCardPage extends StatelessWidget {
  const ReadCardPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AttendanceController>(
      create: (_) {
        final ctrl = AttendanceController();
        ctrl.init();
        return ctrl;
      },
      child: Consumer<AttendanceController>(
        builder: (context, ctrl, _) {
          final staff = Provider.of<AuthProvider>(context, listen: false)
              .userProfile!
              .staffNumber!;

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
                  onPressed: () {
                    ctrl.fetchSessions();
                    ctrl.loadHistoryForSession();
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

                        // ─── Subject Filter ──────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Card(
                            color: Colors.white.withOpacity(.9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: DropdownButton<String>(
                                isExpanded: true,
                                underline: const SizedBox(),
                                value: ctrl.filterSubject ?? 'All Subjects',
                                items: <String>[
                                  'All Subjects',
                                  ...{for (var s in ctrl.sessions) s.subject}
                                ]
                                    .map((subj) =>
                                    DropdownMenuItem(value: subj, child: Text(subj)))
                                    .toList(),
                                onChanged: (v) {
                                  ctrl.setFilterSubject(v);
                                  ctrl.loadHistoryForSession();
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ─── Session Selector (only one at a time) ────────────────
                        if (!ctrl.showSessionSelector) ...[
                          if (ctrl.loadingSessions)
                            const Center(
                                child: CircularProgressIndicator(color: Colors.white))
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Card(
                                color: Colors.white.withOpacity(.9),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 4,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 4),
                                  child: DropdownButton<SessionRecord>(
                                    isExpanded: true,
                                    underline: const SizedBox(),
                                    hint: const Text('Select session',
                                        style: TextStyle(color: Colors.grey)),
                                    value: ctrl.activeSession,
                                    items: ctrl.sessions
                                        .where((s) =>
                                    ctrl.filterSubject == null ||
                                        ctrl.filterSubject == 'All Subjects' ||
                                        s.subject == ctrl.filterSubject)
                                        .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                          '${DateFormat.yMMMd().format(s.date)} · ${s.subject}'),
                                    ))
                                        .toList(),
                                    onChanged: (s) {
                                      if (s != null) ctrl.selectSession(s);
                                    },
                                  ),
                                ),
                              ),
                            ),
                        ] else ...[
                          // toggled “Existing-Session” view
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Card(
                              color: Colors.white.withOpacity(.9),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 4,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                child: DropdownButton<SessionRecord>(
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  hint: const Text('Select session',
                                      style: TextStyle(color: Colors.grey)),
                                  value: ctrl.activeSession,
                                  items: ctrl.sessions
                                      .where((s) =>
                                  ctrl.filterSubject == null ||
                                      ctrl.filterSubject == 'All Subjects' ||
                                      s.subject == ctrl.filterSubject)
                                      .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                        '${DateFormat.yMMMd().format(s.date)} · ${s.subject}'),
                                  ))
                                      .toList(),
                                  onChanged: (s) {
                                    if (s != null) ctrl.selectSession(s);
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // ─── Create vs Existing Buttons ──────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: LayoutBuilder(
                            builder: (ctx, bc) {
                              final narrow = bc.maxWidth < 360;
                              if (narrow) {
                                return Column(
                                  children: [
                                    GradientButton(
                                      label: 'Create New Session',
                                      icon: Icons.add_circle,
                                      gradient: LinearGradient(
                                        colors: ctrl.showCreateForm
                                            ? [Colors.grey, Colors.grey.shade600]
                                            : [const Color(0xFF29B6F6), const Color(0xFF0288D1)],
                                      ),
                                      onTap: () {
                                        ctrl.toggleCreateForm();
                                        if (ctrl.showCreateForm) {
                                          ctrl.loadAvailableSubjects(staff);
                                        }
                                      },
                                    ),
                                  ],
                                );
                              } else {
                                return Row(
                                  children: [
                                    Expanded(
                                      child: GradientButton(
                                        label: 'Select Existing Session',
                                        icon: Icons.view_list,
                                        gradient: LinearGradient(
                                          colors: ctrl.showSessionSelector
                                              ? [Colors.grey, Colors.grey.shade600]
                                              : [const Color(0xFF29B6F6), const Color(0xFF0288D1)],
                                        ),
                                        onTap: () => ctrl.toggleSessionSelector(),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: GradientButton(
                                        label: 'Create New Session',
                                        icon: Icons.add_circle,
                                        gradient: LinearGradient(
                                          colors: ctrl.showCreateForm
                                              ? [Colors.grey, Colors.grey.shade600]
                                              : [const Color(0xFF29B6F6), const Color(0xFF0288D1)],
                                        ),
                                        onTap: () {
                                          ctrl.toggleCreateForm();
                                          if (ctrl.showCreateForm) {
                                            ctrl.loadAvailableSubjects(staff);
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              }
                            },
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ─── Inline Create Form ───────────────
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: InlineCreateForm(),
                          crossFadeState: ctrl.showCreateForm
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 300),
                        ),

                        const SizedBox(height: 24),

                        // ─── Scan Button ───────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: GradientButton(
                            label: ctrl.isScanning ? 'Scanning…' : 'Scan Card',
                            icon: ctrl.isScanning ? Icons.hourglass_top : Icons.nfc,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF66BB6A), Color(0xFF388E3C)],
                            ),
                            onTap: (ctrl.activeSession != null && !ctrl.isScanning)
                                ? () => ctrl.scanCard()
                                : null,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ─── Status Message ───────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            ctrl.statusMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),

                        const SizedBox(height: 24),
                        Divider(color: Colors.white.withOpacity(.3), thickness: 1),
                        const SizedBox(height: 12),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'Recent Scans',
                            style: TextStyle(
                                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ─── Scan History ─────────────────────
                        ...ctrl.history.map((record) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Card(
                              color: Colors.black.withOpacity(.7),
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
                                  '${DateFormat.yMMMd().format(record.timestamp)} · ${record.time}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                trailing:
                                const Icon(Icons.check, color: Colors.greenAccent),
                              ),
                            ),
                          );
                        }),

                        const SizedBox(height: 24),
                        const Center(
                          child: Text('© Tech Ventura',
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
