// =============================================================================
// ShiftEase — Settings screen (RC plan §H).
//
// Sections the release-candidate plan requires:
//   General        — app version + schema version (read-only facts).
//   Notifications  — permission status (§E3 honest reporting: enabled /
//                    denied / unknown) + reminder lead time note.
//   Data           — Backup (full-data JSON, §F), Restore (validate →
//                    preview → confirm, §F2), ICS export note (ICS is NOT a
//                    backup, §F3), Delete all data (double confirm).
//   Privacy &      — encryption status via the §G honesty probe (the plain
//   Security         build reports NOT encrypted — never a fake "secure").
//   About          — version, privacy policy, terms, support (offline text).
//
// No server, no cloud, no settings service: everything here reads the live
// ScheduleService and local files only.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:path_provider/path_provider.dart';

import 'package:shiftease/core/db/db.dart' show schemaVersion;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/common/write_guard.dart';
import 'package:shiftease/features/notifications/shift_reminder.dart';

class SettingsScreen extends StatefulWidget {
  final ScheduleService service;
  final ShiftReminderScheduler reminders;

  /// Directory backup/restore files live in. Tests inject a sandbox temp dir
  /// (the widget-test binding never touches path_provider); production leaves
  /// this null and the screen resolves the persistent app support directory
  /// itself (P7.1 H1 — never the purgeable temp/cache directory).
  final Directory? backupDir;

  /// Injectable resolver used when [backupDir] is null (P7.1 H1 test seam).
  /// Production uses [getApplicationSupportDirectory]; tests substitute a
  /// persistent-looking directory or a thrower to verify the honest refusal.
  final Future<Directory> Function()? backupDirResolver;

  const SettingsScreen({
    super.key,
    required this.service,
    required this.reminders,
    this.backupDir,
    this.backupDirResolver,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// P7.1 (H1, result18 code review): production backups must never land in
  /// `Directory.systemTemp` — on Android that is the app CACHE directory,
  /// which the OS may purge at any time, and a backup is a data-safety
  /// feature. When the caller injects no directory (production wiring), the
  /// screen resolves `getApplicationSupportDirectory()` — the app-private,
  /// persistent location the ICS saver already uses. Tests keep injecting a
  /// sandbox temp dir via [SettingsScreen.backupDir].
  Directory? _resolvedDir;

  /// Honest error state: if path_provider fails there is NO silent
  /// systemTemp fallback — backup/restore refuse and say why.
  String? _dirError;

  @override
  void initState() {
    super.initState();
    if (widget.backupDir == null) _resolveDir();
  }

  Future<void> _resolveDir() async {
    try {
      final resolver = widget.backupDirResolver ??
          getApplicationSupportDirectory; // P7.1 H1: persistent, not cache
      final dir = await resolver();
      // Sync create: an `await dir.create(...)` here is a real dart:io
      // future that a widget-test fake-async zone never pumps (same reason
      // the backup write below uses the Sync API).
      dir.createSync(recursive: true);
      if (!mounted) return;
      setState(() => _resolvedDir = dir);
    } catch (e) {
      if (!mounted) return;
      setState(() => _dirError =
          'Storage location unavailable — backup/restore disabled: $e');
    }
  }

  /// The directory backup/restore operate on. Throws when no persistent
  /// location is available — callers translate that into an honest error.
  Directory get _dir {
    final injected = widget.backupDir;
    if (injected != null) return injected;
    final resolved = _resolvedDir;
    if (resolved != null) return resolved;
    throw StateError(_dirError ?? 'Storage location is still being resolved.');
  }

  Future<void> _backup() async {
    final Directory dir;
    try {
      dir = _dir;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    final doc = widget.service.createBackup();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/shiftease-backup-$stamp.json');
    // Sync write: dart:io async completes on the real event loop, which a
    // widget-test fake-async zone never pumps — the sync API blocks the
    // caller instead and works everywhere (same reason tests use Sync IO).
    file.writeAsStringSync(jsonEncode(doc), flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backup saved to ${file.path}')),
    );
  }

  Future<void> _restore() async {
    final List<File> files;
    try {
      final dir = _dir;
      files = dir
          .listSync()
          .whereType<File>()
          // RC review L3 — only the app's own backups (the backup writer uses
          // this exact prefix). A foreign .json in the same directory would
          // otherwise surface the raw "Restore failed: BackupException: …"
          // line instead of the "No backup file found" message.
          .where((f) =>
              f.path.split(Platform.pathSeparator).last
                  .startsWith('shiftease-backup-') &&
              f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No backup file found in the app directory.')));
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a backup file'),
        children: [
          for (final f in files.take(10))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, f.path),
              child: Text(f.path.split(Platform.pathSeparator).last),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;

    // F2 flow: validate → PREVIEW counts → explicit confirm → restore.
    try {
      final counts = widget.service.previewBackup(
          File(picked).readAsStringSync());
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: Text(
            'This REPLACES all current data with the backup:\n\n'
            '${counts.entries.map((e) => '${e.key}: ${e.value}').join('\n')}\n\n'
            'A failure mid-restore rolls back — the current data stays intact.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Restore')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final error = await runWriteAsync(
          () async => widget.service
              .restoreBackupFrom(File(picked).readAsStringSync()));
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Restore complete.')));
      }
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Not a valid ShiftEase backup (bad JSON).')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }

  Future<void> _deleteAll() async {
    // Double confirm — this is the one destructive action in the app.
    final first = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete ALL data?'),
        content: const Text(
            'Every job, schedule, override, pay rule and import will be '
            'permanently deleted from this device. Make a backup first — '
            'there is no undo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue')),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you absolutely sure?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete everything')),
        ],
      ),
    );
    if (second != true || !mounted) return;
    final error = runWrite(widget.service.deleteAllData);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error ?? 'All data deleted.')));
  }

  Future<void> _showTextDialog(String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final encryptionReason = widget.service.encryptionStatusReason();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('General'),
          ListTile(
            title: const Text('Schema version'),
            subtitle: const Text('Local database layout version'),
            trailing: Text('v$schemaVersion'),
          ),
          ListTile(
            title: const Text('Timezone'),
            subtitle: const Text(
                'Shifts resolve in each job\u2019s own IANA timezone — '
                'no global override'),
          ),

          const _Header('Notifications'),
          FutureBuilder<bool?>(
            future: widget.reminders.permissionStatus(),
            builder: (context, snap) => ListTile(
              title: const Text('Permission status'),
              subtitle: const Text(
                  'Reminder is scheduled 60 minutes before each shift starts'),
              trailing: Text(
                snap.connectionState != ConnectionState.done
                    ? '…'
                    : switch (snap.data) {
                        true => 'Enabled',
                        false => 'Denied',
                        null => 'Unknown',
                      },
              ),
            ),
          ),

          const _Header('Data'),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('Backup'),
            subtitle: const Text('Full-data JSON file (schema + checksum)'),
            onTap: () async {
              final error = await runWriteAsync(_backup);
              if (error != null && mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(error)));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore'),
            subtitle: const Text('Validate → preview → confirm → restore'),
            onTap: _restore,
          ),
          const ListTile(
            leading: Icon(Icons.event),
            title: Text('ICS export'),
            subtitle: Text('Per job, from the job screen — calendar sharing, '
                'NOT a backup'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever),
            title: const Text('Delete all data'),
            subtitle: const Text('Permanent — confirmed twice'),
            onTap: _deleteAll,
          ),

          const _Header('Privacy & Security'),
          ListTile(
            title: const Text('Encryption status'),
            subtitle: Text(encryptionReason ?? 'Encrypted (key verified).'),
            trailing: Icon(
              encryptionReason == null ? Icons.lock : Icons.lock_open,
              color: encryptionReason == null ? Colors.green : Colors.orange,
            ),
          ),
          ListTile(
            title: const Text('Data collection'),
            subtitle: const Text(
                'None. ShiftEase is offline-only: everything stays on this '
                'device, nothing is sent anywhere.'),
          ),

          const _Header('About'),
          const ListTile(
            title: Text('ShiftEase'),
            subtitle: Text('Offline shift calendar — release candidate'),
          ),
          ListTile(
            title: const Text('Privacy Policy'),
            onTap: () => _showTextDialog(
              'Privacy Policy',
              'ShiftEase collects no data. The app has no analytics, no '
              'crash reporting, no advertising identifiers and no network '
              'permission. All data (jobs, schedules, pay rules, imports) '
              'lives exclusively in the local database on this device. '
              'Backups are files you create and keep yourself.',
            ),
          ),
          ListTile(
            title: const Text('Terms'),
            onTap: () => _showTextDialog(
              'Terms',
              'ShiftEase is provided as-is for personal schedule and pay '
              'estimation. Income numbers are ESTIMATES computed from the '
              'rules you enter — they are not payroll advice. Verify '
              'critical figures against your employer\u2019s records.',
            ),
          ),
          ListTile(
            title: const Text('Support'),
            onTap: () => _showTextDialog(
              'Support',
              'Offline build — no remote support channel is wired yet. '
              'For data safety: create a Backup before any restore or '
              'delete operation.',
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
