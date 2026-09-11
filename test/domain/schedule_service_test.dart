// =============================================================================
// ScheduleService tests (M1 DoD, domain level). These exercise the service
// + repositories exactly the way the UI calls them, against a real SQLite
// file/`:memory:` DB — no engine fakes anywhere.
//
// Covered:
//   1. DoD restart: create job/template/pattern → render → UPDATE override →
//      re-render → CLOSE the DB → reopen the SAME file → the override and the
//      updated occurrence survive (append-only log replay, INVARIANT-001).
//   2. INVARIANT-001: an UPDATE never mutates the stored pattern.
//   3. CREATE on an OFF day survives a fresh render of the full week AND of a
//      sub-range that starts at the created date (schema v2 convention — the
//      P1 range-dependence regression from result9 §7d).
//   4. INVARIANT-007/002: occurrences keep their own timezone and wall-clock
//      display times derive from stored UTC through that zone.
// =============================================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:shiftease/core/db/db.dart';
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/time/time_engine.dart';
import 'package:shiftease/domain/schedule_service.dart';

/// PatternRepository whose SECOND savePatternInTransaction call throws — a
/// deterministic fault injection for Gate C A2 (the write of the NEW version
/// inside changeRosterFrom fails; the close of the old one must roll back).
class _FailingSecondInsertPatterns extends PatternRepository {
  _FailingSecondInsertPatterns(super.db);

  int _inTxnSaves = 0;

  @override
  void savePatternInTransaction({
    required String jobId,
    required ShiftPattern pattern,
    List<ShiftTemplate> templates = const [],
  }) {
    _inTxnSaves++;
    if (_inTxnSaves == 2) {
      throw StateError(
          'simulated failure while inserting the new version (Gate C A2)');
    }
    super.savePatternInTransaction(
        jobId: jobId, pattern: pattern, templates: templates);
  }
}

/// PatternRepository whose FIRST savePatternInTransaction call throws — the
/// CLOSE of the old version fails before the new one is ever written (RC plan
/// §A7 fail-before): nothing may be written at all.
class _FailingFirstClosePatterns extends PatternRepository {
  _FailingFirstClosePatterns(super.db);

  @override
  void savePatternInTransaction({
    required String jobId,
    required ShiftPattern pattern,
    List<ShiftTemplate> templates = const [],
  }) {
    throw StateError(
        'simulated failure while closing the old version (RC A7 fail-before)');
  }
}

/// P7.2: on this SQLCipher-linked build, on-disk test databases open KEYED
/// (same path production uses) — these restart tests now prove persistence
/// on an ENCRYPTED store.
const String kTestDbKey = 'shiftease-test-key';

void main() {
  setUpAll(initializeTimezoneDatabase);

  const tz = 'America/New_York';

  String today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  String addDays(String iso, int days) {
    final d = DateTime.parse(iso).add(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  ScheduleService harness(Database d) {
    final patterns = PatternRepository(d);
    return ScheduleService(
      patterns: patterns,
      schedule: ScheduleRepository(d, patterns),
      db: d,
    );
  }

  String seedJobAndTemplate(ScheduleService service) {
    final jobId = service.createJob(name: 'Hospital', timezone: tz);
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
    return jobId;
  }

  /// 4-on/4-off pattern anchored/effective [from] (day0..3 work, 4..7 OFF).
  String seedPattern(ScheduleService service, String jobId, String from) {
    final tplId = service.templates(jobId).first.id;
    final pattern = ShiftPattern(
      id: slugId('pat', ['Rota', jobId, from]),
      jobId: jobId,
      name: 'Rota',
      type: 'FIXED_CYCLE',
      cycleLengthDays: 8,
      sequence: [tplId, tplId, tplId, tplId, null, null, null, null],
      anchorDate: from,
      defaultTimezone: tz,
      effectiveFrom: from,
    );
    service.saveNewPattern(pattern: pattern, templates: service.templates(jobId));
    return pattern.id;
  }

  group('DoD — persist across restart (file DB)', () {
    test('UPDATE override + updated occurrence survive close/reopen', () {
      final tmp = Directory.systemTemp.createTempSync('se_dod');
      final path = '${tmp.path}/t.db';
      final from = today();
      final to = addDays(from, 6);

      final db1 = openDatabase(opener: defaultOpener, path: path, key: kTestDbKey);
      var service = ScheduleService(
        patterns: PatternRepository(db1),
        schedule: ScheduleRepository(db1, PatternRepository(db1)),
        db: db1,
      );
      final jobId = seedJobAndTemplate(service);
      seedPattern(service, jobId, from);

      final before = service.renderJob(jobId: jobId, rangeStart: from, rangeEnd: to);
      expect(before.issues, isEmpty);
      final target = before.occurrences.first;

      // UPDATE 07:00–19:00 → 08:00–16:00 on that occurrence.
      service.applyOverride(
        Override(
          id: service.newOverrideId(target.id),
          occurrenceId: target.id,
          operation: OverrideOperation.update,
          updatePayload: const UpdatePayload(startTime: '08:00', endTime: '16:00'),
          createdAt: ScheduleService.nowIso(),
        ),
        jobId: jobId,
      );
      final after = service.renderJob(jobId: jobId, rangeStart: from, rangeEnd: to);
      final updated = after.occurrences.firstWhere((o) => o.id == target.id);
      expect(updated.startDateTimeUtc, isNot(target.startDateTimeUtc));

      // The stored pattern never mutated (INVARIANT-001).
      final stored =
          service.patterns(jobId).firstWhere((p) => p.id == target.patternId);
      expect(stored.sequence.whereType<String>().length, 4);
      expect(stored.effectiveFrom, from);
      expect(stored.effectiveUntil, isNull);

      // RESTART: dispose the Database (closes the file), reopen the SAME
      // file with fresh repos + service.
      db1.close();
      final db2 = openDatabase(opener: defaultOpener, path: path, key: kTestDbKey);
      service = ScheduleService(
        patterns: PatternRepository(db2),
        schedule: ScheduleRepository(db2, PatternRepository(db2)),
        db: db2,
      );

      final restarted = service.renderJob(jobId: jobId, rangeStart: from, rangeEnd: to);
      final survived =
          restarted.occurrences.firstWhere((o) => o.id == target.id);
      expect(survived.startDateTimeUtc, updated.startDateTimeUtc,
          reason: 'override must replay after restart from the append-only log');
      expect(survived.endDateTimeUtc, updated.endDateTimeUtc);
      expect(survived.shiftDate, target.shiftDate);
      db2.close();
      File(path).deleteSync();
      tmp.deleteSync(recursive: true);
    });
  });

  group('CREATE on an OFF day (schema v2 convention)', () {
    test('survives full-week AND sub-range starting at the created date', () {
      final db = openInMemory();
      final service = harness(db);
      final jobId = seedJobAndTemplate(service);
      final from = today();
      seedPattern(service, jobId, from);
      final offDate = addDays(from, 4); // first OFF day of the cycle

      final tplId = service.templates(jobId).first.id;
      service.applyOverride(
        Override(
          id: service.newOverrideId('new_$offDate'),
          occurrenceId: 'new_$offDate',
          operation: OverrideOperation.create,
          createPayload: CreatePayload(
            date: offDate,
            templateId: tplId,
            startTime: '09:00',
            endTime: '17:00',
            timezone: tz,
          ),
          createdAt: ScheduleService.nowIso(),
        ),
        jobId: jobId,
        patternId: service.patterns(jobId).first.id,
      );

      // Full-week render sees exactly one shift on the OFF day.
      final full =
          service.renderJob(jobId: jobId, rangeStart: from, rangeEnd: addDays(from, 7));
      final createdInFull = full.occurrences.where((o) => o.shiftDate == offDate).toList();
      expect(createdInFull.length, 1,
          reason: 'OFF day must carry exactly the created shift');
      expect(createdInFull.single.source, OccurrenceSource.created);

      // Sub-range starting AT the created date (no baseline before it): the
      // CREATE must still be admitted — keyed on patternId + payload date,
      // never on a baseline occurrence root (P1 regression, result9 §7d).
      final sub =
          service.renderJob(jobId: jobId, rangeStart: offDate, rangeEnd: addDays(offDate, 3));
      final createdInSub = sub.occurrences.where((o) => o.shiftDate == offDate).toList();
      expect(createdInSub.length, 1, reason: 'CREATE must not be range-dependent');

      // Wall clock derives from stored UTC in the occurrence's own zone.
      expect(service.localWallTime(createdInSub.single)!.start, '09:00');
      expect(service.localWallTime(createdInSub.single)!.end, '17:00');
      db.close();
    });
  });

  // -------------------------------------------------------------------------
  // Gate C A2 — changeRosterFrom must be ONE transaction (close old + insert
  // new). A failure while inserting the new version must roll the close back:
  // the old pattern is never left CLOSED without a successor.
  // -------------------------------------------------------------------------
  group('Gate C A2 — atomic changeRosterFrom', () {
    test('happy path: old version closed, new version active after boundary',
        () {
      final db = openInMemory();
      final service = harness(db);
      final jobId = seedJobAndTemplate(service);
      final from = today();
      final patId = seedPattern(service, jobId, from);
      final current = service.patterns(jobId).single;

      final boundary = addDays(from, 5);
      final tplId = service.templates(jobId).first.id;
      final next = service.changeRosterFrom(
        current: current,
        newEffectiveFrom: boundary,
        newName: 'Rota v2',
        newCycleLengthDays: 4,
        newSequence: [tplId, null, null, null], // 1-on/3-off from v2
        templates: service.templates(jobId),
      );

      final versions = service.patterns(jobId);
      expect(versions.length, 2, reason: 'close + insert persisted');
      final oldV = versions.firstWhere((p) => p.id == patId);
      expect(oldV.effectiveUntil, addDays(boundary, -1),
          reason: 'old version closed the day before the boundary');
      final newV = versions.firstWhere((p) => p.id == next.id);
      expect(newV.effectiveFrom, boundary);
      expect(newV.effectiveUntil, isNull);
      expect(newV.anchorDate, current.anchorDate, reason: 'D9 anchor kept');

      // Render a range spanning the boundary: both versions contribute.
      final result = service.renderJob(
          jobId: jobId, rangeStart: from, rangeEnd: addDays(boundary, 6));
      expect(result.issues, isEmpty);
      final workDays = result.occurrences
          .where((o) => o.shiftDate.compareTo(boundary) >= 0)
          .map((o) => o.shiftDate)
          .toList();
      // v2 is 1-on/3-off with the ORIGINAL anchor kept (D9): slot 0 falls on
      // days whose offset from `from` is a multiple of 4. The first such day
      // at/after the boundary is `from+8` (boundary = from+5, 5%4=1).
      expect(workDays, [addDays(from, 8)],
          reason: 'v2 phase continues from the original anchor (D9)');
      final v2Shift = result.occurrences
          .firstWhere((o) => o.shiftDate == addDays(from, 8));
      expect(v2Shift.templateId, tplId);
      db.close();
    });

    test('failure while inserting the NEW version rolls back — old version '
        'is NOT left closed without a successor', () {
      final db = openInMemory();
      final repo = _FailingSecondInsertPatterns(db);
      final service = ScheduleService(
        patterns: repo,
        schedule: ScheduleRepository(db, repo),
        db: db,
      );
      final jobId = seedJobAndTemplate(service);
      final from = today();
      final patId = seedPattern(service, jobId, from);
      final current = service.patterns(jobId).single;
      final tplId = service.templates(jobId).first.id;

      // The second repository write inside changeRosterFrom throws. With the
      // two writes sharing ONE transaction, the close must roll back.
      expect(
        () => service.changeRosterFrom(
          current: current,
          newEffectiveFrom: addDays(from, 5),
          newName: 'Rota v2',
          newCycleLengthDays: 4,
          newSequence: [tplId, null, null, null],
          templates: service.templates(jobId),
        ),
        throwsStateError,
      );

      // No orphaned close: exactly the one OPEN version remains.
      final after = service.patterns(jobId);
      expect(after.length, 1, reason: 'new version insert rolled back');
      expect(after.single.id, patId);
      expect(after.single.effectiveUntil, isNull,
          reason: 'the close of the old version rolled back too (atomic)');
      db.close();
    });

    test('RC A7 fail-before: the close itself failing writes NOTHING — the '
        'old version stays open, no new row appears', () {
      final db = openInMemory();
      final repo = _FailingFirstClosePatterns(db);
      final service = ScheduleService(
        patterns: repo,
        schedule: ScheduleRepository(db, repo),
        db: db,
      );
      final jobId = seedJobAndTemplate(service);
      final from = today();
      seedPattern(service, jobId, from);
      final current = service.patterns(jobId).single;
      final tplId = service.templates(jobId).first.id;

      expect(
        () => service.changeRosterFrom(
          current: current,
          newEffectiveFrom: addDays(from, 5),
          newName: 'Rota v2',
          newCycleLengthDays: 4,
          newSequence: [tplId, null, null, null],
          templates: service.templates(jobId),
        ),
        throwsStateError,
      );

      final after = service.patterns(jobId);
      expect(after.length, 1, reason: 'nothing was written at all');
      expect(after.single.effectiveUntil, isNull,
          reason: 'the old version was never closed');
      db.close();
    });

    test('RC A7: the re-versioned schedule survives a restart (close + new '
        'version both persisted)', () {
      final dir = Directory.systemTemp.createTempSync('shiftease_a7_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dbPath = '${dir.path}/a7.db';
      final db = openDatabase(opener: defaultOpener, path: dbPath, key: kTestDbKey);
      final service = harness(db);
      final jobId = seedJobAndTemplate(service);
      final from = today();
      final patId = seedPattern(service, jobId, from);
      final current = service.patterns(jobId).single;
      final boundary = addDays(from, 5);
      final tplId = service.templates(jobId).first.id;
      service.changeRosterFrom(
        current: current,
        newEffectiveFrom: boundary,
        newName: 'Rota v2',
        newCycleLengthDays: 4,
        newSequence: [tplId, null, null, null],
        templates: service.templates(jobId),
      );

      db.close();
      final db2 = openDatabase(opener: defaultOpener, path: dbPath, key: kTestDbKey);
      final service2 = harness(db2);
      final versions = service2.patterns(jobId);
      expect(versions.length, 2);
      final oldV = versions.firstWhere((p) => p.id == patId);
      expect(oldV.effectiveUntil, addDays(boundary, -1),
          reason: 'the close persisted');
      final newV = versions.firstWhere((p) => p.effectiveFrom == boundary);
      expect(newV.effectiveUntil, isNull);
      db2.close();
    });
  });

  group('timezone retention (INVARIANT-007) + UTC-derived wall clock', () {
    test('daily pattern keeps tz and 07:00–19:00 wall clock', () {
      final db = openInMemory();
      final service = harness(db);
      final jobId = seedJobAndTemplate(service);
      final from = today();
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: slugId('pat', ['Daily', jobId, from]),
          jobId: jobId,
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: [service.templates(jobId).first.id],
          anchorDate: from,
          defaultTimezone: tz,
          effectiveFrom: from,
        ),
        templates: service.templates(jobId),
      );
      final result =
          service.renderJob(jobId: jobId, rangeStart: from, rangeEnd: addDays(from, 3));
      expect(result.issues, isEmpty);
      final o = result.occurrences.first;
      expect(o.timezone, tz, reason: 'INVARIANT-007');
      final wall = service.localWallTime(o)!;
      expect(wall.date, o.shiftDate, reason: 'INVARIANT-003 civil basis');
      expect(wall.start, '07:00');
      expect(wall.end, '19:00');
      db.close();
    });
  });
}
