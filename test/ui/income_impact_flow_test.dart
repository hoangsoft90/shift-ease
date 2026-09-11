// =============================================================================
// RC plan §B6 — Income Impact preview (widget level, real :memory: SQLite).
//
//   The OccurrenceSheet shows a live "Income impact (this week)" line derived
//   from the CURRENT form values via estimateIncomeImpact — persist:false, the
//   DB is never touched by a preview:
//
//   1. AVAILABLE: a job with a base-only pay rule + daily pattern — opening
//      CREATE on a date and typing a shift re-prices the week
//      (7x12h @ $20 = $1680.00 → 8x12h = $1920.00, delta +$240.00).
//   2. UNAVAILABLE: the same job WITHOUT any pay rule shows the explicit
//      reason (never a fabricated number).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/time/time_engine.dart' show initializeTimezoneDatabase;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/occurrence/occurrence_sheet.dart';

const _tz = 'UTC';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _mondayIso() {
  final now = DateTime.now();
  final mon = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - DateTime.monday));
  return _iso(mon);
}

void main() {
  setUpAll(initializeTimezoneDatabase);

  late Database db;
  late ScheduleService service;
  late String jobId;

  setUp(() {
    db = dblib.openInMemory();
    final patterns = PatternRepository(db);
    service = ScheduleService(
      patterns: patterns,
      schedule: ScheduleRepository(db, patterns),
      db: db,
      pay: PayRuleRepository(db, patterns),
    );
    // Daily 07:00–19:00 pattern covering the current week → 7x12h.
    jobId = service.createJob(name: 'Impact Hospital', timezone: _tz);
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
    final from = _mondayIso();
    service.saveNewPattern(
      pattern: ShiftPattern(
        id: slugId('pat', ['Daily', jobId, from]),
        jobId: jobId,
        name: 'Daily',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 1,
        sequence: [service.templates(jobId).single.id],
        anchorDate: from,
        defaultTimezone: _tz,
        effectiveFrom: from,
      ),
      templates: service.templates(jobId),
    );
  });

  tearDown(() => db.close());

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

  testWidgets('B6 — live impact line prices the week: 7x12h @ \$20 '
      '= \$1680.00 -> 8x12h = \$1920.00 (+\$240.00), never persisted',
      (tester) async {
    service.savePayRule(PayRule(
      id: slugId('payrule', [jobId, _mondayIso()]),
      jobId: jobId,
      baseHourlyRate: 20,
      differentials: const [],
      overtimeRules: const [],
      effectiveFrom: _mondayIso(),
    ));

    await pumpSheet(tester, _mondayIso());
    await tester.pumpAndSettle();

    // The post-frame preview fires with the form defaults (07:00–19:00).
    expect(find.textContaining('Income impact (this week): \$1680.00 → '
        '\$1920.00 (+\$240.00) — estimate'), findsOneWidget);

    // Still nothing persisted by the preview.
    expect(
        db.select('SELECT COUNT(*) AS c FROM overrides').first['c'] as int, 0);
  });

  testWidgets('B6 — job without a pay rule: impact line shows the explicit '
      'reason, never a number', (tester) async {
    // No savePayRule for this job.
    await pumpSheet(tester, _mondayIso());
    await tester.pumpAndSettle();

    expect(find.textContaining('Income impact: Unable to calculate '
        'accurately'), findsOneWidget);
    expect(find.textContaining('no active pay rule'), findsOneWidget);
    expect(find.textContaining('→'), findsNothing,
        reason: 'no fabricated before→after numbers');
  });
}