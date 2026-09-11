// =============================================================================
// M2 import-flow UI tests (widget level, real SQLite via ScheduleService).
//
//   1. DoD e2e: paste roster → parse → candidates + confidence →
//      Accept All High (HIGH) → 1 MEDIUM stays pending → Edit it → Commit →
//      roster appears on the WeekCalendar (plan7 D-M2-1 A: import is
//      authoritative for its dates) → restart the file DB → still correct;
//      session audit (committedIds + committedOffDates + review status).
//   2. Reject one row → commit only the survivors.
//   3. Atomic failure: one approved candidate in a DST gap → commit errors
//      loudly and writes ZERO rows (fail-atomic).
//   4. INVARIANT-004: parsing + "Accept All High" never commits — the roster
//      is not visible on the calendar until the explicit Commit press.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/db.dart';
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/time/time_engine.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/import/import_screen.dart';
import 'package:shiftease/features/calendar/week_calendar_screen.dart';

const _tz = 'America/New_York';
const _dayTplId = 'tpl-day-0700-1900';

// The roster below spans Mon 2026-08-31 .. Sun 2026-09-06 (one calendar week).
const _roster = '2026-09-01 Day 07:00-19:00\n'
    '2026-09-02 Day 07:00-19:00\n'
    '2026-09-03 OFF\n'
    '2026-09-04 Day 07:00-19:00\n'
    '2026-09-05 07:00-19:00'; // no label → MEDIUM (exact time match, no type)

ScheduleService _service(Database db) => ScheduleService(
      patterns: PatternRepository(db),
      schedule: ScheduleRepository(db, PatternRepository(db)),
      db: db,
      imports: ImportRepository(db),
    );

/// Seeds a job with one Day template (07:00-19:00) and NO pattern — the job
/// an import targets (plan7 D-M2-1 A: imported roster becomes the schedule).
String _seedJob(ScheduleService service, {String tz = _tz}) {
  final jobId = service.jobs().isEmpty
      ? service.createJob(name: 'Hospital', timezone: tz)
      : service.jobs().first.id;
  service.saveTemplate(
    jobId: jobId,
    template: ShiftTemplate(
      id: _dayTplId,
      jobId: jobId,
      name: 'Day',
      code: 'D',
      color: '#1565C0',
      startTime: '07:00',
      endTime: '19:00',
    ),
  );
  return jobId;
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

/// The import review list is long (5+ candidate cards) — the default 800x600
/// test surface leaves the bottom (Commit button) off-screen and UNBUILT in
/// the lazy ListView, so finders fail. Give every test a tall viewport.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// P7.2: on this SQLCipher-linked build, on-disk test databases open KEYED
/// (same path production uses) — these restart tests now prove persistence
/// on an ENCRYPTED store.
const String kTestDbKey = 'shiftease-test-key';

void main() {
  setUpAll(initializeTimezoneDatabase);

  Future<String> _parseAndReview(WidgetTester tester, ScheduleService service,
      String jobId, String roster) async {
    await _pump(tester, ImportScreen(service: service, jobId: jobId));
    await tester.enterText(find.byType(TextField).first, roster);
    await tester.tap(find.text('Parse & review'));
    await tester.pumpAndSettle();
    return roster;
  }

  group('M2 — DoD import e2e (parse → review → commit → calendar → restart)',
      () {
    testWidgets('edit the MEDIUM row, commit, roster on calendar, survives '
        'restart, session audit intact', (tester) async {
      _useTallViewport(tester);
      // NOTE: sync IO only — real async file IO deadlocks under
      // testWidgets' FakeAsync zone (sqlite itself is sync and fine).
      final dir = Directory.systemTemp.createTempSync('shiftease_m2_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dbPath = '${dir.path}/m2.db';

      final db = openDatabase(opener: defaultOpener, path: dbPath, key: kTestDbKey);
      final service = _service(db);
      final jobId = _seedJob(service);
      await _parseAndReview(tester, service, jobId, _roster);

      // EXTRACTED, nothing auto-approved/committed (INVARIANT-004).
      expect(find.textContaining('State: EXTRACTED'), findsOneWidget);
      expect(find.textContaining('pending 5'), findsOneWidget);
      expect(find.textContaining('approve at least 1 row first'), findsOneWidget);
      expect(db.select('SELECT COUNT(*) c FROM occurrences').first['c'], 0,
          reason: 'parsing alone must never write schedule rows');

      // Accept All High → the 4 labelled/OFF rows (HIGH); the MEDIUM waits.
      await tester.tap(find.text('Accept All High'));
      await tester.pumpAndSettle();
      expect(find.textContaining('approved 4'), findsOneWidget);
      expect(find.textContaining('pending 1'), findsOneWidget);
      expect(db.select('SELECT COUNT(*) c FROM occurrences').first['c'], 0,
          reason: 'INVARIANT-004: accept-all-high is review, not commit');

      // Edit the pending MEDIUM (2026-09-05 → 2026-09-06, stays in the week).
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit cand-5'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('edit-date')),
          '2026-09-06');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('modified 1'), findsOneWidget);

      // Commit.
      await tester.tap(find.text('Commit 5 approved row(s)'));
      await tester.pumpAndSettle();
      expect(find.text('Committed 4 shift(s) + 1 OFF day(s).'), findsOneWidget);

      // Roster is now the schedule (D-M2-1 A). Domain check first.
      final rendered = service.renderJob(
          jobId: jobId, rangeStart: '2026-08-31', rangeEnd: '2026-09-06');
      expect(rendered.occurrences.length, 4);
      expect(rendered.occurrences.map((o) => o.shiftDate).toSet(),
          {'2026-09-01', '2026-09-02', '2026-09-04', '2026-09-06'});
      final edited = rendered.occurrences
          .firstWhere((o) => o.id == 'occ-cand-5');
      expect(service.localWallTime(edited)?.start, '07:00');
      // No occurrence row exists for the OFF day.
      expect(rendered.occurrences.any((o) => o.shiftDate == '2026-09-03'),
          isFalse,
          reason: 'OFF lines must be recorded as off-dates, never occurrences');

      // Calendar UI shows the committed week (anchored on 2026-09-01).
      await tester.tap(find.text('View calendar'));
      await tester.pumpAndSettle();
      expect(find.byType(WeekCalendarScreen), findsOneWidget);
      expect(find.text('07:00–19:00'), findsNWidgets(4));
      for (final id in ['occ-cand-1', 'occ-cand-2', 'occ-cand-4', 'occ-cand-5']) {
        expect(find.byKey(ValueKey('card-$id')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('card-occ-cand-3')), findsNothing,
          reason: 'the OFF day (Sep 03) must not render an occurrence card');

      // Restart: reopen the same FILE db → committed roster survives.
      db.close();
      final db2 = openDatabase(opener: defaultOpener, path: dbPath, key: kTestDbKey);
      final service2 = _service(db2);
      final again = service2.renderJob(
          jobId: jobId, rangeStart: '2026-08-31', rangeEnd: '2026-09-06');
      expect(again.occurrences.length, 4,
          reason: 'DoD: imported roster persists across restart');
      expect(again.occurrences.map((o) => o.shiftDate).toSet(),
          {'2026-09-01', '2026-09-02', '2026-09-04', '2026-09-06'});

      // Session audit: the committed session stores ids + OFF dates + status.
      final sessionId = db2
          .select(
              'SELECT id FROM import_sessions WHERE jobId = ? ORDER BY createdAt DESC, rowid DESC LIMIT 1',
              [jobId])
          .first['id'] as String;
      final saved = ImportRepository(db2).sessionById(sessionId);
      expect(saved, isNotNull);
      expect(saved!.committedOccurrenceIds, hasLength(4));
      expect(saved.committedOffDates, ['2026-09-03']);
      expect(saved.state.name, 'committed');
      expect(saved.candidates.where((c) => c.id == 'cand-5').first.reviewStatus
          .name, 'modified');
      expect(saved.candidates.where((c) => c.id == 'cand-3').first.reviewStatus
          .name, 'approved');
      db2.close();
    });
  });

  group('M2 — Reject one row, commit the survivors', () {
    testWidgets('rejected candidate never reaches the calendar', (tester) async {
      _useTallViewport(tester);
      final db = openInMemory();
      final service = _service(db);
      final jobId = _seedJob(service);
      await _parseAndReview(tester, service, jobId,
          '2026-09-01 Day 07:00-19:00\n'
          '2026-09-02 Day 07:00-19:00\n'
          '2026-09-03 Day 07:00-19:00');

      // Reject the middle row (2026-09-02) via its card's ✗ button.
      final card = find.ancestor(
          of: find.textContaining('2026-09-02'), matching: find.byType(Card));
      await tester.tap(
          find.descendant(of: card, matching: find.byTooltip('Reject')));
      await tester.pumpAndSettle();
      expect(find.textContaining('rejected 1'), findsOneWidget);

      await tester.tap(find.text('Accept All High'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commit 2 approved row(s)'));
      await tester.pumpAndSettle();

      final rendered = service.renderJob(
          jobId: jobId, rangeStart: '2026-08-31', rangeEnd: '2026-09-06');
      expect(rendered.occurrences.map((o) => o.shiftDate).toSet(),
          {'2026-09-01', '2026-09-03'},
          reason: 'the rejected 09-02 must not appear on the schedule');
      db.close();
    });
  });

  group('M2 — Atomic commit failure (DST gap)', () {
    testWidgets('one unresolvable candidate fails the whole commit loudly, '
        'zero rows written', (tester) async {
      _useTallViewport(tester);
      final db = openInMemory();
      final service = _service(db);
      // America/New_York springs forward 2026-03-08 02:00→03:00 — a shift
      // starting 02:30 that day does not exist locally.
      final jobId = _seedJob(service);
      await _parseAndReview(tester, service, jobId,
          '2026-03-07 Day 07:00-19:00\n'
          '2026-03-08 Day 02:30-10:30');

      expect(find.textContaining('State: EXTRACTED'), findsOneWidget);
      await tester.tap(find.text('Accept All High'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commit 2 approved row(s)'));
      await tester.pumpAndSettle();

      // Error surfaced, session reverted to an error state — not silent.
      expect(find.textContaining('COMMIT_UNRESOLVED'), findsOneWidget);
      expect(db.select('SELECT COUNT(*) c FROM occurrences').first['c'], 0,
          reason: 'commit is atomic: zero changes when any row fails');
      db.close();
    });
  });

  group('M2 — INVARIANT-004 via UI', () {
    testWidgets('nothing reaches the schedule before the explicit Commit tap',
        (tester) async {
      _useTallViewport(tester);
      final db = openInMemory();
      final service = _service(db);
      final jobId = _seedJob(service);
      await _parseAndReview(tester, service, jobId,
          '2026-09-01 Day 07:00-19:00\n'
          '2026-09-02 Day 07:00-19:00');

      // All HIGH after parse. Approve everything, but DO NOT press Commit.
      await tester.tap(find.text('Accept All High'));
      await tester.pumpAndSettle();
      expect(find.textContaining('State: REVIEWING'), findsOneWidget);
      expect(find.textContaining('approved 2'), findsOneWidget);

      // The calendar of that week is still empty, and the DB has zero rows.
      final rendered = service.renderJob(
          jobId: jobId, rangeStart: '2026-08-31', rangeEnd: '2026-09-06');
      expect(rendered.occurrences, isEmpty,
          reason: 'INVARIANT-004: reviewing is not committing');
      expect(db.select('SELECT COUNT(*) c FROM occurrences').first['c'], 0);
      db.close();
    });
  });

  group('M2 — Partial-commit warning (Gate A §A5)', () {
    testWidgets('commit with a pending row confirms first and only commits '
        'the approved subset after the user agrees', (tester) async {
      _useTallViewport(tester);
      final db = openInMemory();
      final service = _service(db);
      final jobId = _seedJob(service);
      await _parseAndReview(tester, service, jobId,
          '2026-09-01 Day 07:00-19:00\n'
          '2026-09-02 Day 07:00-19:00\n'
          '2026-09-03 Day 07:00-19:00');

      // Approve ONLY 09-01 — two rows stay pending. Partial-commit UX (A5):
      // the button says the pending rows will be skipped and the Commit tap
      // opens a confirm dialog instead of silently committing.
      final first = find.ancestor(
          of: find.textContaining('2026-09-01'), matching: find.byType(Card));
      await tester.tap(
          find.descendant(of: first, matching: find.byTooltip('Approve')));
      await tester.pumpAndSettle();
      expect(find.textContaining('approved 1'), findsOneWidget);
      expect(
          find.textContaining('Commit 1 approved row(s) — 2 pending shifts '
              'will NOT enter the schedule'),
          findsOneWidget,
          reason: 'A5: the commit label names the skipped pending rows');

      // Cancel the dialog → nothing is committed.
      await tester.tap(find.textContaining('Commit 1 approved row(s)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('are still pending review and will NOT'),
          findsOneWidget,
          reason: 'A5: confirm dialog names the consequence before commit');
      await tester.tap(find.text('Keep reviewing'));
      await tester.pumpAndSettle();
      expect(db.select('SELECT COUNT(*) c FROM occurrences').first['c'], 0,
          reason: 'cancelling the warning must not commit anything');

      // Confirm → only the 1 approved row lands on the schedule.
      await tester.tap(find.textContaining('Commit 1 approved row(s)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commit approved shifts'));
      await tester.pumpAndSettle();
      expect(find.text('Committed 1 shift(s) + 0 OFF day(s).'), findsOneWidget);
      final rendered = service.renderJob(
          jobId: jobId, rangeStart: '2026-08-31', rangeEnd: '2026-09-06');
      expect(rendered.occurrences.map((o) => o.shiftDate).toSet(),
          {'2026-09-01'},
          reason: 'partial commit: 09-02/09-03 stayed pending and were skipped');
      db.close();
    });
  });
}
