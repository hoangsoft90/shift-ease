// plan_payrule_version_ux.md §7 — domain tests for savePayRuleFromEditor.
//
// Cases (plan §2/§7): A idempotent no-op · B version-on-change (new id, old
// closed) · C first create · D invalid From rejected without partial write ·
// repo still refuses same-id different payload directly (A6) · close+insert
// atomic (failure after close rolls BOTH back).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/time/time_engine.dart'
    show initializeTimezoneDatabase;
import 'package:shiftease/domain/schedule_service.dart';

const _tz = 'UTC';

String _isoOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _dateOf(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

PayRule _draft({
  required String jobId,
  required String from,
  double base = 25,
}) =>
    PayRule(
      id: 'draft-id-unused-by-domain',
      jobId: jobId,
      baseHourlyRate: base,
      differentials: const [
        PayDifferential(
            type: DifferentialType.night,
            mode: DifferentialMode.percent,
            value: 10),
      ],
      overtimeRules: const [
        OvertimeRule(
            thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
      ],
      effectiveFrom: from,
    );

void main() {
  setUpAll(initializeTimezoneDatabase);

  late Database db;
  late ScheduleService service;
  late String jobId;
  late String today;

  setUp(() {
    db = dblib.openInMemory();
    final patterns = PatternRepository(db);
    service = ScheduleService(
      patterns: patterns,
      schedule: ScheduleRepository(db, patterns),
      db: db,
      pay: PayRuleRepository(db, patterns),
    );
    jobId = service.createJob(name: 'Hospital', timezone: _tz);
    final n = DateTime.now();
    today = _isoOf(DateTime(n.year, n.month, n.day));
  });

  test('C: first create (no existingId) → created, one row', () {
    final outcome = service.savePayRuleFromEditor(
      rule: _draft(jobId: jobId, from: today),
    );
    expect(outcome, 'created');
    expect(service.payRules(jobId).length, 1);
  });

  test('A: unchanged save → noOp success, no extra row, old stays open', () {
    service.savePayRuleFromEditor(rule: _draft(jobId: jobId, from: today));
    final existingId = service.payRules(jobId).single.id;

    final outcome = service.savePayRuleFromEditor(
      rule: _draft(jobId: jobId, from: today),
      existingId: existingId,
    );
    expect(outcome, 'noOp');
    expect(service.payRules(jobId).length, 1);
    expect(service.payRules(jobId).single.effectiveUntil, isNull);
  });

  test('B: changed rate + future From → new version (new id), old closed '
      'the day before; active-rule lookup follows the dates', () {
    service.savePayRuleFromEditor(rule: _draft(jobId: jobId, from: today));
    final old = service.payRules(jobId).single;

    final newFrom = _isoOf(_dateOf(today).add(const Duration(days: 7)));
    final outcome = service.savePayRuleFromEditor(
      rule: _draft(jobId: jobId, from: newFrom, base: 30),
      existingId: old.id,
    );
    expect(outcome, 'versioned');

    final rules = service.payRules(jobId);
    expect(rules.length, 2);
    final closedOld = rules.singleWhere((r) => r.id == old.id);
    final created = rules.singleWhere((r) => r.id != old.id);
    expect(closedOld.effectiveUntil, _isoOf(_dateOf(newFrom)
        .subtract(const Duration(days: 1))));
    expect(closedOld.baseHourlyRate, 25); // history never rewritten
    expect(created.baseHourlyRate, 30);
    expect(created.effectiveFrom, newFrom);
    expect(created.effectiveUntil, isNull);

    // Version resolution by date (INVARIANT-006 path).
    expect(service.activePayRule(jobId: jobId, date: today)!.baseHourlyRate,
        25);
    expect(
        service.activePayRule(jobId: jobId, date: newFrom)!.baseHourlyRate,
        30);
  });

  test('D: invalid From (before existing.effectiveFrom) → ArgumentError '
      'naming the floor date, NO partial write', () {
    service.savePayRuleFromEditor(rule: _draft(jobId: jobId, from: today));
    final old = service.payRules(jobId).single;

    final earlyFrom =
        _isoOf(_dateOf(old.effectiveFrom).subtract(const Duration(days: 5)));
    expect(
      () => service.savePayRuleFromEditor(
        rule: _draft(jobId: jobId, from: earlyFrom, base: 30),
        existingId: old.id,
      ),
      throwsA(isA<ArgumentError>().having(
          (e) => e.message, 'message', contains('on or after'))),
    );
    // No partial write: still one rule, still open.
    expect(service.payRules(jobId).length, 1);
    expect(service.payRules(jobId).single.effectiveUntil, isNull);
  });

  test('persistence still refuses same-id different payload (A6 intact)', () {
    service.savePayRuleFromEditor(rule: _draft(jobId: jobId, from: today));
    final existing = service.payRules(jobId).single;

    expect(
      () => service.savePayRule(PayRule(
        id: existing.id,
        jobId: jobId,
        baseHourlyRate: 99, // different payload, same id
        differentials: existing.differentials,
        overtimeRules: existing.overtimeRules,
        effectiveFrom: existing.effectiveFrom,
      )),
      throwsA(isA<StateError>()),
    );
    expect(service.payRules(jobId).single.baseHourlyRate, 25);
  });

  test('atomicity: failure after close rolls BOTH back (old stays open)', () {
    service.savePayRuleFromEditor(rule: _draft(jobId: jobId, from: today));
    final old = service.payRules(jobId).single;

    final newFrom = _isoOf(_dateOf(today).add(const Duration(days: 3)));
    // Invalid draft (base rate 0 → repo validation throws) AFTER the close
    // already ran inside the transaction → the whole txn must roll back.
    expect(
      () => service.savePayRuleFromEditor(
        rule: _draft(jobId: jobId, from: newFrom, base: 0),
        existingId: old.id,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(service.payRules(jobId).length, 1,
        reason: 'no orphan new version');
    expect(service.payRules(jobId).single.effectiveUntil, isNull,
        reason: 'the close must roll back with the failed insert');
  });
}
