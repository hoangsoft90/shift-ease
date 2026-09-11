// =============================================================================
// RC plan §C1/C2 — CSV mapping UI + re-import diff UI (widget level, real
// in-memory SQLite).
//
//   1. C1 CSV mode: paste CSV → Preview columns → map dropdowns auto-detected
//      → Validate & review → candidates + validation card. INVARIANT-004
//      holds: parsing alone writes ZERO schedule rows.
//   2. C1 validation card: an unmapped required column (start/end cleared)
//      surfaces the exact warning text from validateCsvMapping.
//   3. C2 diff card: after committing one roster, re-importing with a change
//      shows "+N added · −N removed · ~N changed · =N unchanged", the old →
//      new row, the signed Hours delta and the income impact (estimate).
//   4. C2 diff is honest about pending rows: pending candidates are skipped
//      by commit (Gate A §A5) so they never appear in the diff preview.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/time/time_engine.dart'
    show initializeTimezoneDatabase;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/import/import_screen.dart';

const _tz = 'America/New_York';
const _dayTplId = 'tpl-day-0700-1900';

ScheduleService _service(Database db) => ScheduleService(
      patterns: PatternRepository(db),
      schedule: ScheduleRepository(db, PatternRepository(db)),
      db: db,
      imports: ImportRepository(db),
      pay: PayRuleRepository(db, PatternRepository(db)),
    );

String _seedJob(ScheduleService service, {double? rate}) {
  final jobId = service.createJob(name: 'Hospital', timezone: _tz);
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
  if (rate != null) {
    service.savePayRule(PayRule(
      id: slugId('payrule', [jobId, 'r1']),
      jobId: jobId,
      baseHourlyRate: rate,
      differentials: const [],
      overtimeRules: const [],
      effectiveFrom: '2026-01-01',
    ));
  }
  return jobId;
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

/// Switch to CSV mode, paste [csv], preview, then validate & review.
Future<void> _importCsv(WidgetTester tester, String csv) async {
  await tester.tap(find.text('CSV'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, csv);
  await tester.tap(find.text('Preview columns'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Validate & review'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initializeTimezoneDatabase);

  testWidgets('C1: CSV mode parses with auto-detected mapping, shows the '
      'validation card, and writes nothing before commit', (tester) async {
    _useTallViewport(tester);
    final db = dblib.openInMemory();
    final service = _service(db);
    final jobId = _seedJob(service);

    await _pump(tester, ImportScreen(service: service, jobId: jobId));
    await _importCsv(
      tester,
      'date,shift,start,end\n'
      '2026-09-01,Day,07:00,19:00\n'
      '2026-09-02,OFF,,\n'
      '2026-09-03,Day,07:00,19:00\n',
    );

    // Session is EXTRACTED with the 3 rows; INVARIANT-004 holds.
    expect(find.textContaining('State: EXTRACTED'), findsOneWidget);
    expect(find.textContaining('pending 3'), findsOneWidget);
    expect(find.text('CSV validation'), findsOneWidget);
    expect(find.textContaining('All rows resolve cleanly'), findsOneWidget,
        reason: 'the clean CSV reports readiness, not silence');
    expect(db.select('SELECT COUNT(*) c FROM occurrences').first['c'], 0,
        reason: 'C1: parsing alone must never write schedule rows');
    db.close();
  });

  testWidgets('C1: unmapped start/end column surfaces the validation warning '
      '(never a silent wall of LOW rows)', (tester) async {
    _useTallViewport(tester);
    final db = dblib.openInMemory();
    final service = _service(db);
    final jobId = _seedJob(service);

    await _pump(tester, ImportScreen(service: service, jobId: jobId));
    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).first,
        'date,note\n'
        '2026-09-01,Day\n');
    await tester.tap(find.text('Preview columns'));
    await tester.pumpAndSettle();

    // Clear the auto-detected start/end mappings (nothing detected here) —
    // the dropdowns stay "(not mapped)" and the validation card explains.
    await tester.tap(find.text('Validate & review'));
    await tester.pumpAndSettle();

    expect(find.text('CSV validation'), findsOneWidget);
    expect(
        find.textContaining(
            'Start or End column is not mapped'),
        findsOneWidget,
        reason: 'C1: the missing-time warning is shown up-front');
    expect(find.textContaining('pending 1'), findsOneWidget,
        reason: 'the row still enters review as LOW, never auto-committed');
    db.close();
  });

  testWidgets('C2: diff card buckets the re-import against the committed '
      'roster with old→new, hours delta and income impact', (tester) async {
    _useTallViewport(tester);
    final db = dblib.openInMemory();
    final service = _service(db);
    final jobId = _seedJob(service, rate: 20); // $20/h for the impact line

    // Host screen that pushes a FRESH ImportScreen each time (a committed
    // session stays committed — the second import is a new session).
    Future<void> openImport() async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ImportScreen(service: service, jobId: jobId),
                )),
                child: const Text('open-import'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open-import'));
      await tester.pumpAndSettle();
    }

    // Commit the FIRST roster: Sep 01 + Sep 02 Day shifts.
    await openImport();
    await tester.enterText(find.byType(TextField).first,
        '2026-09-01 Day 07:00-19:00\n2026-09-02 Day 07:00-19:00');
    await tester.tap(find.text('Parse & review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept All High'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commit 2 approved row(s)'));
    await tester.pumpAndSettle();
    expect(find.text('Committed 2 shift(s) + 0 OFF day(s).'), findsOneWidget);

    // Back out, then re-import: Sep 01 unchanged, Sep 02 → OFF (removed
    // shift), Sep 03 added.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openImport();
    await tester.enterText(find.byType(TextField).first,
        '2026-09-01 Day 07:00-19:00\n2026-09-02 OFF\n2026-09-03 Day 07:00-19:00');
    await tester.tap(find.text('Parse & review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept All High'));
    await tester.pumpAndSettle();

    // The diff card previews exactly what commit will change.
    expect(find.text('What commit will change (vs current roster)'),
        findsOneWidget);
    expect(find.textContaining('+1 added · −0 removed · ~1 changed · =1 unchanged'),
        findsOneWidget,
        reason: 'Sep 02 shift→OFF is a MODIFIED day (old→new), not a removal');
    expect(find.textContaining('~ 2026-09-02: 07:00–19:00 → OFF'), findsOneWidget,
        reason: 'C2: modified rows carry old → new');
    expect(find.textContaining('Hours: no change'), findsOneWidget,
        reason: 'signed hours delta: 09-02 shift→OFF is -12h, 09-03 added is '
            '+12h → net 0');
    expect(find.textContaining('Income impact:'), findsOneWidget);
    db.close();
  });

  testWidgets('C2: pending rows never appear in the diff preview '
      '(commit skips them, so the preview must too)', (tester) async {
    _useTallViewport(tester);
    final db = dblib.openInMemory();
    final service = _service(db);
    final jobId = _seedJob(service, rate: 20);

    await _pump(tester, ImportScreen(service: service, jobId: jobId));
    await tester.enterText(find.byType(TextField).first,
        '2026-09-01 Day 07:00-19:00\n2026-09-02 Day 07:00-19:00');
    await tester.tap(find.text('Parse & review'));
    await tester.pumpAndSettle();

    // Approve ONLY 09-01; 09-02 stays pending.
    final first = find.ancestor(
        of: find.textContaining('2026-09-01'), matching: find.byType(Card));
    await tester.tap(find.descendant(of: first, matching: find.byTooltip('Approve')));
    await tester.pumpAndSettle();

    // The diff card covers only the approved row's span; nothing was ever
    // committed so both sides are empty → the card itself stays hidden
    // (nothing to compare), which is the honest answer for an empty diff.
    expect(find.text('What commit will change (vs current roster)'), findsOneWidget);
    expect(find.textContaining('+1 added · −0 removed · ~0 changed · =0 unchanged'),
        findsOneWidget,
        reason: 'only the APPROVED row is previewed — the pending one is not '
            'counted as a change because commit would skip it');
    db.close();
  });

  testWidgets('L1: commit button stays disabled in EXTRACTED state '
      '(the engine rejects EXTRACTED→COMMIT — the button must not invite '
      'a guaranteed error)', (tester) async {
    _useTallViewport(tester);
    final db = dblib.openInMemory();
    final service = _service(db);
    final jobId = _seedJob(service, rate: 20);

    await _pump(tester, ImportScreen(service: service, jobId: jobId));
    await tester.enterText(find.byType(TextField).first,
        '2026-09-01 Day 07:00-19:00\n2026-09-02 Day 07:00-19:00');
    await tester.tap(find.text('Parse & review'));
    await tester.pumpAndSettle();

    // Parse alone leaves the session EXTRACTED — no review action yet.
    expect(find.textContaining('State: EXTRACTED'), findsOneWidget);
    // The commit affordance is disabled (the disabled label variant shows).
    expect(find.text('Commit (approve at least 1 row first)'), findsOneWidget,
        reason: 'EXTRACTED rows are all pending, so the disabled label shows');
    expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton,
            'Commit (approve at least 1 row first)'))
        .onPressed,
        isNull,
        reason: 'L1: the commit button must be disabled before any review action');

    // The first review action moves EXTRACTED→REVIEWING and the button arms.
    await tester.tap(find.text('Accept All High'));
    await tester.pumpAndSettle();
    expect(find.textContaining('State: REVIEWING'), findsOneWidget);
    expect(find.text('Commit 2 approved row(s)'), findsOneWidget);
    expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton,
            'Commit 2 approved row(s)'))
        .onPressed,
        isNotNull,
        reason: 'REVIEWING with approved rows arms the commit button');
    db.close();
  });
}
