// =============================================================================
// Gate C B1 (D-C5) — DST resolution UI. Widget-level, real :memory: SQLite.
//
//   1. AMBIGUOUS create (fall-back overlap, America/New_York 2026-11-01
//      01:00): the dialog lists BOTH candidate instants (offset per pass) and
//      even after the user acknowledges NO override/occurrence is written —
//      the engine never auto-picks and the payload cannot store "which pass".
//   2. NONEXISTENT create (spring-forward gap, 2026-03-08 02:30): informative
//      dialog, user told to pick another time, nothing written.
//   3. Control: an unambiguous time on the same date commits normally (the
//      gate must not block valid times).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/time/time_engine.dart' show initializeTimezoneDatabase;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/occurrence/occurrence_sheet.dart';

const _tz = 'America/New_York';

void main() {
  setUpAll(initializeTimezoneDatabase);

  late Database db;
  late ScheduleService service;
  late String jobId;
  late String tplId;

  setUp(() {
    db = dblib.openInMemory();
    final patterns = PatternRepository(db);
    service = ScheduleService(
      patterns: patterns,
      schedule: ScheduleRepository(db, patterns),
      db: db,
    );
    jobId = service.createJob(name: 'DST Hospital', timezone: _tz);
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
    tplId = service.templates(jobId).single.id;
  });

  tearDown(() => db.close());

  /// A daily pattern active on [anchor] so CREATE has a pattern to attach to.
  void seedDaily(String anchor) {
    final p = ShiftPattern(
      id: slugId('pat', ['Daily', jobId, anchor]),
      jobId: jobId,
      name: 'Daily',
      type: 'FIXED_CYCLE',
      cycleLengthDays: 1,
      sequence: [tplId],
      anchorDate: anchor,
      defaultTimezone: _tz,
      effectiveFrom: anchor,
    );
    service.saveNewPattern(pattern: p, templates: service.templates(jobId));
  }

  int overrideCount() =>
      db.select('SELECT COUNT(*) AS c FROM overrides').first['c'] as int;
  int occurrenceCount() =>
      db.select('SELECT COUNT(*) AS c FROM occurrences').first['c'] as int;

  /// Hosts the sheet inside a route so a successful commit pops back.
  Future<void> pumpSheet(WidgetTester tester, String date) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: OccurrenceSheet(
                    service: service,
                    jobId: jobId,
                    date: date,
                  ),
                ),
              )),
              child: const Text('open-sheet'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();
  }

  Future<void> fillTimes(WidgetTester tester, String start, String end) async {
    await tester.enterText(find.byKey(const ValueKey('shift-start')), start);
    await tester.enterText(find.byKey(const ValueKey('shift-end')), end);
    await tester.pumpAndSettle();
  }

  testWidgets('AMBIGUOUS create: picking an interpretation stores the chosen '
      'instant (RC §D real resolution)', (tester) async {
    // 2026-11-01 America/New_York: clocks fall back 02:00 EDT -> 01:00 EST,
    // so 01:00 occurs twice.
    seedDaily('2026-11-01');
    await pumpSheet(tester, '2026-11-01');
    await fillTimes(tester, '01:00', '09:00');

    await tester.tap(find.text('Add shift'));
    await tester.pumpAndSettle();

    // Dialog explains the overlap and offers BOTH candidate instants with
    // the offset of each pass (EDT 05:00Z vs EST 06:00Z for 01:00 local).
    expect(find.text('Time occurs twice (DST)'), findsOneWidget);
    expect(find.textContaining('happens TWICE'), findsOneWidget);
    expect(find.textContaining('UTC-04'), findsOneWidget);
    expect(find.textContaining('UTC-05'), findsOneWidget);

    // The user EXPLICITLY picks the second interpretation (EST, UTC-05 →
    // 06:00Z). The write proceeds with exactly that instant.
    await tester.tap(find.textContaining('UTC-05'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Store the picked interpretation'));
    await tester.pumpAndSettle();

    // Successful commit pops back to the host button.
    expect(find.text('open-sheet'), findsOneWidget);
    expect(find.text('Add shift'), findsNothing);
    expect(overrideCount(), 1, reason: 'the picked interpretation is stored');
    // The created override (EST pass) starts at 06:00Z, not 05:00Z (EDT).
    // The daily pattern ALSO projects a 01:00 baseline occurrence — the
    // effective schedule carries both; the created one is the picked instant.
    final rendered = service.renderJob(
        jobId: jobId, rangeStart: '2026-11-01', rangeEnd: '2026-11-01');
    final created = rendered.occurrences
        .where((o) => o.source == OccurrenceSource.created)
        .toList();
    expect(created, hasLength(1));
    expect(created.single.startDateTimeUtc, startsWith('2026-11-01T06:00'));
  });

  testWidgets('AMBIGUOUS create: acknowledging WITHOUT a pick still refuses '
      'the write (no auto-pick, D-C5)', (tester) async {
    seedDaily('2026-11-01');
    await pumpSheet(tester, '2026-11-01');
    await fillTimes(tester, '01:00', '09:00');

    await tester.tap(find.text('Add shift'));
    await tester.pumpAndSettle();

    // Acknowledge without selecting any interpretation → refused.
    await tester.tap(find.text('Store the picked interpretation'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not saved: 01:00 on 2026-11-01'),
        findsOneWidget);
    expect(find.text('Add shift'), findsOneWidget, reason: 'sheet still open');
    expect(overrideCount(), 0, reason: 'no override may be written');
    expect(occurrenceCount(), 0, reason: 'no occurrence may be written');
  });

  testWidgets('NONEXISTENT create is blocked with a clear message; nothing '
      'written', (tester) async {
    // 2026-03-08 America/New_York: clocks spring forward 02:00 -> 03:00, so
    // 02:30 does not exist.
    seedDaily('2026-03-08');
    await pumpSheet(tester, '2026-03-08');
    await fillTimes(tester, '02:30', '10:30');

    await tester.tap(find.text('Add shift'));
    await tester.pumpAndSettle();
    expect(find.text('Time does not exist (DST)'), findsOneWidget);
    expect(find.textContaining('does NOT exist'), findsOneWidget);

    await tester.tap(find.text('Choose a different time'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not saved: 02:30 on 2026-03-08'),
        findsOneWidget);
    expect(overrideCount(), 0);
    expect(occurrenceCount(), 0);
  });

  testWidgets('control: an unambiguous time still commits normally',
      (tester) async {
    seedDaily('2026-11-01');
    await pumpSheet(tester, '2026-11-01');
    await fillTimes(tester, '09:00', '17:00'); // unambiguous on 2026-11-01

    await tester.tap(find.text('Add shift'));
    await tester.pumpAndSettle();

    // Successful commit pops back to the host button.
    expect(find.text('open-sheet'), findsOneWidget);
    expect(find.text('Add shift'), findsNothing);
    expect(overrideCount(), 1);
    expect(occurrenceCount(), 0, reason: 'occurrences appear on next render');
  });
}
