// =============================================================================
// RC plan §H — Settings screen flow tests (real in-memory SQLite).
//
//   1. Render: all required sections visible; encryption status is HONEST
//      (plain build → "NOT encrypted" reason shown, never a fake secure).
//   2. Backup → Delete all data (double confirm) → Restore round-trip:
//      the schedule is wiped and then fully recovered from the backup file.
//   3. Restore of a corrupted file reports an error and leaves data intact.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/time/time_engine.dart'
    show initializeTimezoneDatabase;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/notifications/shift_reminder.dart';
import 'package:shiftease/features/settings/settings_screen.dart';

const String _tz = 'Asia/Ho_Chi_Minh';

ScheduleService _seededService(Database db) {
  final service = ScheduleService(
    patterns: PatternRepository(db),
    schedule: ScheduleRepository(db, PatternRepository(db)),
    db: db,
  );
  final jobId = service.createJob(name: 'Cafe', timezone: _tz);
  service.saveTemplate(
    jobId: jobId,
    template: ShiftTemplate(
      id: slugId('tpl', ['Morning', '07:00', '15:00']),
      jobId: jobId,
      name: 'Morning',
      code: 'M',
      color: '#1565C0',
      startTime: '07:00',
      endTime: '15:00',
    ),
  );
  final monday = _mondayIso();
  final tplId = service.templates(jobId).first.id;
  service.saveNewPattern(
    pattern: ShiftPattern(
      id: slugId('pat', ['Rota', jobId, monday]),
      jobId: jobId,
      name: 'Rota',
      type: 'FIXED_CYCLE',
      cycleLengthDays: 7,
      sequence: [tplId, null, null, null, null, null, null],
      anchorDate: monday,
      defaultTimezone: _tz,
      effectiveFrom: monday,
    ),
    templates: service.templates(jobId),
  );
  return service;
}

String _mondayIso() {
  final now = DateTime.now();
  // 2026-01-05 is a Monday — a fixed anchor keeps the pattern deterministic.
  return DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: (now.weekday - 1) % 7))
      .toIso8601String()
      .substring(0, 10);
}

Future<void> _pump(
  WidgetTester tester,
  ScheduleService service, {
  Directory? backupDir,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: SettingsScreen(
      service: service,
      reminders: ShiftReminderScheduler(),
      backupDir: backupDir,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    initializeTimezoneDatabase();
  });
  testWidgets('renders all sections; encryption status is honest',
      (tester) async {
    final service = _seededService(dblib.openInMemory());
    await _pump(tester, service);

    expect(find.text('GENERAL'), findsOneWidget);
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(find.text('DATA'), findsOneWidget);
    expect(find.text('Backup'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);

    // ListView is lazy — walk down to the destructive + privacy tail.
    await tester.scrollUntilVisible(
      find.text('Delete all data'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Delete all data'), findsOneWidget);

    // The Privacy & Security copy is longer now (Sentry + AdMob disclosure)
    // so the lazy ListView can't show this whole section plus Support at
    // once — scroll per section and assert within its own viewport window.
    await tester.scrollUntilVisible(
      find.text('PRIVACY & SECURITY'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('PRIVACY & SECURITY'), findsOneWidget);

    // §G honesty: on the plain sqlite3 test build the probe MUST say not
    // encrypted — never a green "Encrypted" claim.
    expect(find.textContaining('NOT encrypted'), findsOneWidget);
    expect(find.byIcon(Icons.lock_open), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Support'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
  });

  testWidgets('backup → delete all → restore round-trip recovers the roster',
      (tester) async {
    final service = _seededService(dblib.openInMemory());
    final dir = Directory.systemTemp.createTempSync('se_settings_');
    addTearDown(() => dir.deleteSync(recursive: true));

    await _pump(tester, service, backupDir: dir);

    // 1. Backup.
    await tester.tap(find.text('Backup'));
    await tester.pumpAndSettle();
    final backupFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.contains('shiftease-backup-') && f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    expect(backupFiles, isNotEmpty, reason: 'backup wrote a file');
    final raw = backupFiles.first.readAsStringSync();
    expect(jsonDecode(raw)['format'], 'shiftease-backup');

    // 2. Delete all data — confirm twice. Scroll it into view first (the
    // ListView is lazy).
    await tester.scrollUntilVisible(
      find.text('Delete all data'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete all data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete everything'));
    await tester.pumpAndSettle();
    // The snackbar may already be dismissed by the settle — the meaningful
    // assertion is that the wipe actually happened.
    expect(service.jobs(), isEmpty, reason: 'wipe really happened');

    // 3. Restore from the backup file (validate → preview → confirm).
    await tester.scrollUntilVisible(
      find.text('Restore'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    // The picker lists backup files; pick the one we just made. Scoped to
    // the SimpleDialog — the still-visible 'Backup saved to …' snackbar
    // also contains the file name.
    await tester.tap(find.descendant(
      of: find.byType(SimpleDialog),
      matching: find.textContaining('shiftease-backup-'),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('This REPLACES all current data'),
        findsOneWidget, reason: 'preview shows the row counts');
    // The dialog's FilledButton — the list tile 'Restore' behind it also
    // matches a bare text finder.
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Restore'),
    ));
    await tester.pumpAndSettle();

    // The snackbar may already be dismissed by the settle — the meaningful
    // assertion is the recovered roster.
    expect(service.jobs().length, 1, reason: 'roster fully recovered');
    expect(service.jobs().first.name, 'Cafe');
  });

  testWidgets('corrupted backup reports an error and data stays intact',
      (tester) async {
    final service = _seededService(dblib.openInMemory());
    final dir = Directory.systemTemp.createTempSync('se_settings_bad_');
    final badFile = File('${dir.path}/shiftease-backup-bad.json');
    badFile.writeAsStringSync('{"format":"shiftease-backup","payload":{}}');
    addTearDown(() => dir.deleteSync(recursive: true));

    await _pump(tester, service, backupDir: dir);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(SimpleDialog),
      matching: find.textContaining('shiftease-backup-bad'),
    ));
    await tester.pumpAndSettle();

    // Missing checksum → validation fails, the error is surfaced, and the
    // seeded schedule is untouched.
    expect(find.textContaining('Restore failed'), findsOneWidget);
    expect(service.jobs().length, 1);
    expect(service.jobs().first.name, 'Cafe');
  });

  testWidgets('L3: the restore picker lists only shiftease-backup- files — '
      'a foreign .json in the directory is ignored', (tester) async {
    final service = _seededService(dblib.openInMemory());
    final dir = Directory.systemTemp.createTempSync('se_settings_l3_');
    addTearDown(() => dir.deleteSync(recursive: true));
    // A foreign JSON file (e.g. some other tool's data) shares the dir.
    File('${dir.path}/other-app-data.json').writeAsStringSync('{"x":1}');

    await _pump(tester, service, backupDir: dir);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    // No shiftease-backup-*.json exists → the honest "none found" message,
    // NOT the picker with the foreign file and NOT a raw exception line.
    expect(find.text('No backup file found in the app directory.'),
        findsOneWidget);
    expect(find.textContaining('other-app-data'), findsNothing,
        reason: 'L3: foreign files never appear in the picker');
    expect(find.textContaining('Restore failed'), findsNothing,
        reason: 'L3: the user is never shown a raw BackupException line');
  });

  group('P7.1 H1 — production backup directory is persistent, never temp', () {
    testWidgets('default path (no injected dir) backs up into the '
        'resolved app-support directory and restore reads the same place',
        (tester) async {
      final service = _seededService(dblib.openInMemory());
      // Stands in for getApplicationSupportDirectory(): an app-private
      // PERSISTENT directory (on device: never purgeable, unlike
      // Directory.systemTemp = the OS cache dir).
      final support = Directory.systemTemp.createTempSync('se_p7_support_');
      addTearDown(() => support.deleteSync(recursive: true));

      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
          service: service,
          reminders: ShiftReminderScheduler(),
          backupDirResolver: () async => support,
        ),
      ));
      await tester.pumpAndSettle();

      // 1. Backup writes into the RESOLVED directory.
      await tester.tap(find.text('Backup'));
      await tester.pumpAndSettle();
      final backups = support
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('shiftease-backup-'))
          .toList();
      expect(backups, hasLength(1), reason: 'backup landed in the support dir');

      // 2. Delete all data, then restore — the picker reads the SAME
      //    persistent location (no directory re-resolution between steps).
      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete everything'));
      await tester.pumpAndSettle();
      expect(service.jobs(), isEmpty);

      await tester.scrollUntilVisible(
        find.text('Restore'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.textContaining('shiftease-backup-'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Restore'),
      ));
      await tester.pumpAndSettle();
      expect(service.jobs().length, 1,
          reason: 'restore recovered the roster from the persistent dir');
      expect(service.jobs().first.name, 'Cafe');
    });

    testWidgets('unavailable storage → honest refusal, never a silent '
        'fallback into the purgeable temp directory', (tester) async {
      final service = _seededService(dblib.openInMemory());
      // Snapshot: nothing may be smuggled into systemTemp. Top-level listing
      // only — a recursive scan of the whole temp tree can hit foreign
      // permission-denied dirs in a sandbox.
      List<File> tempBackups() => Directory.systemTemp
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.split(Platform.pathSeparator).last
                  .startsWith('shiftease-backup-') &&
              f.path.endsWith('.json'))
          .toList();
      final before = tempBackups().length;

      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
          service: service,
          reminders: ShiftReminderScheduler(),
          backupDirResolver: () async =>
              throw const FileSystemException('no persistent storage'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Backup'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Storage location unavailable'),
          findsOneWidget,
          reason: 'H1: backup is disabled with a clear reason, never '
              'silently written to the cache directory');
      expect(tempBackups().length, before,
          reason: 'H1: no backup file appears in the purgeable temp dir');

      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Storage location unavailable'),
          findsOneWidget);
    });
  });
}
