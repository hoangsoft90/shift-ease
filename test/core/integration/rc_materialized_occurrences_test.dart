// =============================================================================
// RC plan §A3 — materialized occurrence semantics.
//
// The `occurrences` table is a MATERIALIZED effective-schedule cache, never a
// historical store (history = patterns/versions + override log + import
// sessions). Every render persists a scoped REPLACE for the job+range:
//
//   1. pattern shift → DELETE override → the old projection row for that day
//      is GONE from the table (a suppressed day must not keep a stale row
//      readable as a current shift).
//   2. import suppression → the pattern-projected row for the covered day is
//      removed; only the roster rows remain.
//   3. re-render / restart never resurrects a stale row.
//   4. an INVARIANT-006 pay snapshot on a STILL-effective row survives the
//      delete-then-upsert replace (never clobbered by the cache refresh).
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
      imports: ImportRepository(db),
    );

/// Seeds a job with a daily 07:00-19:00 pattern from [monday].
String _seedDaily(ScheduleService service, String monday) {
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
  final tplId = service.templates(jobId).single.id;
  service.saveNewPattern(
    pattern: ShiftPattern(
      id: slugId('pat', ['Daily', jobId, monday]),
      jobId: jobId,
      name: 'Daily',
      type: 'FIXED_CYCLE',
      cycleLengthDays: 1,
      sequence: [tplId],
      anchorDate: monday,
      defaultTimezone: _tz,
      effectiveFrom: monday,
    ),
    templates: service.templates(jobId),
  );
  return jobId;
}

int _rowsFor(Database db, String jobId, String from, String to) =>
    db.select(
        'SELECT COUNT(*) c FROM occurrences WHERE jobId = ? '
        'AND shiftDate >= ? AND shiftDate <= ?', [jobId, from, to])
        .first['c'] as int;

/// P7.2: on this SQLCipher-linked build, on-disk test databases open KEYED
/// (same path production uses) — these restart tests now prove persistence
/// on an ENCRYPTED store.
const String kTestDbKey = 'shiftease-test-key';

void main() {
  setUpAll(initializeTimezoneDatabase);

  test('DELETE override removes the stale projection row from the table',
      () {
    final db = openInMemory();
    final service = _service(db);
    final monday = _mondayIso();
    final jobId = _seedDaily(service, monday);
    final to = _iso(DateTime.parse(monday).add(const Duration(days: 6)));

    // Render (persist) the week → 7 materialized rows.
    service.renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to);
    expect(_rowsFor(db, jobId, monday, to), 7);

    // DELETE Monday's shift via the override log.
    final mon = service
        .renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to)
        .occurrences
        .firstWhere((o) => o.shiftDate == monday);
    service.applyOverride(
      Override(
        id: service.newOverrideId(mon.id),
        occurrenceId: mon.id,
        operation: OverrideOperation.delete,
        createdAt: ScheduleService.nowIso(),
      ),
      jobId: jobId,
    );

    // Re-render → the effective list is 6 rows AND the stale row is gone
    // from the table (A3: no stale occurrence readable as current).
    final r = service.renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to);
    expect(r.occurrences, hasLength(6));
    expect(r.occurrences.any((o) => o.shiftDate == monday), isFalse);
    expect(_rowsFor(db, jobId, monday, to), 6,
        reason: 'A3: deleted day must not keep a materialized row');

    // Re-render again + a second service (restart) — still 6, no resurrection.
    service.renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to);
    expect(_rowsFor(db, jobId, monday, to), 6);
    db.close();
  });

  test('import suppression removes the covered pattern projection row', () {
    final db = openInMemory();
    final service = _service(db);
    final monday = _mondayIso();
    final jobId = _seedDaily(service, monday);
    final to = _iso(DateTime.parse(monday).add(const Duration(days: 6)));

    service.renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to);
    expect(_rowsFor(db, jobId, monday, to), 7);

    // Commit a roster marking Monday OFF and Tue a shift — the roster is
    // authoritative for those days (plan7 D-M2-1 A).
    final parsed = service.parsePaste(
      jobId: jobId,
      rawText: '$monday OFF\n$_iso(DateTime.parse(monday).add(const Duration(days: 1))) Day 07:00-19:00',
      referenceDate: monday,
    );
    final reviewed = applyReview(parsed, action: ReviewAction.bulkAcceptAllHigh);
    final result = service.commitRoster(session: reviewed, jobId: jobId);
    expect(result.error, isNull);

    final r = service.renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to);
    // 7 pattern days, minus Monday (suppressed OFF), minus Tue (suppressed by
    // the imported shift) + 1 imported row = 6 effective rows.
    expect(r.occurrences, hasLength(6));
    expect(r.occurrences.any((o) => o.shiftDate == monday), isFalse);
    expect(_rowsFor(db, jobId, monday, to), 6,
        reason: 'A3: pattern projection for covered days must not stay stale');
    db.close();
  });

  test('restart does not resurrect a stale row', () {
    final dir = Directory.systemTemp.createTempSync('shiftease_a3_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final dbPath = '${dir.path}/a3.db';
    final db = openDatabase(opener: defaultOpener, path: dbPath, key: kTestDbKey);
    final service = _service(db);
    final monday = _mondayIso();
    final jobId = _seedDaily(service, monday);
    final to = _iso(DateTime.parse(monday).add(const Duration(days: 6)));

    service.renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to);
    final mon = service
        .renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to)
        .occurrences
        .firstWhere((o) => o.shiftDate == monday);
    service.applyOverride(
      Override(
        id: service.newOverrideId(mon.id),
        occurrenceId: mon.id,
        operation: OverrideOperation.delete,
        createdAt: ScheduleService.nowIso(),
      ),
      jobId: jobId,
    );
    service.renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to);

    // Restart: new service on the same file db.
    db.close();
    final db2 = openDatabase(opener: defaultOpener, path: dbPath, key: kTestDbKey);
    final service2 = _service(db2);
    final r = service2.renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to);
    expect(r.occurrences, hasLength(6));
    expect(r.occurrences.any((o) => o.shiftDate == monday), isFalse);
    expect(_rowsFor(db2, jobId, monday, to), 6,
        reason: 'A3: restart must not resurrect the deleted row');
    db2.close();
  });

  test('an INVARIANT-006 pay snapshot on a still-effective row survives the '
      'cache replace', () {
    final db = openInMemory();
    final service = _service(db);
    final monday = _mondayIso();
    final jobId = _seedDaily(service, monday);
    final to = _iso(DateTime.parse(monday).add(const Duration(days: 6)));

    service.renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to);
    final occ = service
        .renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to)
        .occurrences
        .first;
    ScheduleRepository(db, PatternRepository(db)).setPayEstimateSnapshot(
      occurrenceId: occ.id,
      amount: 210.0,
      payRuleFrom: '2020-01-01',
    );

    // Re-render the same range — the row stays effective, the DELETE keeps it
    // (id in the projection) and the upsert must NOT clobber the snapshot.
    service.renderJob(jobId: jobId, rangeStart: monday, rangeEnd: to);
    final row = db.select(
        'SELECT actualPayEstimate FROM occurrences WHERE id = ?', [occ.id])
        .first;
    expect(row['actualPayEstimate'], 210.0,
        reason: 'A3 + INVARIANT-006: snapshot survives the cache replace');
    db.close();
  });
}