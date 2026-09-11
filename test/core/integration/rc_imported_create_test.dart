// =============================================================================
// RC plan §A2 — imported-only roster must support CREATE.
//
//   1. A job with NO pattern: createShiftOnDate succeeds, the CREATE override
//      records the sentinel patternId (importedSchedulePatternId), render
//      shows the shift, and the shift survives a restart (file db).
//   2. The sentinel is job-scoped: another job's render never shows it.
//   3. Imported-only job: CREATE on a roster OFF day (deliberate manual
//      override) + DELETE of an imported shift both work.
//   4. Version-gap date (no pattern active that day) also attaches via the
//      sentinel — no fake pattern is ever created to pass validation.
// =============================================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/db.dart';
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/import/import_engine.dart' show applyReview;
import 'package:shiftease/core/import/import_types.dart' show ReviewAction;
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/time/time_engine.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/occurrence/override_actions.dart';

const _tz = 'America/New_York';

ScheduleService _service(Database db) => ScheduleService(
      patterns: PatternRepository(db),
      schedule: ScheduleRepository(db, PatternRepository(db)),
      db: db,
      imports: ImportRepository(db),
    );

String _seedJob(ScheduleService service, {String name = 'Hospital'}) {
  final jobId = service.createJob(name: name, timezone: _tz);
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

/// P7.2: on this SQLCipher-linked build, on-disk test databases open KEYED
/// (same path production uses) — these restart tests now prove persistence
/// on an ENCRYPTED store.
const String kTestDbKey = 'shiftease-test-key';

void main() {
  setUpAll(initializeTimezoneDatabase);

  group('A2 — imported-only job CREATE', () {
    test('no-pattern job: CREATE succeeds via sentinel, renders, survives '
        'restart, never leaks to another job', () {
      final dir = Directory.systemTemp.createTempSync('shiftease_a2_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dbPath = '${dir.path}/a2.db';
      final db = openDatabase(opener: defaultOpener, path: dbPath, key: kTestDbKey);
      final service = _service(db);
      final jobId = _seedJob(service);
      final tplId = service.templates(jobId).single.id;

      // A second job must never see job A's sentinel CREATE.
      final otherJob = _seedJob(service, name: 'Other');

      const date = '2026-09-15';
      final err = createShiftOnDate(
        service,
        jobId: jobId,
        date: date,
        templateId: tplId,
        start: '09:00',
        end: '17:00',
      );
      expect(err, isNull, reason: 'no-pattern job must support CREATE (A2)');

      // The override row records the sentinel patternId — no fake pattern.
      final row = db.select(
          'SELECT patternId FROM overrides WHERE operation = ?', ['create'])
          .single;
      expect(row['patternId'], importedSchedulePatternId(jobId),
          reason: 'CREATE convention for job-less schedules (A2)');
      expect(
        db.select('SELECT COUNT(*) c FROM shift_patterns').first['c'],
        0,
        reason: 'no fake pattern is ever fabricated (A2)',
      );

      // Render shows the created shift; the other job's render is empty.
      final r = service.renderJob(
          jobId: jobId, rangeStart: date, rangeEnd: date);
      expect(r.occurrences, hasLength(1));
      expect(r.issues, isEmpty);
      expect(service.localWallTime(r.occurrences.single)?.start, '09:00');
      final other = service.renderJob(
          jobId: otherJob, rangeStart: date, rangeEnd: date);
      expect(other.occurrences, isEmpty,
          reason: 'sentinel embeds the job id — no cross-job leakage');

      // Restart: the created shift persists (admission re-derives it).
      db.close();
      final db2 = openDatabase(opener: defaultOpener, path: dbPath, key: kTestDbKey);
      final service2 = _service(db2);
      final r2 = service2.renderJob(
          jobId: jobId, rangeStart: date, rangeEnd: date);
      expect(r2.occurrences, hasLength(1),
          reason: 'A2: created shift must survive restart');
      expect(r2.occurrences.single.id,
          db2.select('SELECT id FROM overrides LIMIT 1').first['id']);
      db2.close();
    });

    test('imported-only job: CREATE on a roster OFF day (manual override) + '
        'DELETE of an imported shift', () {
      final db = openInMemory();
      final service = _service(db);
      final jobId = _seedJob(service);
      final tplId = service.templates(jobId).single.id;

      // Commit a roster: 09-01 shift, 09-02 OFF.
      final parsed = service.parsePaste(
        jobId: jobId,
        rawText: '2026-09-01 Day 07:00-19:00\n2026-09-02 OFF',
        referenceDate: '2026-09-01',
      );
      final reviewed = applyReview(parsed, action: ReviewAction.bulkAcceptAllHigh);
      final result = service.commitRoster(session: reviewed, jobId: jobId);
      expect(result.error, isNull);

      final r0 = service.renderJob(
          jobId: jobId, rangeStart: '2026-09-01', rangeEnd: '2026-09-02');
      expect(r0.occurrences.map((o) => o.shiftDate), ['2026-09-01']);

      // CREATE on the import OFF day = deliberate manual override of the
      // roster — must succeed on a job with no pattern at all.
      final err = createShiftOnDate(
        service,
        jobId: jobId,
        date: '2026-09-02',
        templateId: tplId,
        start: '10:00',
        end: '18:00',
      );
      expect(err, isNull);
      final r1 = service.renderJob(
          jobId: jobId, rangeStart: '2026-09-01', rangeEnd: '2026-09-02');
      expect(r1.occurrences.map((o) => o.shiftDate).toSet(),
          {'2026-09-01', '2026-09-02'});

      // DELETE the imported shift — targets a roster row, not a pattern day.
      final imported =
          r1.occurrences.firstWhere((o) => o.shiftDate == '2026-09-01');
      final dErr = deleteShift(service, jobId: jobId, occurrence: imported);
      expect(dErr, isNull);
      final r2 = service.renderJob(
          jobId: jobId, rangeStart: '2026-09-01', rangeEnd: '2026-09-02');
      expect(r2.occurrences.map((o) => o.shiftDate), ['2026-09-02']);
      db.close();
    });

    test('version-gap date (no pattern active that day) attaches via sentinel',
        () {
      final db = openInMemory();
      final service = _service(db);
      final jobId = _seedJob(service);
      final tplId = service.templates(jobId).single.id;

      // Pattern active Mon..Wed only, closed with no successor.
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: slugId('pat', ['Short', jobId, '2026-09-14']),
          jobId: jobId,
          name: 'Short',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: [tplId],
          anchorDate: '2026-09-14',
          defaultTimezone: _tz,
          effectiveFrom: '2026-09-14',
          effectiveUntil: '2026-09-16',
        ),
        templates: service.templates(jobId),
      );

      const gapDate = '2026-09-18'; // Friday — no active version
      expect(service.patterns(jobId).any((p) => p.isActiveOn(gapDate)), isFalse,
          reason: 'precondition: the gap date has no active pattern');
      final err = createShiftOnDate(
        service,
        jobId: jobId,
        date: gapDate,
        templateId: tplId,
        start: '09:00',
        end: '17:00',
      );
      expect(err, isNull);
      final r = service.renderJob(
          jobId: jobId, rangeStart: '2026-09-14', rangeEnd: gapDate);
      expect(r.occurrences.any((o) => o.shiftDate == gapDate), isTrue);
      db.close();
    });
  });
}