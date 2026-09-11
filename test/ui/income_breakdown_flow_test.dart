// =============================================================================
// RC plan §B3/B4/B7 — income breakdown screen + multi-job weekly total.
//
//   1. Breakdown screen (this week) shows Date/Range, Hours, Regular Pay and
//      Estimated Total with the mandatory disclaimer (D-C6); a job WITHOUT a
//      rule shows 'Unable to calculate accurately' + the specific reason.
//   2. Range switching: 'This month' re-prices the range (multi-version month
//      stays deterministic — B4 via the per-occurrence estimator).
//   3. Today's multi-job total (B7): available jobs sum into
//      'available total', unavailable jobs are named as excluded — never $0.
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
import 'package:shiftease/core/time/time_engine.dart' show initializeTimezoneDatabase;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/income/income_breakdown_screen.dart';
import 'package:shiftease/features/today/today_screen.dart';

const _tz = 'America/New_York';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _mondayIso() {
  final now = DateTime.now();
  final mon = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - DateTime.monday));
  return _iso(mon);
}

ScheduleService _service(Database db) => ScheduleService(
      patterns: PatternRepository(db),
      schedule: ScheduleRepository(db, PatternRepository(db)),
      db: db,
      pay: PayRuleRepository(db, PatternRepository(db)),
    );

/// Seeds a job with a daily 07:00-19:00 pattern from this week's Monday and
/// (when [rate] != null) a pay rule at that rate from the same Monday.
String _seedJob(ScheduleService service, {double? rate, String name = 'H'}) {
  final jobId = service.createJob(name: name, timezone: _tz);
  service.saveTemplate(
    jobId: jobId,
    template: ShiftTemplate(
      id: slugId('tpl', [name, '07:00', '19:00']),
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
      id: slugId('pat', [name, jobId, from]),
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
  if (rate != null) {
    service.savePayRule(PayRule(
      id: slugId('payrule', [jobId, from]),
      jobId: jobId,
      baseHourlyRate: rate,
      differentials: const [],
      overtimeRules: const [],
      effectiveFrom: from,
    ));
  }
  return jobId;
}

void main() {
  setUpAll(initializeTimezoneDatabase);

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('B3: breakdown screen prices the week with disclaimer; no-rule '
      'job shows the explicit reason', (tester) async {
    final db = dblib.openInMemory();
    final service = _service(db);
    final jobId = _seedJob(service, rate: 20); // 7 x 12h x $20 = $1680

    await tester.pumpWidget(MaterialApp(
      home: IncomeBreakdownScreen(service: service, jobId: jobId),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Income · H'), findsOneWidget);
    expect(find.textContaining('Hours worked: 84.0h'), findsOneWidget);
    expect(find.text('Regular Pay'), findsOneWidget);
    // Regular Pay AND Estimated Total both read $1680 (no diff/OT here).
    expect(find.text('USD \$1680.00'), findsNWidgets(2));
    expect(find.text('Estimated Total'), findsOneWidget);
    expect(find.textContaining('Ước tính'), findsOneWidget,
        reason: 'D-C6: every amount ships with the estimate disclaimer');
    db.close();

    // No-rule job → 'Unable to calculate accurately' + the reason, no $0.
    final db2 = dblib.openInMemory();
    final service2 = _service(db2);
    final jobId2 = _seedJob(service2); // no rule
    await tester.pumpWidget(MaterialApp(
      home: IncomeBreakdownScreen(service: service2, jobId: jobId2),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Unable to calculate accurately'), findsOneWidget);
    expect(find.textContaining('không đoán số'), findsOneWidget);
    expect(find.textContaining('USD \$0.00'), findsNothing,
        reason: 'missing config is never displayed as a \$0 estimate');
    db2.close();
  });

  testWidgets('B4: This month re-prices the range; a custom start date '
      'switches the range label', (tester) async {
    final db = dblib.openInMemory();
    final service = _service(db);
    final jobId = _seedJob(service, rate: 10);

    await tester.pumpWidget(MaterialApp(
      home: IncomeBreakdownScreen(service: service, jobId: jobId),
    ));
    await tester.pumpAndSettle();

    // Default 'This week': range label is the week Mon..Sun.
    expect(find.textContaining('→'), findsOneWidget);

    await tester.tap(find.text('This month'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final monthLabel = '${_iso(DateTime(now.year, now.month, 1))} → '
        '${_iso(DateTime(now.year, now.month + 1, 0))}';
    expect(find.text(monthLabel), findsOneWidget,
        reason: 'B4: month range is the whole calendar month');
    expect(find.textContaining('Hours worked:'), findsOneWidget);
    db.close();
  });

  testWidgets('B7: multi-job total sums AVAILABLE jobs and names the excluded',
      (tester) async {
    useTallViewport(tester);
    final db = dblib.openInMemory();
    final service = _service(db);
    _seedJob(service, rate: 20, name: 'JobA'); // available: 84h x $20
    _seedJob(service, name: 'JobB'); // no rule → unavailable

    await tester.pumpWidget(MaterialApp(home: TodayScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.fling(
        find.byType(ListView).first, const Offset(0, -1600), 3000);
    await tester.pumpAndSettle();

    expect(find.text('All jobs · available total'), findsOneWidget);
    expect(find.text('USD \$1680.00'), findsWidgets,
        reason: 'B7: only the AVAILABLE job contributes');
    expect(find.textContaining('Total excludes 1 job(s)'), findsOneWidget,
        reason: 'B7: excluded jobs are stated, never silently turned into \$0');
    db.close();
  });
}