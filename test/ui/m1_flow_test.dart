// =============================================================================
// M1 UI flow tests (widget level). These drive the REAL widgets against a
// REAL :memory: SQLite DB via ScheduleService — no fake repositories, no fake
// engine. Any failure here means the UI does not actually persist what it
// shows (the exact class of bug this gate exists to catch).
//
//   1. DoD: create job → create template → build pattern → view week →
//      edit one shift (UPDATE override) → calendar reflects the edit while
//      the pattern object is untouched (INVARIANT-001) → exactly one override
//      row in the append-only log.
//   2. CREATE on an OFF day through the UI (+ column) — the created shift
//      appears on that day and the log gains exactly one CREATE row
//      (schema v2 convention is exercised by the UI path).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:shiftease/core/db/db.dart';
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/time/time_engine.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/jobs/jobs_screen.dart';

const _tz = 'America/New_York';

(String, Database, ScheduleService) makeHarness() {
  final db = openInMemory();
  final patterns = PatternRepository(db);
  final service = ScheduleService(
    patterns: patterns,
    schedule: ScheduleRepository(db, patterns),
    db: db,
  );
  return ('job', db, service);
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _addDays(String iso, int days) {
  final d = DateTime.parse(iso).add(Duration(days: days));
  return _iso(d);
}

int _overrideCount(Database db) =>
    db.select('SELECT COUNT(*) AS c FROM overrides').first['c'] as int;

void main() {
  setUpAll(initializeTimezoneDatabase);

  Future<void> pumpApp(WidgetTester tester, ScheduleService service) async {
    await tester.pumpWidget(MaterialApp(home: JobsScreen(service: service)));
    await tester.pumpAndSettle();
  }

  group('DoD — full UI flow (job → template → pattern → calendar → edit)', () {
    testWidgets('job created through UI renders a pattern; an UPDATE override '
        'sticks and never mutates the pattern', (tester) async {
      final (_, db, service) = makeHarness();

      await pumpApp(tester, service);
      expect(find.text('No jobs yet.'), findsOneWidget);

      // --- create the job through the UI dialog -----------------------------
      await tester.tap(find.text('New job'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Hospital');
      await tester.enterText(
          find.byType(TextField).at(1), _tz); // default is fine, set anyway
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Hospital'), findsOneWidget);

      // --- open the job, add a template through the UI dialog ---------------
      await tester.tap(find.text('Hospital'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).at(0),
          'Day shift');
      await tester.enterText(
          find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).at(1),
          'D');
      await tester.enterText(
          find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).at(2),
          '07:00');
      await tester.enterText(
          find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).at(3),
          '19:00');
      await tester.enterText(
          find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).at(4),
          '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Day shift'), findsOneWidget);

      // --- build the pattern (default 4-on/4-off, today) --------------------
      await tester.tap(find.text('New pattern'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save pattern'));
      await tester.pumpAndSettle();

      // --- open the week calendar ------------------------------------------
      await tester.tap(find.text('View week'));
      await tester.pumpAndSettle();

      // Pattern effective today means at least today's shift renders in the
      // current week. Its card reads "07:00–19:00" (local wall clock).
      final jobId = service.jobs().first.id;
      final beforePatterns = service.patterns(jobId).map((p) => p.effectiveFrom).toList();
      final dayCards = find.text('07:00–19:00');
      final beforeCards = tester.widgetList(dayCards).length;
      expect(beforeCards, greaterThan(0),
          reason: 'calendar must render the projected shift card');

      // --- edit the first shift through the sheet (UPDATE override) --------
      await tester.tap(dayCards.first);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(BottomSheet), matching: find.byType(TextField)).at(0),
          '08:00');
      await tester.enterText(
          find.descendant(
              of: find.byType(BottomSheet), matching: find.byType(TextField)).at(1),
          '16:00');
      await tester.tap(find.text('Update shift'));
      await tester.pumpAndSettle();

      // Calendar now shows the edited shift; the original 07:00–19:00 cards
      // are exactly one fewer (nothing else changed).
      expect(find.text('08:00–16:00'), findsOneWidget);
      expect(find.text('07:00–19:00'), findsNWidgets(beforeCards - 1));

      // Exactly one override row in the append-only log.
      expect(_overrideCount(db), 1,
          reason: 'one UI edit must equal exactly one stored override');

      // The pattern was never mutated (INVARIANT-001): same version set, same
      // effective windows, and the engine still projects the original 07:00.
      expect(service.patterns(jobId).map((p) => p.effectiveFrom).toList(),
          beforePatterns);
      final unchanged = service
          .patterns(jobId)
          .first.sequence
          .whereType<String>()
          .toList();
      expect(unchanged.length, 4,
          reason: 'sequence still has its 4 work slots (no mutation)');
    });
  });

  group('CREATE an OFF-day shift through the UI', () {
    testWidgets('add on an empty day column writes one CREATE override and the '
        'shift appears on the calendar', (tester) async {
      final (_, db, service) = makeHarness();

      // Seed job/template/pattern anchored to THIS week's Monday so the whole
      // Mon..Sun window renders (4-on/4-off → Mon..Thu work, Fri..Sun OFF).
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - DateTime.monday));
      final from = _iso(monday);
      final jobId = service.createJob(name: 'Hospital', timezone: _tz);
      final tpl = ShiftTemplate(
        id: slugId('tpl', ['Day', '07:00', '19:00']),
        jobId: jobId,
        name: 'Day',
        code: 'D',
        color: '#1565C0',
        startTime: '07:00',
        endTime: '19:00',
      );
      service.saveTemplate(jobId: jobId, template: tpl);
      final tplId = service.templates(jobId).first.id;
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: slugId('pat', ['Rota', jobId, from]),
          jobId: jobId,
          name: 'Rota',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 8,
          sequence: [tplId, tplId, tplId, tplId, null, null, null, null],
          anchorDate: from,
          defaultTimezone: _tz,
          effectiveFrom: from,
        ),
        templates: service.templates(jobId),
      );

      await pumpApp(tester, service);
      await tester.tap(find.text('Hospital'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View week'));
      await tester.pumpAndSettle();

      // Friday (from + 4) is the first OFF day of this week → 4 cards only.
      expect(find.text('07:00–19:00'), findsNWidgets(4));
      final offIso = _addDays(from, 4);

      // Tap the OFF day's column header → Quick Add sheet (M1b).
      await tester.tap(find.byKey(ValueKey('day-$offIso')));
      await tester.pumpAndSettle();
      expect(find.text('Quick add on $offIso'), findsOneWidget);

      // 1-tap: a template tile creates immediately with the template's
      // default times (07:00–19:00) — no form.
      await tester.tap(find.text('Day (07:00–19:00)'));
      await tester.pumpAndSettle();

      // The created shift shows on Friday with the default wall clock; log
      // has exactly one CREATE row carrying patternId (v2 convention).
      expect(find.text('07:00–19:00'), findsNWidgets(5));
      expect(_overrideCount(db), 1);
      final row = db.select(
          'SELECT operation, patternId FROM overrides').first;
      expect(row['operation'], 'create');
      expect(row['patternId'], isNotNull,
          reason: 'official CREATE convention — patternId must be stored');

      // Domain-level check: the created occurrence survives a fresh render.
      final fresh = service.renderJob(
          jobId: jobId, rangeStart: offIso, rangeEnd: _addDays(offIso, 3));
      expect(
          fresh.occurrences.where((o) => o.shiftDate == offIso).length, 1);
    });
  });
}
