// =============================================================================
// M1b UI tests (widget level, real :memory: SQLite via ScheduleService).
//
//   1. Today screen: today's shift rendered + weekly hours computed from UTC
//      (INVARIANT-002) — 7 daily 12h shifts = 84.0h.
//   2. Month view: every in-month day shows its shift start; tapping a day
//      drills into the WeekCalendar for that day's week.
//   3. Quick Add "Custom time…" falls through to the full CREATE form and
//      writes exactly one CREATE override (patternId stored).
//   4. Roster re-version UI: "New version from date…" closes the old version
//      at X−1, opens the new one at X, keeps the anchor (D9) and leaves past
//      occurrences byte-identical (INVARIANT-001).
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
import 'package:shiftease/features/calendar/month_calendar_screen.dart';
import 'package:shiftease/features/calendar/week_calendar_screen.dart';
import 'package:shiftease/features/jobs/job_detail_screen.dart';
import 'package:shiftease/features/today/today_screen.dart';

const _tz = 'America/New_York';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _addDays(String iso, int days) {
  final d = DateTime.parse(iso).add(Duration(days: days));
  return _iso(d);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _mondayOf(DateTime d) =>
    _dateOnly(d).subtract(Duration(days: d.weekday - DateTime.monday));

/// Seeds job + Day template + pattern (default 4-on/4-off anchored [from]).
void _seed(ScheduleService service, String from, List<String?> sequence) {
  final jobId = service.jobs().isEmpty
      ? service.createJob(name: 'Hospital', timezone: _tz)
      : service.jobs().first.id;
  service.saveTemplate(
    jobId: jobId,
    template: ShiftTemplate(
      id: slugId('tpl', ['Day', '07:00', '19:00']),
      jobId: jobId,
      name: 'Day',
      code: 'D',
      color: '#1565C0',
      startTime: '07:00',
      endTime: '19:00',
    ),
  );
  final tplId = service.templates(jobId).first.id;
  final seq = sequence.isEmpty ? [tplId, tplId, tplId, tplId, null, null, null, null]
      : sequence;
  service.saveNewPattern(
    pattern: ShiftPattern(
      id: slugId('pat', ['Rota', jobId, from]),
      jobId: jobId,
      name: 'Rota',
      type: 'FIXED_CYCLE',
      cycleLengthDays: seq.length,
      sequence: seq,
      anchorDate: from,
      defaultTimezone: _tz,
      effectiveFrom: from,
    ),
    templates: service.templates(jobId),
  );
}

int _overrideCount(Database db) =>
    db.select('SELECT COUNT(*) AS c FROM overrides').first['c'] as int;

void main() {
  setUpAll(initializeTimezoneDatabase);

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  group('M1b — Today screen', () {
    testWidgets('today shift + weekly hours from UTC (daily 7×12h = 84h)',
        (tester) async {
      final db = openInMemory();
      final patterns = PatternRepository(db);
      final service = ScheduleService(
          patterns: patterns, schedule: ScheduleRepository(db, patterns), db: db);
      final now = DateTime.now();
      final monday = _mondayOf(now);
      final jobId = service.createJob(name: 'Hospital', timezone: _tz);
      service.saveTemplate(
        jobId: jobId,
        template: ShiftTemplate(
          id: slugId('tpl', ['Day', '07:00', '19:00']),
          jobId: jobId,
          name: 'Day',
          code: 'D',
          color: '#1565C0',
          startTime: '07:00',
          endTime: '19:00',
        ),
      );
      final tplId = service.templates(jobId).first.id;
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: slugId('pat', ['Daily', jobId, _iso(monday)]),
          jobId: jobId,
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: [tplId],
          anchorDate: _iso(monday),
          defaultTimezone: _tz,
          effectiveFrom: _iso(monday),
        ),
        templates: service.templates(jobId),
      );

      await pump(tester, TodayScreen(service: service));

      // Today always has its shift (daily pattern from this week's Monday).
      expect(find.textContaining('Today · 1 shift'), findsOneWidget);
      expect(find.textContaining('Day'), findsWidgets);
      // 7 daily 12h shifts in Mon..Sun, duration from resolved UTC → 84.0h.
      expect(find.text('84.0h'), findsOneWidget,
          reason: 'weekly hours must come from UTC durations (INVARIANT-002)');
      db.close();
    });
  });

  group('M1b — Month view', () {
    testWidgets('all month days listed; tapping a day drills into its week',
        (tester) async {
      final db = openInMemory();
      final patterns = PatternRepository(db);
      final service = ScheduleService(
          patterns: patterns, schedule: ScheduleRepository(db, patterns), db: db);
      final now = DateTime.now();
      final first = DateTime(now.year, now.month, 1);
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final jobId = service.createJob(name: 'Hospital', timezone: _tz);
      service.saveTemplate(
        jobId: jobId,
        template: ShiftTemplate(
          id: slugId('tpl', ['Day', '07:00', '19:00']),
          jobId: jobId,
          name: 'Day',
          code: 'D',
          color: '#1565C0',
          startTime: '07:00',
          endTime: '19:00',
        ),
      );
      final tplId = service.templates(jobId).first.id;
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: slugId('pat', ['Daily', jobId, _iso(first)]),
          jobId: jobId,
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: [tplId],
          anchorDate: _iso(first),
          defaultTimezone: _tz,
          effectiveFrom: _iso(first),
        ),
        templates: service.templates(jobId),
      );

      await pump(tester, MonthCalendarScreen(service: service, jobId: jobId));

      // Every in-month day shows its local start time '07:00' (out-of-month
      // cells are empty).
      expect(find.text('07:00'), findsNWidgets(daysInMonth));

      // Tap day 15 → drills into the WeekCalendar of that day's week (7 daily
      // shifts Mon..Sun visible there).
      final target = first.add(const Duration(days: 14));
      await tester.tap(find.byKey(ValueKey('month-day-${_iso(target)}')));
      await tester.pumpAndSettle();
      expect(find.byType(WeekCalendarScreen), findsOneWidget);
      expect(find.text('07:00–19:00'), findsNWidgets(7),
          reason: 'the week containing day 15 has 7 daily shifts');
      db.close();
    });
  });

  group('M1b — Quick Add: Custom time…', () {
    testWidgets('falls through to the full CREATE form and writes one override',
        (tester) async {
      final db = openInMemory();
      final patterns = PatternRepository(db);
      final service = ScheduleService(
          patterns: patterns, schedule: ScheduleRepository(db, patterns), db: db);
      final monday = _mondayOf(DateTime.now());
      _seed(service, _iso(monday), const []); // 4-on/4-off from Monday
      final jobId = service.jobs().first.id;
      final offIso = _addDays(_iso(monday), 4); // Friday OFF

      await pump(tester, WeekCalendarScreen(service: service, jobId: jobId));
      expect(find.text('07:00–19:00'), findsNWidgets(4));

      await tester.tap(find.byKey(ValueKey('day-$offIso')));
      await tester.pumpAndSettle();
      expect(find.text('Quick add on $offIso'), findsOneWidget);

      await tester.tap(find.text('Custom time…'));
      await tester.pumpAndSettle();
      expect(find.text('Add shift on $offIso'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('shift-start')), '09:00');
      await tester.enterText(find.byKey(const ValueKey('shift-end')), '17:00');
      await tester.tap(find.text('Add shift'));
      await tester.pumpAndSettle();

      expect(find.text('09:00–17:00'), findsOneWidget);
      expect(_overrideCount(db), 1);
      final row = db.select('SELECT operation, patternId FROM overrides').first;
      expect(row['operation'], 'create');
      expect(row['patternId'], isNotNull);
      db.close();
    });
  });

  group('M1b — Roster re-version UI (D1/D9)', () {
    testWidgets('new version from a date closes the old at X−1, keeps anchor, '
        'past shifts unchanged', (tester) async {
      final db = openInMemory();
      final patterns = PatternRepository(db);
      final service = ScheduleService(
          patterns: patterns, schedule: ScheduleRepository(db, patterns), db: db);
      final now = DateTime.now();
      // v1 started 3 days ago → re-version default date = today.
      final base = _iso(now.subtract(const Duration(days: 3)));
      _seed(service, base, const []); // 4-on/4-off anchored [base]
      final jobId = service.jobs().first.id;
      final anchorBefore = service.patterns(jobId).first.anchorDate;

      // Baseline render of the PAST (base .. today−1) to compare later.
      final pastEnd = _addDays(base, 2); // base+0..+2 = 3 past workdays
      final pastBefore = service
          .renderJob(jobId: jobId, rangeStart: base, rangeEnd: pastEnd)
          .occurrences
          .map((o) => o.id)
          .toSet();

      // UI: open the job → tap the pattern → “New version from date…”.
      await pump(tester,
          JobDetailScreen(service: service, jobId: jobId));
      await tester.tap(find.text('Rota'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New version from date…'));
      await tester.pumpAndSettle();
      // Date picker is open with initial = today (earliest allowed = base+1).
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Builder opens prefilled as a NEW VERSION of Rota.
      expect(find.textContaining('New version of Rota'), findsOneWidget);
      await tester.tap(find.text('Save pattern'));
      await tester.pumpAndSettle();

      // Back on the job detail: two version rows exist now.
      expect(find.text('Shift patterns'), findsOneWidget);

      // Domain asserts:
      final versions = service.patterns(jobId); // ordered by id/effectiveFrom
      expect(versions.length, 2, reason: 'old closed + new open version');
      final todayIso = _iso(now);
      final oldV = versions.firstWhere((p) => p.effectiveFrom == base);
      final newV = versions.firstWhere((p) => p.effectiveFrom == todayIso);
      expect(oldV.effectiveUntil, _addDays(todayIso, -1),
          reason: 'D1: old version closes at X−1');
      expect(newV.effectiveUntil, isNull);
      expect(newV.anchorDate, anchorBefore,
          reason: 'D9: anchor (phase) must carry over across versions');

      // Past occurrences byte-identical after the version change.
      final pastAfter = service
          .renderJob(jobId: jobId, rangeStart: base, rangeEnd: pastEnd)
          .occurrences;
      expect(pastAfter.map((o) => o.id).toSet(), pastBefore,
          reason: 'INVARIANT-001: roster change never touches past shifts');
      db.close();
    });
  });
}
