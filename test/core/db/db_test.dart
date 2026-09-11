// =============================================================================
// Gate 3 — Persistence layer tests (in-memory SQLite, real sqlite3 FFI)
// =============================================================================
//
// Covers: migration idempotency, repo round-trips, versioned active-rule
// lookup (INVARIANT-006), engine<->DB render parity, override append-only
// replay, immutable pay-estimate snapshots, import-session audit reload.
// No mocks — every test runs against an actual SQLite database.
// =============================================================================

import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/pattern/pattern_engine.dart'
    show projectOccurrences, applyOverride;
import 'package:shiftease/core/time/time_engine.dart' show resolveShift;
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/import/import_types.dart';
import 'package:shiftease/core/import/import_engine.dart';

import 'package:sqlite3/sqlite3.dart' as sq;

ShiftTemplate tmpl(String id,
        {String start = '07:00', String end = '19:00'}) =>
    ShiftTemplate(
      id: id,
      jobId: 'job-1',
      name: id,
      code: id,
      color: '#3366FF',
      startTime: start,
      endTime: end,
    );

void main() {
  tz.initializeTimeZones();

  late sq.Database db;
  late PatternRepository pat;
  late ScheduleRepository sched;
  late PayRuleRepository pay;
  late ImportRepository imp;

  setUp(() {
    db = dblib.openInMemory();
    pat = PatternRepository(db);
    sched = ScheduleRepository(db, pat);
    pay = PayRuleRepository(db, pat);
    imp = ImportRepository(db);
    // RC §A8: PayRuleRepository refuses to auto-create jobs — the pay-rule
    // tests below target job-1, so seed it explicitly (the job form is the
    // only legitimate job origin).
    pat.ensureJob(id: 'job-1', name: 'Job 1', defaultTimezone: 'UTC');
  });
  tearDown(() => db.close());

  group('Migration', () {
    test('open migrates to schema v3 and is idempotent', () {
      expect(db.select('PRAGMA user_version').first.columnAt(0), 3);
      dblib.migrate(db); // no-op, must not throw / duplicate
      expect(db.select('PRAGMA user_version').first.columnAt(0), 3);
      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toSet();
      expect(tables, containsAll([
        'jobs', 'shift_templates', 'shift_patterns', 'pattern_sequence',
        'occurrences', 'overrides', 'pay_rules', 'pay_differentials',
        'pay_overtime_rules', 'import_sessions', 'import_candidates',
      ]));
    });

    test('foreign keys are enforced', () {
      expect(
        () => db.execute(
            'INSERT INTO shift_templates '
            '(uuid, id, jobUuid, name, code, color, startTime, endTime) '
            "VALUES ('u', 't', 'missing-job', 'n', 'c', '#000', '07:00', "
            "'19:00')"),
        throwsA(anything),
      );
    });

    test('a v1 database upgrades to v3 (patternId + import columns added)', () {
      // Build a raw v1 database by running every v1 DDL statement exported
      // from db.dart, then migrate() must add v2+v3 columns and bump
      // user_version without touching existing rows.
      final raw = dblib.defaultOpener(path: ':memory:');
      for (final ddl in dblib.v1Ddl) {
        raw.execute(ddl);
      }
      raw.execute('PRAGMA user_version = 1');
      raw.execute(
          "INSERT INTO overrides (uuid, id, occurrenceId, operation, "
          "payloadJson, createdAt) VALUES ('u', 'ovr-old', 'occ-1', 'UPDATE', "
          "'{}', '2026-01-01T00:00:00Z')");
      dblib.migrate(raw); // v1 -> v3
      expect(raw.select('PRAGMA user_version').first.columnAt(0), 3);
      // Existing row survived with NULL patternId; v2 column is queryable.
      final overrideCols = raw
          .select('PRAGMA table_info(overrides)')
          .map((r) => r['name'] as String)
          .toList();
      expect(overrideCols, contains('patternId'));
      final old = raw
          .select("SELECT * FROM overrides WHERE id = 'ovr-old'")
          .single;
      expect(old['patternId'], isNull);
      expect(old['occurrenceId'], 'occ-1');
      // v3 columns exist on occurrences + import_sessions.
      final occCols = raw
          .select('PRAGMA table_info(occurrences)')
          .map((r) => r['name'] as String)
          .toList();
      expect(occCols, containsAll(['jobId', 'isImported']));
      final impCols = raw
          .select('PRAGMA table_info(import_sessions)')
          .map((r) => r['name'] as String)
          .toList();
      expect(impCols, containsAll([
        'jobId',
        'committedOffDatesJson',
      ]));
      raw.close();
    });
  });

  group('Pattern + occurrence round-trip', () {
    test('templates/pattern + sequence survive save/load', () {
      pat.saveTemplate(jobId: 'job-1', t: tmpl('st-day'));
      final pattern = ShiftPattern(
        id: 'pat-a',
        jobId: 'job-1',
        name: 'A',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 7,
        sequence: ['st-day', null, 'st-day', null, 'st-day', null, null],
        anchorDate: '2026-09-07',
        defaultTimezone: 'America/New_York',
        effectiveFrom: '2026-01-01',
      );
      pat.savePattern(jobId: 'job-1', pattern: pattern,
          templates: [tmpl('st-day')]);

      final loaded = pat.patternsForJob('job-1').single;
      expect(loaded.sequence, pattern.sequence);
      expect(loaded.anchorDate, '2026-09-07');
      expect(pat.templatesForJob('job-1').single.id, 'st-day');
    });

    test('occurrences persist and reload identically (resolved UTC kept)',
        () {
      pat.savePattern(
        jobId: 'job-1',
        pattern: ShiftPattern(
          id: 'pat-d',
          jobId: 'job-1',
          name: 'D',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          sequence: List.filled(7, 'st-day'),
          anchorDate: '2026-09-07',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-01-01',
        ),
        templates: [tmpl('st-day')],
      );
      final rendered = sched.renderJobSchedule(
        jobId: 'job-1',
        rangeStart: '2026-09-07',
        rangeEnd: '2026-09-13',
      );
      expect(rendered.issues, isEmpty);
      expect(rendered.occurrences.length, 7);

      final stored = sched.occurrencesInRange(
          patternId: 'pat-d', from: '2026-09-07', to: '2026-09-13');
      expect(stored.length, 7);
      expect(stored.first.id, rendered.occurrences.first.id);
      expect(stored.first.startDateTimeUtc,
          rendered.occurrences.first.startDateTimeUtc);
      // Tuesday is UTC-4 in Sep: 07:00 EDT -> 11:00Z.
      expect(stored.first.startDateTimeUtc, '2026-09-07T11:00:00.000Z');
    });
  });

  group('PayRule versioned lookup (INVARIANT-006)', () {
    test('activeRuleFor returns the version effective at the date', () {
      pay.savePayRule(
          rule: PayRule(
        id: 'rule-v1',
        jobId: 'job-1',
        baseHourlyRate: 35,
        differentials: const [
          PayDifferential(
            type: DifferentialType.night,
            mode: DifferentialMode.percent,
            value: 10,
            scope: DifferentialScope.hoursInWindow,
            window: DifferentialWindow(startLocal: '22:00', endLocal: '06:00'),
          ),
        ],
        overtimeRules: const [
          OvertimeRule(
              thresholdHours: 8,
              period: OvertimePeriod.shift,
              multiplier: 1.5),
        ],
        effectiveFrom: '2026-01-01',
        effectiveUntil: '2026-06-30',
      ));
      pay.savePayRule(
          rule: PayRule(
        id: 'rule-v2',
        jobId: 'job-1',
        baseHourlyRate: 40,
        differentials: const [],
        overtimeRules: const [],
        effectiveFrom: '2026-07-01',
      ));

      final v1 = pay.activeRuleFor(jobId: 'job-1', date: '2026-06-15')!;
      final v2 = pay.activeRuleFor(jobId: 'job-1', date: '2026-07-15')!;
      expect(v1.id, 'rule-v1');
      expect(v1.baseHourlyRate, 35);
      expect(v1.differentials.single.scope, DifferentialScope.hoursInWindow);
      expect(v1.differentials.single.window!.startLocal, '22:00');
      expect(v1.overtimeRules.single.multiplier, 1.5);
      expect(v2.id, 'rule-v2');
      expect(v2.baseHourlyRate, 40);
    });
  });

  group('Override persistence + replay', () {
    test('append-only override survives restart-equivalent reload', () {
      pat.savePattern(
        jobId: 'job-1',
        pattern: ShiftPattern(
          id: 'pat-o',
          jobId: 'job-1',
          name: 'O',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          sequence: List.filled(7, 'st-day'),
          anchorDate: '2026-09-07',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-01-01',
        ),
        templates: [tmpl('st-day')],
      );
      final projection = projectOccurrences(
        pattern: pat.patternsForJob('job-1').single,
        rangeStart: '2026-09-07',
        rangeEnd: '2026-09-08',
        templates: pat.templatesForJob('job-1'),
      );
      final target = projection.occurrences.first;

      final override = Override(
        id: 'ovr-1',
        occurrenceId: target.id,
        operation: OverrideOperation.update,
        updatePayload: UpdatePayload(startTime: '09:00', endTime: '17:00'),
        createdAt: '2026-09-01T08:00:00Z',
        reason: OverrideReason.overtime,
      );
      sched.saveOverride(override);
      // Same deterministic id twice = idempotent (no duplicate log rows).
      sched.saveOverride(override);
      expect(db.select('SELECT COUNT(*) AS c FROM overrides').first['c'], 1);

      final reloaded =
          sched.overridesAffecting([target.id]).single;
      expect(reloaded.operation, OverrideOperation.update);
      expect(reloaded.updatePayload?.startTime, '09:00');
      expect(reloaded.reason, OverrideReason.overtime);
      expect(reloaded.createdAt, '2026-09-01T08:00:00Z');

      // Replay reproduces what the engine does directly.
      final viaEngine =
          applyOverride(projection.occurrences, reloaded,
              templates: {for (final t in pat.templatesForJob('job-1')) t.id: t});
      final viaRepo = sched.replayOverrides(
          projection.occurrences, [reloaded],
          {for (final t in pat.templatesForJob('job-1')) t.id: t});
      expect(viaRepo.issues, isEmpty);
      final eUpdated = viaEngine.occurrences.firstWhere((o) => o.id == target.id);
      final rUpdated = viaRepo.occurrences.firstWhere((o) => o.id == target.id);
      expect(rUpdated.startDateTimeUtc, eUpdated.startDateTimeUtc);
      expect(rUpdated.startDateTimeUtc, '2026-09-07T13:00:00.000Z'); // 09:00 EDT
    });

    test('chained overrides (split then update a part) survive re-render',
        () {
      // Regression (review Gate 3): renderJobSchedule pre-filtered the log to
      // BASELINE occurrence ids, silently dropping overrides that target
      // occurrences created by earlier overrides (split parts '<id>#p1').
      pat.savePattern(
        jobId: 'job-1',
        pattern: ShiftPattern(
          id: 'pat-chn',
          jobId: 'job-1',
          name: 'Chn',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          sequence: List.filled(7, 'st-day'),
          anchorDate: '2026-09-07',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-01-01',
        ),
        templates: [tmpl('st-day')],
      );
      sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-07');
      final baseId =
          sched.occurrencesInRange(patternId: 'pat-chn', from: '2026-09-07',
                  to: '2026-09-07')
              .single.id;

      final split = Override(
        id: 'ovr-split',
        occurrenceId: baseId,
        operation: OverrideOperation.split,
        createdAt: '2026-09-01T10:00:00Z',
        splitPayload: const SplitPayload(parts: [
          SplitPart(
              startTime: '07:00',
              endTime: '13:00',
              templateId: 'st-day',
              dateOffsetDays: 0),
          SplitPart(
              startTime: '13:00',
              endTime: '19:00',
              templateId: 'st-day',
              dateOffsetDays: 0),
        ]),
      );
      final part1 = Override(
        id: 'ovr-upd-part',
        occurrenceId: '$baseId#p1', // targets the SPLIT-created part
        operation: OverrideOperation.update,
        createdAt: '2026-09-02T10:00:00Z',
        updatePayload: const UpdatePayload(startTime: '14:00'),
      );
      sched.saveOverride(split);
      sched.saveOverride(part1);

      // Re-render from scratch (restart-equivalent): the chained update must
      // NOT be dropped by the log pre-filter.
      final rendered = sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-07');
      expect(rendered.issues, isEmpty);
      final p1 = rendered.occurrences
          .firstWhere((o) => o.id == '$baseId#p1');
      // Split part was 13:00 local; chained update moved it to 14:00 local =
      // 18:00Z (EDT, UTC-4). 17:00Z would mean the update was dropped.
      expect(p1.startDateTimeUtc, '2026-09-07T18:00:00.000Z');
      expect(p1.endDateTimeUtc, '2026-09-07T23:00:00.000Z');
    });

    test('render applies stored overrides and persists the result', () {
      pat.savePattern(
        jobId: 'job-1',
        pattern: ShiftPattern(
          id: 'pat-r',
          jobId: 'job-1',
          name: 'R',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          sequence: List.filled(7, 'st-day'),
          anchorDate: '2026-09-07',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-01-01',
        ),
        templates: [tmpl('st-day')],
      );
      // First render to learn the baseline occurrence id of Sep 7.
      sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-07');
      final baseId =
          sched.occurrencesInRange(patternId: 'pat-r', from: '2026-09-07', to: '2026-09-07')
              .single.id;

      sched.saveOverride(Override(
        id: 'ovr-r1',
        occurrenceId: baseId,
        operation: OverrideOperation.update,
        updatePayload: UpdatePayload(startTime: '09:00', endTime: '17:00'),
        createdAt: '2026-09-01T09:00:00Z',
      ));

      final rendered = sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-07');
      expect(rendered.issues, isEmpty);
      final updated = rendered.occurrences.single;
      // Expected via the time engine, not copied from anywhere:
      final expected =
          resolveShift(shiftDate: '2026-09-07', startTime: '09:00',
              endTime: '17:00', timezone: 'America/New_York');
      expect(updated.startDateTimeUtc, expected.utcStart!.isoString);

      // Persisted row reflects the override.
      final stored =
          sched.occurrencesInRange(patternId: 'pat-r', from: '2026-09-07', to: '2026-09-07')
              .single;
      expect(stored.startDateTimeUtc, expected.utcStart!.isoString);
    });
  });

  group('Gate C A3 — override immutability (no silent ignore)', () {
    /// Seed a daily pattern + persist one rendered baseline occurrence.
    String seedOccurrence(String patId) {
      pat.savePattern(
        jobId: 'job-1',
        pattern: ShiftPattern(
          id: patId,
          jobId: 'job-1',
          name: 'A3',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          sequence: List.filled(7, 'st-a3'),
          anchorDate: '2026-09-07',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-01-01',
        ),
        templates: [tmpl('st-a3')],
      );
      sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-07');
      return sched
          .occurrencesInRange(patternId: patId, from: '2026-09-07',
              to: '2026-09-07')
          .single.id;
    }

    test('ADV-4: same id + IDENTICAL payload = idempotent no-op (1 row)', () {
      final baseId = seedOccurrence('pat-a3-idem');
      final o = Override(
        id: 'ovr-a3-idem',
        occurrenceId: baseId,
        operation: OverrideOperation.update,
        updatePayload: const UpdatePayload(startTime: '09:00', endTime: '17:00'),
        createdAt: '2026-09-01T08:00:00Z',
        reason: OverrideReason.custom,
      );
      sched.saveOverride(o);
      // A retry with a fresh timestamp is still the SAME edit (id + payload).
      sched.saveOverride(Override(
        id: o.id,
        occurrenceId: baseId,
        operation: OverrideOperation.update,
        updatePayload: const UpdatePayload(startTime: '09:00', endTime: '17:00'),
        createdAt: '2026-09-01T09:30:00Z',
        reason: OverrideReason.custom,
      ));
      expect(db.select('SELECT COUNT(*) AS c FROM overrides').first['c'], 1);
      // Stored payload is the ORIGINAL edit's (nothing overwritten).
      final stored =
          sched.overridesAffecting([baseId]).single;
      expect(stored.updatePayload?.startTime, '09:00');
      expect(stored.updatePayload?.endTime, '17:00');
    });

    test('A6: same id + REORDERED-EQUIVALENT payload = idempotent no-op '
        '(canonical compare ignores JSON key order)', () {
      final baseId = seedOccurrence('pat-a6-canon');
      // Insert the row directly with the payload keys in a DIFFERENT order
      // than payloadToJson emits — a JSON round-trip through another writer
      // must not create a false difference on re-save.
      final reorderedJson = '{"endTime":"17:00","startTime":"09:00"}';
      db.execute(
        '''INSERT INTO overrides
           (uuid, id, occurrenceId, operation, payloadJson,
            swapWithOccurrenceId, createdAt, reason, patternId)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          newUuid(), 'ovr-a6-canon', baseId, 'update', reorderedJson,
          null, '2026-09-01T08:00:00Z', null, null,
        ],
      );
      // Normal re-save (payloadToJson emits startTime first) → SAME contract.
      sched.saveOverride(Override(
        id: 'ovr-a6-canon',
        occurrenceId: baseId,
        operation: OverrideOperation.update,
        updatePayload: const UpdatePayload(startTime: '09:00', endTime: '17:00'),
        createdAt: '2026-09-01T09:00:00Z',
      ));
      expect(db.select('SELECT COUNT(*) AS c FROM overrides').first['c'], 1,
          reason: 'reordered-equivalent payload must not be a false conflict');

      // A REAL difference in the same reordered shape is still refused.
      expect(
        () => sched.saveOverride(Override(
          id: 'ovr-a6-canon',
          occurrenceId: baseId,
          operation: OverrideOperation.update,
          updatePayload: const UpdatePayload(startTime: '10:00', endTime: '17:00'),
          createdAt: '2026-09-01T10:00:00Z',
        )),
        throwsA(isA<ImmutableHistoryError>()),
        reason: 'key order is canonicalized, values are still compared exactly',
      );
      expect(db.select('SELECT COUNT(*) AS c FROM overrides').first['c'], 1);
    });

    test('ADV-3: same id + DIFFERENT payload throws and DB stays unchanged', () {
      final baseId = seedOccurrence('pat-a3-diff');
      final o = Override(
        id: 'ovr-a3-diff',
        occurrenceId: baseId,
        operation: OverrideOperation.update,
        updatePayload: const UpdatePayload(startTime: '09:00', endTime: '17:00'),
        createdAt: '2026-09-01T08:00:00Z',
      );
      sched.saveOverride(o);

      // Same id, different startTime -> loud refusal, never silent overwrite.
      expect(
        () => sched.saveOverride(Override(
          id: o.id,
          occurrenceId: baseId,
          operation: OverrideOperation.update,
          updatePayload: const UpdatePayload(startTime: '10:00', endTime: '18:00'),
          createdAt: '2026-09-01T09:00:00Z',
        )),
        throwsA(isA<ImmutableHistoryError>()),
      );
      // Also refuses an operation swap under the same id (different contract).
      expect(
        () => sched.saveOverride(Override(
          id: o.id,
          occurrenceId: baseId,
          operation: OverrideOperation.delete,
          createdAt: '2026-09-01T09:00:00Z',
        )),
        throwsA(isA<ImmutableHistoryError>()),
      );

      expect(db.select('SELECT COUNT(*) AS c FROM overrides').first['c'], 1);
      final stored = sched.overridesAffecting([baseId]).single;
      expect(stored.operation, OverrideOperation.update);
      expect(stored.updatePayload?.startTime, '09:00',
          reason: 'history unchanged after refused overwrite');
    });

    test('CREATE re-save under same id with a different patternId is refused',
        () {
      pat.savePattern(
        jobId: 'job-1',
        pattern: ShiftPattern(
          id: 'pat-a3-create',
          jobId: 'job-1',
          name: 'C',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: ['st-a3'],
          anchorDate: '2026-09-07',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-01-01',
        ),
        templates: [tmpl('st-a3')],
      );
      final o = Override(
        id: 'ovr-a3-create',
        occurrenceId: 'new-0907',
        operation: OverrideOperation.create,
        createPayload: const CreatePayload(
          date: '2026-09-07',
          templateId: 'st-a3',
          startTime: '09:00',
          endTime: '17:00',
          timezone: 'America/New_York',
        ),
        createdAt: '2026-09-01T08:00:00Z',
      );
      sched.saveOverride(o, patternId: 'pat-a3-create');
      // Same edit re-targeted at a DIFFERENT pattern is a different row.
      expect(
        () => sched.saveOverride(o, patternId: 'pat-a3-other'),
        throwsA(isA<ImmutableHistoryError>()),
      );
      // Identical re-save (same patternId) stays idempotent.
      sched.saveOverride(o, patternId: 'pat-a3-create');
      expect(db.select('SELECT COUNT(*) AS c FROM overrides').first['c'], 1);
    });
  });

  group('INVARIANT-006 pay snapshot immutability', () {
    test('snapshot set once; re-render never touches it; rewrite refused',
        () {
      pat.savePattern(
        jobId: 'job-1',
        pattern: ShiftPattern(
          id: 'pat-p',
          jobId: 'job-1',
          name: 'P',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          sequence: List.filled(7, 'st-day'),
          anchorDate: '2026-09-07',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-01-01',
        ),
        templates: [tmpl('st-day')],
      );
      sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-07');
      final id = sched
          .occurrencesInRange(patternId: 'pat-p', from: '2026-09-07', to: '2026-09-07')
          .single.id;

      sched.setPayEstimateSnapshot(
          occurrenceId: id, amount: 385.00, payRuleFrom: '2026-01-01');
      // Same amount again = fine (idempotent snapshot).
      sched.setPayEstimateSnapshot(
          occurrenceId: id, amount: 385.00, payRuleFrom: '2026-01-01');
      // Rewriting history to a DIFFERENT amount must be refused.
      expect(
          () => sched.setPayEstimateSnapshot(
              occurrenceId: id, amount: 480.00, payRuleFrom: '2026-07-01'),
          throwsA(isA<ImmutableHistoryError>()));

      // A re-render (temporal refresh) must NOT clobber the snapshot.
      sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-07');
      final reloaded = sched
          .occurrencesInRange(patternId: 'pat-p', from: '2026-09-07', to: '2026-09-07')
          .single;
      expect(reloaded.actualPayEstimate, closeTo(385.00, 0.005));
      expect(reloaded.payEstimateFrom, '2026-01-01');
    });
  });

  group('Import session persistence (audit)', () {
    test('committed session reloads with candidates + committed ids intact',
        () {
      final session = parseDocument(
        sourceType: ImportSourceType.pasteText,
        rawText: 'Sep 03 Day 07:00-19:00\nSep 04 Night 19:00-07:00\nSep 05 OFF',
        templates: const [
          TemplateSpec(
              id: 'tpl-day', name: 'Day', startTime: '07:00', endTime: '19:00'),
          TemplateSpec(
              id: 'tpl-night',
              name: 'Night',
              startTime: '19:00',
              endTime: '07:00+1'),
        ],
        referenceDate: '2026-09-01',
        timezone: 'America/New_York',
        id: 'session-1',
        createdAt: '2026-09-01T08:00:00Z',
      );
      final committed = commitImport(bulkAcceptHigh(session));
      expect(committed.error, isNull);
      // commitImport now returns a session without the window set; attach the
      // commit window (Gate A §A3) before persisting so the row satisfies the
      // COMMITTED-window invariant enforced by ImportRepository.
      final windowed = committed.session.withWindow(
          committed.committedOffDates.toList()..addAll(
              committed.shifts.map((s) => s.shiftDate)));
      imp.saveSession(windowed);

      final reloaded = imp.sessionById('session-1')!;
      expect(reloaded.state, ImportState.committed);
      expect(reloaded.candidates.length, 3);
      expect(reloaded.committedOccurrenceIds,
          committed.session.committedOccurrenceIds);
      expect(reloaded.committedOccurrenceIds.length, 2);
      expect(reloaded.rawExtraction.entries.length, 3);
      expect(reloaded.rawExtraction.entries.first.original,
          'Sep 03 Day 07:00-19:00');
      expect(reloaded.history.map((s) => s.name).toList(),
          ['idle', 'parsing', 'extracted', 'reviewing', 'committed']);

      // Audit query works on the reloaded session (plan2 §3.3).
      final cand = reloaded.candidateForOccurrenceId('occ-cand-1');
      expect(cand?.data.date, '2026-09-03');
      expect(cand?.data.shiftType, 'Day');
    });
  });

  group('Gate C A4 — committed ImportSession is immutable', () {
    /// Parse a clean 2-shift roster, review + commit it, persist the
    /// committed session (with its window) and return it for reuse.
    ImportSession commitAndSave(String sessionId) {
      final session = parseDocument(
        sourceType: ImportSourceType.pasteText,
        rawText: 'Sep 03 Day 07:00-19:00\nSep 04 Night 19:00-07:00',
        templates: const [
          TemplateSpec(
              id: 'tpl-day', name: 'Day', startTime: '07:00', endTime: '19:00'),
          TemplateSpec(
              id: 'tpl-night',
              name: 'Night',
              startTime: '19:00',
              endTime: '07:00+1'),
        ],
        referenceDate: '2026-09-01',
        timezone: 'UTC',
        id: sessionId,
        createdAt: '2026-09-01T08:00:00Z',
      );
      final committed = commitImport(bulkAcceptHigh(session));
      expect(committed.error, isNull);
      final windowed = committed.session.withWindow(
          committed.committedOffDates.toList()..addAll(
              committed.shifts.map((s) => s.shiftDate)));
      imp.saveSession(windowed);
      return windowed;
    }

    test('ADV-5: overwriting a COMMITTED session (raw changed) throws and '
        'the stored row is untouched', () {
      final committed = commitAndSave('sess-a4-raw');

      // A different extraction under the SAME id -> rewrite attempt.
      final tampered = committed.copyWith(
        rawExtraction: const RawExtraction(
            sourceType: ImportSourceType.pasteText,
            entries: [
              RawEntry(
                  lineNumber: 1,
                  original: 'Sep 05 OFF',
                  shiftTypeLabel: 'Off'),
            ]),
      );
      expect(() => imp.saveSession(tampered), throwsStateError);

      // State downgrade under the same id is also a rewrite attempt.
      final downgraded = committed.copyWith(state: ImportState.reviewing);
      expect(() => imp.saveSession(downgraded), throwsStateError);

      // Nothing changed on disk.
      final reloaded = imp.sessionById('sess-a4-raw')!;
      expect(reloaded.state, ImportState.committed);
      expect(reloaded.rawExtraction.entries.length, 2);
      expect(reloaded.history.map((s) => s.name).toList(),
          ['idle', 'parsing', 'extracted', 'reviewing', 'committed']);
    });

    test('ADV-5b: identical re-save of a committed session = idempotent no-op',
        () {
      commitAndSave('sess-a4-idem');
      // Round-trip through the repo (reload) then save again unchanged.
      final reloaded = imp.sessionById('sess-a4-idem')!;
      imp.saveSession(reloaded); // must not throw, must not duplicate
      expect(imp.sessionById('sess-a4-idem')!.state, ImportState.committed);
      final n = db.select('SELECT COUNT(*) AS c FROM import_sessions').first['c'];
      expect(n, 1);
    });

    test('a REVIEWING session still accepts legitimate updates', () {
      final session = parseDocument(
        sourceType: ImportSourceType.pasteText,
        rawText: 'Sep 03 Day 07:00-19:00',
        templates: const [
          TemplateSpec(
              id: 'tpl-day', name: 'Day', startTime: '07:00', endTime: '19:00')
        ],
        referenceDate: '2026-09-01',
        timezone: 'UTC',
        id: 'sess-a4-review',
        createdAt: '2026-09-01T08:00:00Z',
      );
      final reviewing = applyReview(session,
          candidateId: session.candidates.single.id,
          action: ReviewAction.approve);
      imp.saveSession(reviewing); // EXTRACTED -> REVIEWING row persists

      // Another legitimate review step on the same id.
      final reReview = applyReview(reviewing,
          candidateId: reviewing.candidates.single.id,
          action: ReviewAction.reject);
      imp.saveSession(reReview);
      final reloaded = imp.sessionById('sess-a4-review')!;
      expect(reloaded.state, ImportState.reviewing);
      expect(
          reloaded.candidates.single.reviewStatus, ReviewStatus.rejected);
    });
  });

  group('Job isolation', () {
    test('patterns and pay rules of one job never leak into another', () {
      pat.savePattern(
        jobId: 'job-A',
        pattern: ShiftPattern(
          id: 'pat-A',
          jobId: 'job-A',
          name: 'A',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          sequence: List.filled(7, 'st'),
          anchorDate: '2026-09-07',
          defaultTimezone: 'UTC',
          effectiveFrom: '2026-01-01',
        ),
        templates: [tmpl('st')],
      );
      pay.savePayRule(
          rule: PayRule(
        id: 'r-A',
        jobId: 'job-A',
        baseHourlyRate: 35,
        differentials: const [],
        overtimeRules: const [],
        effectiveFrom: '2026-01-01',
      ));
      expect(pat.patternsForJob('job-B'), isEmpty);
      expect(pat.templatesForJob('job-B'), isEmpty);
      expect(pay.activeRuleFor(jobId: 'job-B', date: '2026-09-07'), isNull);
      expect(pay.allRulesFor('job-A').single.baseHourlyRate, 35);
    });
  });

  group('Import-commit seam (plan7 D-M2-1 — schema v3)', () {
    /// Daily 07:00–19:00 pattern from 2026-09-07 (UTC 11:00Z–23:00Z EDT).
    void seedDailyPattern() {
      pat.ensureJob(id: 'job-1', name: 'H', defaultTimezone: 'America/New_York');
      pat.savePattern(
        jobId: 'job-1',
        pattern: ShiftPattern(
          id: 'pat-d',
          jobId: 'job-1',
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: ['st-day'],
          anchorDate: '2026-09-07',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-09-07',
        ),
        templates: [tmpl('st-day')],
      );
    }

    ImportSession committedSession({required List<String> off}) => ImportSession(
          id: 'sess-1',
          createdAt: '2026-09-01T00:00:00Z',
          sourceType: ImportSourceType.pasteText,
          state: ImportState.committed,
          referenceDate: '2026-09-01',
          timezone: 'America/New_York',
          rawExtraction: RawExtraction(
              sourceType: ImportSourceType.pasteText, entries: const []),
          candidates: const [],
          committedOccurrenceIds: const [],
          committedOffDates: off,
        );

    test('imported rows + OFF days replace the pattern on those dates; '
        'other dates keep pattern behaviour (mixed window)', () {
      seedDailyPattern();
      // Commit roster for 09-09 (shift 09:00–17:00) and 09-10 (OFF).
      sched.replaceImportedOccurrences(
        jobId: 'job-1',
        from: '2026-09-09',
        to: '2026-09-09',
        rows: [
          ShiftOccurrence(
            id: 'occ-cand-1',
            patternId: '',
            shiftDate: '2026-09-09',
            templateId: '',
            startDateTimeUtc: '2026-09-09T13:00:00.000Z',
            endDateTimeUtc: '2026-09-09T21:00:00.000Z',
            timezone: 'America/New_York',
            source: OccurrenceSource.created,
            jobId: 'job-1',
            isImported: true,
          ),
        ],
      );
      imp.saveSession(committedSession(off: ['2026-09-10']).copyWith(
        windowStart: '2026-09-09',
        windowEnd: '2026-09-10',
      ), jobId: 'job-1');

      final result = sched.renderJobSchedule(
          jobId: 'job-1',
          rangeStart: '2026-09-07',
          rangeEnd: '2026-09-13');
      final byDate = {
        for (final o in result.occurrences) o.shiftDate: o,
      };
      // 09-09 is the imported 09:00–17:00 (UTC 13:00Z), NOT the pattern day.
      expect(byDate['2026-09-09']!.startDateTimeUtc,
          '2026-09-09T13:00:00.000Z');
      expect(byDate['2026-09-09']!.isImported, isTrue);
      // 09-10 approved OFF suppresses the pattern entirely (no occurrence).
      expect(byDate.containsKey('2026-09-10'), isFalse);
      // Untouched days keep the pattern 07:00–19:00 (UTC 11:00Z).
      expect(byDate['2026-09-07']!.startDateTimeUtc,
          '2026-09-07T11:00:00.000Z');
      expect(byDate['2026-09-08']!.startDateTimeUtc,
          '2026-09-08T11:00:00.000Z');
      expect(byDate['2026-09-11']!.startDateTimeUtc,
          '2026-09-11T11:00:00.000Z');
      expect(result.occurrences.length, 6, reason: '7 days − 1 imported-only')
          ; // 09-09 present once (imported), 09-10 gone, others pattern
    });

    test('a newer import replaces the older one inside the window', () {
      seedDailyPattern();
      sched.replaceImportedOccurrences(
        jobId: 'job-1', from: '2026-09-08', to: '2026-09-09',
        rows: [
          ShiftOccurrence(
              id: 'occ-cand-old',
              patternId: '',
              shiftDate: '2026-09-08',
              templateId: '',
              startDateTimeUtc: '2026-09-08T12:00:00.000Z',
              endDateTimeUtc: '2026-09-08T20:00:00.000Z',
              timezone: 'America/New_York',
              source: OccurrenceSource.created,
              jobId: 'job-1',
              isImported: true),
        ],
      );
      // Newer session replaces 09-08 with a different time.
      sched.replaceImportedOccurrences(
        jobId: 'job-1', from: '2026-09-08', to: '2026-09-08',
        rows: [
          ShiftOccurrence(
              id: 'occ-cand-new',
              patternId: '',
              shiftDate: '2026-09-08',
              templateId: '',
              startDateTimeUtc: '2026-09-08T14:00:00.000Z',
              endDateTimeUtc: '2026-09-08T22:00:00.000Z',
              timezone: 'America/New_York',
              source: OccurrenceSource.created,
              jobId: 'job-1',
              isImported: true),
        ],
      );
      final result = sched.renderJobSchedule(
          jobId: 'job-1',
          rangeStart: '2026-09-07',
          rangeEnd: '2026-09-10');
      final on8 =
          result.occurrences.where((o) => o.shiftDate == '2026-09-08').toList();
      expect(on8.length, 1, reason: 'old committed row replaced in window');
      expect(on8.single.id, 'occ-cand-new');
      expect(on8.single.startDateTimeUtc, '2026-09-08T14:00:00.000Z');
    });

    test('transaction-atomic seam: a failing occurrence write rolls the '
        'whole commit back — the session never becomes COMMITTED '
        '(Gate A §A2)', () {
      seedDailyPattern();
      // Mirror commitRoster's transaction: caller opens BEGIN, writes the
      // session + occurrences, COMMITs. Force the occurrence write to FAIL
      // (two rows sharing one id → UNIQUE constraint on the second insert)
      // and ROLLBACK — both the session and the partial rows must vanish.
      final session = committedSession(off: const []).copyWith(
        windowStart: '2026-09-09',
        windowEnd: '2026-09-10',
      );
      var threw = false;
      db.execute('BEGIN');
      try {
        imp.saveSession(session, jobId: 'job-1');
        sched.replaceImportedOccurrencesInTransaction(
          jobId: 'job-1',
          from: '2026-09-09',
          to: '2026-09-10',
          rows: [
            ShiftOccurrence(
                id: 'occ-dupe',
                patternId: '',
                shiftDate: '2026-09-09',
                templateId: '',
                startDateTimeUtc: '2026-09-09T13:00:00.000Z',
                endDateTimeUtc: '2026-09-09T21:00:00.000Z',
                timezone: 'America/New_York',
                source: OccurrenceSource.created,
                jobId: 'job-1',
                isImported: true),
            ShiftOccurrence(
                id: 'occ-dupe',
                patternId: '',
                shiftDate: '2026-09-10',
                templateId: '',
                startDateTimeUtc: '2026-09-10T13:00:00.000Z',
                endDateTimeUtc: '2026-09-10T21:00:00.000Z',
                timezone: 'America/New_York',
                source: OccurrenceSource.created,
                jobId: 'job-1',
                isImported: true),
          ],
        );
        db.execute('COMMIT');
      } catch (_) {
        threw = true;
        db.execute('ROLLBACK');
      }
      expect(threw, isTrue,
          reason: 'duplicate imported id must fail the occurrence write');
      expect(db.select('SELECT COUNT(*) c FROM occurrences').first['c'], 0,
          reason: 'rollback: zero occurrence rows persisted');
      expect(
          db
              .select(
                  "SELECT COUNT(*) c FROM import_sessions WHERE id = 'sess-1'")
              .first['c'],
          0,
          reason: 'rollback: session must NOT be left in COMMITTED state');
    });

    test('window replacement: Import A (OFF) then Import B same day as Day '
        'with an empty OFF list → the day renders as the Day shift, not '
        'suppressed (Gate A §A3)', () {
      seedDailyPattern();
      // A: 09-10 approved OFF (window 09-10..09-10) suppresses the pattern day.
      imp.saveSession(
        committedSession(off: ['2026-09-10']).copyWith(
          windowStart: '2026-09-10',
          windowEnd: '2026-09-10',
        ),
        jobId: 'job-1',
      );
      final afterA = sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-10', rangeEnd: '2026-09-10');
      expect(afterA.occurrences, isEmpty,
          reason: 'A marks the day OFF — no occurrence, pattern suppressed');

      // B: the SAME day is re-imported as a Day shift and its committed OFF
      // list is [] — still a committed session, still authoritative in the
      // window, but it says “no OFF days here”. [] must override A's OFF
      // (the old != '[]' filter that dropped such sessions is gone).
      sched.replaceImportedOccurrences(
        jobId: 'job-1',
        from: '2026-09-10',
        to: '2026-09-10',
        rows: [
          ShiftOccurrence(
              id: 'occ-b-day',
              patternId: '',
              shiftDate: '2026-09-10',
              templateId: '',
              startDateTimeUtc: '2026-09-10T13:00:00.000Z',
              endDateTimeUtc: '2026-09-10T21:00:00.000Z',
              timezone: 'America/New_York',
              source: OccurrenceSource.created,
              jobId: 'job-1',
              isImported: true),
        ],
      );
      // session B is NEWER than A (createdAt + id) so it wins the window.
      imp.saveSession(
        ImportSession(
          id: 'sess-2',
          createdAt: '2026-09-02T00:00:00Z',
          sourceType: ImportSourceType.pasteText,
          state: ImportState.committed,
          referenceDate: '2026-09-01',
          timezone: 'America/New_York',
          rawExtraction: RawExtraction(
              sourceType: ImportSourceType.pasteText, entries: const []),
          candidates: const [],
          committedOccurrenceIds: const ['occ-b-day'],
          committedOffDates: const [], // authoritative empty OFF list
          windowStart: '2026-09-10',
          windowEnd: '2026-09-10',
        ),
        jobId: 'job-1',
      );

      final afterB = sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
      final on10 =
          afterB.occurrences.where((o) => o.shiftDate == '2026-09-10').toList();
      expect(on10.length, 1,
          reason: 'B replaces A for the window: the day is a Day shift');
      expect(on10.single.id, 'occ-b-day');
      expect(on10.single.startDateTimeUtc, '2026-09-10T13:00:00.000Z');
      expect(on10.single.isImported, isTrue);
    });

    test('version immutability: re-saving the same pattern id with a '
        'different payload throws, but the D9 close (effectiveUntil only) is '
        'allowed (Gate A §A6)', () {
      seedDailyPattern(); // id 'pat-d', name 'Daily', seq ['st-day']
      // Same id + different core payload → refused loudly.
      expect(
          () => pat.savePattern(
                jobId: 'job-1',
                pattern: ShiftPattern(
                  id: 'pat-d',
                  jobId: 'job-1',
                  name: 'Changed',
                  type: 'FIXED_CYCLE',
                  cycleLengthDays: 1,
                  sequence: const ['st-day'],
                  anchorDate: '2026-09-07',
                  defaultTimezone: 'America/New_York',
                  effectiveFrom: '2026-09-07',
                ),
              ),
          throwsA(isA<StateError>()),
          reason: 'same-id re-save with different content must never '
              'silently overwrite a persisted version');
      // Same id + changed sequence → also refused (sequence is payload).
      expect(
          () => pat.savePattern(
                jobId: 'job-1',
                pattern: ShiftPattern(
                  id: 'pat-d',
                  jobId: 'job-1',
                  name: 'Daily',
                  type: 'FIXED_CYCLE',
                  cycleLengthDays: 1,
                  sequence: const [null],
                  anchorDate: '2026-09-07',
                  defaultTimezone: 'America/New_York',
                  effectiveFrom: '2026-09-07',
                ),
              ),
          throwsA(isA<StateError>()),
          reason: 're-saving with a different sequence must be refused too');
      // The D9 close path (identical core payload, effectiveUntil newly set)
      // is the ONLY allowed mutation of an existing version row.
      pat.savePattern(
        jobId: 'job-1',
        pattern: ShiftPattern(
          id: 'pat-d',
          jobId: 'job-1',
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: const ['st-day'],
          anchorDate: '2026-09-07',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-09-07',
          effectiveUntil: '2026-09-30',
        ),
      );
      expect(pat.patternsForJob('job-1').single.effectiveUntil, '2026-09-30',
          reason: 'close persisted — the version now ends 09-30');
      // Once closed, re-opening (null) or re-closing at a different date is
      // refused too — the version history stays immutable (A6).
      expect(
          () => pat.savePattern(
                jobId: 'job-1',
                pattern: ShiftPattern(
                  id: 'pat-d',
                  jobId: 'job-1',
                  name: 'Daily',
                  type: 'FIXED_CYCLE',
                  cycleLengthDays: 1,
                  sequence: const ['st-day'],
                  anchorDate: '2026-09-07',
                  defaultTimezone: 'America/New_York',
                  effectiveFrom: '2026-09-07', // effectiveUntil omitted = open
                ),
              ),
          throwsA(isA<StateError>()),
          reason: 're-opening a closed version must be refused');
      expect(
          () => pat.savePattern(
                jobId: 'job-1',
                pattern: ShiftPattern(
                  id: 'pat-d',
                  jobId: 'job-1',
                  name: 'Daily',
                  type: 'FIXED_CYCLE',
                  cycleLengthDays: 1,
                  sequence: const ['st-day'],
                  anchorDate: '2026-09-07',
                  defaultTimezone: 'America/New_York',
                  effectiveFrom: '2026-09-07',
                  effectiveUntil: '2026-10-01', // different close date
                ),
              ),
          throwsA(isA<StateError>()),
          reason: 're-closing at a different date must be refused');
      // Identical re-save of the closed version stays a no-op (idempotent).
      pat.savePattern(
        jobId: 'job-1',
        pattern: ShiftPattern(
          id: 'pat-d',
          jobId: 'job-1',
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: const ['st-day'],
          anchorDate: '2026-09-07',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-09-07',
          effectiveUntil: '2026-09-30',
        ),
      );
      expect(pat.patternsForJob('job-1').single.effectiveUntil, '2026-09-30');
    });

    test('version immutability: re-saving the same pay rule id with a '
        'different payload throws (Gate A §A6)', () {
      pay.savePayRule(
          rule: PayRule(
        id: 'r-imm',
        jobId: 'job-1',
        baseHourlyRate: 35,
        differentials: const [],
        overtimeRules: const [],
        effectiveFrom: '2026-01-01',
      ));
      expect(
          () => pay.savePayRule(
              rule: PayRule(
            id: 'r-imm',
            jobId: 'job-1',
            baseHourlyRate: 40, // differs from the persisted 35
            differentials: const [],
            overtimeRules: const [],
            effectiveFrom: '2026-01-01',
          )),
          throwsA(isA<StateError>()),
          reason: 'same pay-rule id with a different rate must be refused');
      // Identical re-save stays a no-op (idempotent) — no exception.
      pay.savePayRule(
          rule: PayRule(
        id: 'r-imm',
        jobId: 'job-1',
        baseHourlyRate: 35,
        differentials: const [],
        overtimeRules: const [],
        effectiveFrom: '2026-01-01',
      ));
      expect(pay.allRulesFor('job-1').single.baseHourlyRate, 35);
    });

    test('RC A8: unknown jobId is rejected — a fake job is NEVER created', () {
      final before = db.select('SELECT COUNT(*) c FROM jobs').first['c'];
      expect(
        () => pay.savePayRule(rule: PayRule(
          id: 'r-ghost',
          jobId: 'no-such-job',
          baseHourlyRate: 20,
          differentials: const [],
          overtimeRules: const [],
          effectiveFrom: '2026-01-01',
        )),
        throwsA(isA<ArgumentError>()),
        reason: 'unknown job must be a loud error, not a silent fake job',
      );
      expect(db.select('SELECT COUNT(*) c FROM jobs').first['c'], before,
          reason: 'no fake job row may be inserted (RC §A8)');
      expect(pay.allRulesFor('no-such-job'), isEmpty);
    });

    test('RC A8: malformed money numbers are rejected before any write', () {
      PayRule rule({
        double base = 20,
        List<PayDifferential> diffs = const [],
        List<OvertimeRule> ots = const [],
      }) =>
          PayRule(
            id: 'r-bad',
            jobId: 'job-1',
            baseHourlyRate: base,
            differentials: diffs,
            overtimeRules: ots,
            effectiveFrom: '2026-01-01',
          );

      expect(() => pay.savePayRule(rule: rule(base: 0)),
          throwsA(isA<ArgumentError>()),
          reason: 'a zero base rate is not a rule');
      expect(() => pay.savePayRule(rule: rule(base: -5)),
          throwsA(isA<ArgumentError>()));
      expect(
        () => pay.savePayRule(rule: rule(diffs: const [
          PayDifferential(
              type: DifferentialType.night,
              mode: DifferentialMode.percent,
              value: -10),
        ])),
        throwsA(isA<ArgumentError>()),
        reason: 'negative differential value must be refused',
      );
      expect(
        () => pay.savePayRule(rule: rule(ots: const [
          OvertimeRule(
              thresholdHours: -1,
              period: OvertimePeriod.shift,
              multiplier: 1.5),
        ])),
        throwsA(isA<ArgumentError>()),
        reason: 'negative OT threshold must be refused',
      );
      expect(
        () => pay.savePayRule(rule: rule(ots: const [
          OvertimeRule(
              thresholdHours: 8,
              period: OvertimePeriod.shift,
              multiplier: 0.5),
        ])),
        throwsA(isA<ArgumentError>()),
        reason: 'an OT multiplier below 1 must be refused',
      );
      expect(
        () => pay.savePayRule(rule: rule(diffs: const [
          PayDifferential(
            type: DifferentialType.night,
            mode: DifferentialMode.percent,
            value: 20,
            scope: DifferentialScope.hoursInWindow,
            // window deliberately missing
          ),
        ])),
        throwsA(isA<ArgumentError>()),
        reason: 'a HOURS_IN_WINDOW differential without a window must be refused',
      );
      // Nothing was written by any rejected attempt.
      expect(pay.allRulesFor('job-1'), isEmpty);
    });

    test('RC A8: reordered differential/OT children = identical version '
        '(order-independent compare, idempotent no-op)', () {
      final rule = PayRule(
        id: 'r-order',
        jobId: 'job-1',
        baseHourlyRate: 35,
        differentials: const [
          PayDifferential(
              type: DifferentialType.weekend,
              mode: DifferentialMode.percent,
              value: 50),
          PayDifferential(
            type: DifferentialType.night,
            mode: DifferentialMode.percent,
            value: 20,
            scope: DifferentialScope.hoursInWindow,
            window: DifferentialWindow(startLocal: '22:00', endLocal: '06:00'),
          ),
        ],
        overtimeRules: const [
          OvertimeRule(
              thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
          OvertimeRule(
              thresholdHours: 8, period: OvertimePeriod.day, multiplier: 2.0),
        ],
        effectiveFrom: '2026-01-01',
      );
      pay.savePayRule(rule: rule);

      // Same children in a DIFFERENT order — still the SAME version.
      final reordered = PayRule(
        id: 'r-order',
        jobId: 'job-1',
        baseHourlyRate: 35,
        differentials: const [
          PayDifferential(
            type: DifferentialType.night,
            mode: DifferentialMode.percent,
            value: 20,
            scope: DifferentialScope.hoursInWindow,
            window: DifferentialWindow(startLocal: '22:00', endLocal: '06:00'),
          ),
          PayDifferential(
              type: DifferentialType.weekend,
              mode: DifferentialMode.percent,
              value: 50),
        ],
        overtimeRules: const [
          OvertimeRule(
              thresholdHours: 8, period: OvertimePeriod.day, multiplier: 2.0),
          OvertimeRule(
              thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
        ],
        effectiveFrom: '2026-01-01',
      );
      expect(() => pay.savePayRule(rule: reordered), returnsNormally,
          reason: 'child order is not part of the version identity (A8)');
      expect(pay.allRulesFor('job-1'), hasLength(1));

      // A REAL child change under the same id is still refused.
      expect(
        () => pay.savePayRule(rule: PayRule(
          id: 'r-order',
          jobId: 'job-1',
          baseHourlyRate: 35,
          differentials: const [
            PayDifferential(
                type: DifferentialType.weekend,
                mode: DifferentialMode.percent,
                value: 50),
            PayDifferential(
                type: DifferentialType.night,
                mode: DifferentialMode.percent,
                value: 20,
                scope: DifferentialScope.hoursInWindow,
                window: DifferentialWindow(
                    startLocal: '22:00', endLocal: '06:00')),
          ],
          overtimeRules: const [
            OvertimeRule(
                thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
            OvertimeRule(
                thresholdHours: 8, period: OvertimePeriod.day, multiplier: 2.5),
          ],
          effectiveFrom: '2026-01-01',
        )),
        throwsA(isA<StateError>()),
        reason: 'an actual multiplier change must still be refused',
      );
    });
  });
}
