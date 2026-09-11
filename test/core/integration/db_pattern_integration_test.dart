// =============================================================================
// Persistence (SQLite) <-> Pattern Engine integration (version boundary).
// =============================================================================
//
// What this file proves end-to-end (no hand-fed numbers):
//   1. A date range spanning a VERSION BOUNDARY renders from BOTH versions —
//      each date's occurrences come from the version active on that date, the
//      old version's window is clipped at effectiveUntil, the new version's
//      starts at effectiveFrom, with NO gap and NO duplicate at the seam.
//   2. D9 phase continuity through the DB: the new version keeps the original
//      anchorDate, so occurrence weekdays continue seamlessly across the
//      boundary (projectOccurrences anchors to anchorDate, not rangeStart).
//   3. Occurrences BEFORE the boundary are unchanged by the version change
//      (INVARIANT-001) — same deterministic ids, same template, same UTC —
//      and overrides targeting them still replay after the change.
//   4. All SIX override operations (UPDATE / DELETE / REPLACE / SPLIT / SWAP
//      / CREATE) plus a chained update onto a split part survive a
//      restart-equivalent re-render: the DB final occurrence set matches the
//      pure-engine replay over the same baseline and log, byte for byte.
//
// Arithmetic of every scenario is closed-form and independently checkable.
// =============================================================================

import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/pattern/pattern_engine.dart';

void main() {
  tz.initializeTimeZones();

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

  /// Mon/Wed/Fri 12h pattern (07:00-19:00 UTC) anchored on a Monday.
  ShiftPattern monWedFri(String id, {String template = 'st-day'}) =>
      ShiftPattern(
        id: id,
        jobId: 'job-1',
        name: id,
        type: 'FIXED_CYCLE',
        cycleLengthDays: 7,
        sequence: [template, null, template, null, template, null, null],
        anchorDate: '2026-09-07', // Monday
        defaultTimezone: 'UTC',
        effectiveFrom: '2026-01-01',
      );

  Map<String, ShiftTemplate> tmapOf(List<ShiftTemplate> ts) =>
      {for (final t in ts) t.id: t};

  test('version boundary: render spans two versions with D9 phase continuity '
      '(no gap, no duplicate, old days unchanged)', () {
    final db = dblib.openInMemory();
    final pat = PatternRepository(db);
    final sched = ScheduleRepository(db, pat);

    // v1: Mon/Wed/Fri 07:00-19:00 UTC from 2026-01-01.
    pat.savePattern(
      jobId: 'job-1',
      pattern: monWedFri('pat-v1'),
      templates: [tmpl('st-day')],
    );
    // Baseline under v1 only (before the change).
    final v1Render = sched.renderJobSchedule(
        jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
    expect(v1Render.issues, isEmpty);
    expect(v1Render.occurrences.length, 3); // Mon 07 / Wed 09 / Fri 11

    // D9: version change happens MID-CYCLE on 2026-09-16 (a WEDNESDAY) — the
    // new version keeps the ORIGINAL anchor (Mon 09-07), so its sequence
    // slots continue the OLD phase. If the anchor were (wrongly) reset to the
    // effectiveFrom (Wed 09-16), the v2 workdays would shift to a different
    // weekday set — the assertions below discriminate.
    final (closedV1, v2) = createNewVersion(
      currentPattern: pat.patternsForJob('job-1').single,
      newEffectiveFrom: '2026-09-16',
      newName: 'v2',
      newCycleLengthDays: 7,
      newSequence: ['st-day2', null, 'st-day2', null, 'st-day2', null, null],
    );
    expect(v2.id, isNot(closedV1.id), reason: 'new version gets its own id');
    expect(v2.anchorDate, '2026-09-07', reason: 'D9 keeps the original anchor');
    pat.savePattern(
        jobId: 'job-1', pattern: closedV1, templates: [tmpl('st-day')]);
    pat.savePattern(
        jobId: 'job-1',
        pattern: v2,
        templates: [tmpl('st-day'), tmpl('st-day2', end: '21:00')]);
    // v2's template list must be available at render time.
    pat.saveTemplate(jobId: 'job-1', t: tmpl('st-day2', end: '21:00'));

    // Render the FULL boundary range 09-07..09-22 in one shot.
    final boundary = sched.renderJobSchedule(
        jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-22');
    expect(boundary.issues, isEmpty);
    // v1 window 09-07..09-15: Mon 07, Wed 09, Fri 11, Mon 14 (st-day, 12h).
    // v2 window 09-16..09-22 KEEPS the Mon-anchored phase (09-07 anchor):
    // Wed 16 (slot 2), Fri 18 (slot 4), Mon 21 (slot 0) — st-day2, 14h.
    // If v2's anchor were reset to 09-16, slot 0 would be Wed 16 and the
    // Fri-18 / Mon-21 shifts would NOT exist.
    final byDate = {
      for (final o in boundary.occurrences) o.shiftDate: o,
    };
    expect(byDate.keys.toSet(), {
      '2026-09-07', '2026-09-09', '2026-09-11', '2026-09-14', // v1
      '2026-09-16', '2026-09-18', '2026-09-21', // v2
    });
    for (final d in ['2026-09-07', '2026-09-09', '2026-09-11', '2026-09-14']) {
      expect(byDate[d]!.templateId, 'st-day');
      // 07:00-19:00 UTC = exactly 12h.
      expect(
          DateTime.parse(byDate[d]!.endDateTimeUtc)
                  .difference(DateTime.parse(byDate[d]!.startDateTimeUtc))
                  .inHours,
          12);
    }
    for (final d in ['2026-09-16', '2026-09-18', '2026-09-21']) {
      expect(byDate[d]!.templateId, 'st-day2');
      expect(
          DateTime.parse(byDate[d]!.endDateTimeUtc)
                  .difference(DateTime.parse(byDate[d]!.startDateTimeUtc))
                  .inHours,
          14);
    }

    // INVARIANT-001: the v1-only days are UNCHANGED by the version change —
    // same deterministic ids and same UTC as the earlier v1-only render.
    for (final o in v1Render.occurrences) {
      final after = byDate[o.shiftDate]!;
      expect(after.id, o.id);
      expect(after.startDateTimeUtc, o.startDateTimeUtc);
      expect(after.endDateTimeUtc, o.endDateTimeUtc);
      expect(after.templateId, 'st-day');
    }
    db.close();
  });

  test('override targeting a pre-boundary occurrence survives the version '
      'change; a new-version day is untouched', () {
    final db = dblib.openInMemory();
    final pat = PatternRepository(db);
    final sched = ScheduleRepository(db, pat);
    pat.savePattern(
        jobId: 'job-1', pattern: monWedFri('pat-ovb'), templates: [tmpl('st-day')]);
    sched.renderJobSchedule(
        jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
    final preChange = sched.occurrencesInRange(
        patternId: 'pat-ovb', from: '2026-09-07', to: '2026-09-13');
    final mon7 =
        preChange.firstWhere((o) => o.shiftDate == '2026-09-07').id;

    // User edits Mon 09-07 (09:00-17:00) — recorded as an override BEFORE the
    // version change happens.
    sched.saveOverride(Override(
      id: 'ovr-before-change',
      occurrenceId: mon7,
      operation: OverrideOperation.update,
      createdAt: '2026-09-10T00:00:00.000Z',
      updatePayload: const UpdatePayload(startTime: '09:00', endTime: '17:00'),
    ));

    // Now the roster changes from 2026-09-14 (same anchor — D9).
    final (closedV1, v2) = createNewVersion(
      currentPattern: pat.patternsForJob('job-1').single,
      newEffectiveFrom: '2026-09-14',
      newName: 'v2',
      newCycleLengthDays: 7,
      newSequence: ['st-day2', null, 'st-day2', null, 'st-day2', null, null],
    );
    pat.savePattern(jobId: 'job-1', pattern: closedV1, templates: [tmpl('st-day')]);
    pat.savePattern(
        jobId: 'job-1',
        pattern: v2,
        templates: [tmpl('st-day2', end: '21:00')]);

    final rendered = sched.renderJobSchedule(
        jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-20');
    expect(rendered.issues, isEmpty);
    final mon = rendered.occurrences
        .firstWhere((o) => o.shiftDate == '2026-09-07');
    // The pre-boundary override is STILL applied after the version change.
    expect(mon.startDateTimeUtc, '2026-09-07T09:00:00.000Z');
    expect(mon.endDateTimeUtc, '2026-09-07T17:00:00.000Z');
    // And a post-change v2 day renders untouched by any v1-era override.
    final mon14 =
        rendered.occurrences.firstWhere((o) => o.shiftDate == '2026-09-14');
    expect(mon14.startDateTimeUtc, '2026-09-14T07:00:00.000Z');
    expect(mon14.endDateTimeUtc, '2026-09-14T21:00:00.000Z');
    db.close();
  });

  test('all six override ops + chained split-part update replay through the '
      'DB identically to the pure engine', () {
    final db = dblib.openInMemory();
    final pat = PatternRepository(db);
    final sched = ScheduleRepository(db, pat);

    // Daily pattern so every op sits on its own day without interference:
    //   Mon UPDATE | Tue<->Thu SWAP | Wed SPLIT+chain | Fri REPLACE |
    //   Sat CREATE | Sun DELETE
    pat.savePattern(
      jobId: 'job-1',
      pattern: ShiftPattern(
        id: 'pat-6op',
        jobId: 'job-1',
        name: '6op',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 7,
        sequence: List.filled(7, 'st-day'),
        anchorDate: '2026-09-07',
        defaultTimezone: 'UTC',
        effectiveFrom: '2026-01-01',
      ),
      templates: [
        tmpl('st-day'),
        tmpl('st-night', start: '19:00', end: '07:00+1'),
      ],
    );
    final tmap = tmapOf(pat.templatesForJob('job-1'));
    sched.renderJobSchedule(
        jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
    final week = sched.occurrencesInRange(
        patternId: 'pat-6op', from: '2026-09-07', to: '2026-09-13');
    String idOf(String d) => week.firstWhere((o) => o.shiftDate == d).id;
    final mon = idOf('2026-09-07');
    final tue = idOf('2026-09-08');
    final wed = idOf('2026-09-09');
    final thu = idOf('2026-09-10');
    final sun = idOf('2026-09-13');

    // Official CREATE convention (saveOverride patternId): the created
    // occurrence's id IS the override id, so occurrenceId = its own id; the
    // pattern whose schedule it edits is passed to saveOverride as patternId.
    final ops = <Override>[
      // (1) UPDATE Monday 07-19 -> 09-17.
      Override(
          id: 'op-upd',
          occurrenceId: mon,
          operation: OverrideOperation.update,
          createdAt: '2026-09-01T00:00:00.000Z',
          updatePayload:
              const UpdatePayload(startTime: '09:00', endTime: '17:00')),
      // (2) DELETE Sunday entirely.
      Override(
          id: 'op-del',
          occurrenceId: sun,
          operation: OverrideOperation.delete,
          createdAt: '2026-09-01T01:00:00.000Z'),
      // (3) SPLIT Wednesday 07-19 into 07-13 + 13-19.
      Override(
          id: 'op-split',
          occurrenceId: wed,
          operation: OverrideOperation.split,
          createdAt: '2026-09-01T02:00:00.000Z',
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
          ])),
      // (4) chain UPDATE onto split part #p1 (13-19 -> 14-19).
      Override(
          id: 'op-upd-part',
          occurrenceId: '$wed#p1',
          operation: OverrideOperation.update,
          createdAt: '2026-09-01T03:00:00.000Z',
          updatePayload: const UpdatePayload(startTime: '14:00')),
      // (5) REPLACE part #p0's template day -> night; overrideTime keeps the
      // window (D3: overrideTime wins over the new template's default).
      Override(
          id: 'op-repl',
          occurrenceId: '$wed#p0',
          operation: OverrideOperation.replace,
          createdAt: '2026-09-01T04:00:00.000Z',
          replacePayload: const ReplacePayload(
            newTemplateId: 'st-night',
            overrideTime: ReplaceTime(startTime: '07:00', endTime: '13:00'),
          )),
      // (6) SWAP Tuesday <-> Thursday: both st-day 07-19 UTC, same job, same
      // timezone (D5). Each keeps its id; local civil intent travels to the
      // other's date.
      Override(
          id: 'op-swap',
          occurrenceId: tue,
          operation: OverrideOperation.swap,
          swapWithOccurrenceId: thu,
          createdAt: '2026-09-01T05:00:00.000Z'),
      // (7) CREATE an extra hand-typed shift on Saturday 10-16.
      Override(
          id: 'op-create',
          occurrenceId: 'op-create', // official: created id = override id
          operation: OverrideOperation.create,
          createdAt: '2026-09-01T06:00:00.000Z',
          createPayload: const CreatePayload(
            date: '2026-09-12',
            templateId: 'st-day',
            startTime: '10:00',
            endTime: '16:00',
            timezone: 'UTC',
          )),
    ];
    for (final o in ops) {
      sched.saveOverride(o,
          patternId: o.operation == OverrideOperation.create
              ? 'pat-6op'
              : null);
    }

    // Pure-engine reference replay (same baseline, same log order).
    var pureList = List<ShiftOccurrence>.from(week);
    final pureIssues = <RenderIssue>[];
    for (final o in ops) {
      final r = applyOverride(pureList, o, templates: tmap);
      if (r.isSuccess) {
        pureList = r.occurrences;
      } else {
        pureIssues.addAll(r.issues);
      }
    }
    expect(pureIssues, isEmpty,
        reason: 'pure replay of the op chain must succeed: '
            '${pureIssues.map((i) => i.code).toList()}');

    // DB restart-equivalent re-render.
    final rendered = sched.renderJobSchedule(
        jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
    expect(rendered.issues, isEmpty,
        reason: 'DB re-render must not lose ops: '
            '${rendered.issues.map((i) => i.code).toList()}');

    final dbById = {for (final o in rendered.occurrences) o.id: o};
    final pureById = {for (final o in pureList) o.id: o};
    expect(dbById.keys.toSet(), pureById.keys.toSet(),
        reason: 'DB replay must produce the same occurrence set as the pure '
            'engine (all 6 ops + chain must survive)');
    for (final id in pureById.keys) {
      expect(dbById[id]!.startDateTimeUtc, pureById[id]!.startDateTimeUtc,
          reason: 'UTC parity for $id');
      expect(dbById[id]!.endDateTimeUtc, pureById[id]!.endDateTimeUtc,
          reason: 'UTC parity for $id');
      expect(dbById[id]!.templateId, pureById[id]!.templateId,
          reason: 'template parity for $id');
      expect(dbById[id]!.shiftDate, pureById[id]!.shiftDate,
          reason: 'date parity for $id');
    }

    // Spot-checks of each operation's survivor:
    // (1) Monday moved to 09:00-17:00.
    expect(dbById[mon]!.startDateTimeUtc, '2026-09-07T09:00:00.000Z');
    // (2) Sunday deleted.
    expect(dbById.containsKey(sun), isFalse);
    // (3+4) split parts present; #p1 chained to 14:00.
    expect(dbById['$wed#p0']!.templateId, 'st-night'); // (5) replaced
    expect(dbById['$wed#p1']!.startDateTimeUtc, '2026-09-09T14:00:00.000Z');
    // (6) SWAP: Tue's occurrence now carries Thu's date (and vice versa) —
    // ids kept, dates exchanged.
    expect(dbById[tue]!.shiftDate, '2026-09-10');
    expect(dbById[thu]!.shiftDate, '2026-09-08');
    // (7) CREATE: extra Saturday shift exists under the override's id.
    final created = dbById['op-create'];
    expect(created, isNotNull);
    expect(created!.shiftDate, '2026-09-12');
    expect(created.startDateTimeUtc, '2026-09-12T10:00:00.000Z');
    expect(created.endDateTimeUtc, '2026-09-12T16:00:00.000Z');
    db.close();
  });

  test('official CREATE convention: OFF-day create survives ANY render range '
      'containing its date (not anchored to a baseline root)', () {
    final db = dblib.openInMemory();
    final pat = PatternRepository(db);
    final sched = ScheduleRepository(db, pat);
    pat.savePattern(
        jobId: 'job-1', pattern: monWedFri('pat-off'), templates: [tmpl('st-day')]);
    sched.renderJobSchedule(
        jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
    expect(sched
            .occurrencesInRange(
                patternId: 'pat-off', from: '2026-09-07', to: '2026-09-13')
            .where((o) => o.shiftDate == '2026-09-08'),
        isEmpty,
        reason: 'Tue 09-08 is an OFF day — no baseline occurrence');

    // UI adds a hand-typed shift on the OFF day Tue 09-08. occurrenceId is
    // its own (created) id; patternId names the pattern being edited.
    sched.saveOverride(
      Override(
        id: 'op-tue-extra',
        occurrenceId: 'op-tue-extra',
        operation: OverrideOperation.create,
        createdAt: '2026-09-01T04:00:00.000Z',
        createPayload: const CreatePayload(
          date: '2026-09-08',
          templateId: 'st-day',
          startTime: '10:00',
          endTime: '16:00',
          timezone: 'UTC',
        ),
      ),
      patternId: 'pat-off',
    );

    // Full week render: present.
    final full = sched.renderJobSchedule(
        jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
    expect(full.issues, isEmpty);
    expect(full.occurrences.where((o) => o.shiftDate == '2026-09-08').single.id,
        'op-tue-extra');

    // Sub-range that STARTS on the created day (Tue 09-08) and EXCLUDES the
    // Monday baseline: the created shift MUST still appear. (The pre-fix
    // root-based convention lost it silently — regression.)
    final sub = sched.renderJobSchedule(
        jobId: 'job-1', rangeStart: '2026-09-08', rangeEnd: '2026-09-13');
    expect(sub.issues, isEmpty);
    expect(sub.occurrences.where((o) => o.shiftDate == '2026-09-08').single.id,
        'op-tue-extra',
        reason: 'CREATE on an OFF day must not depend on which baseline '
            'occurrences share the render range');

    // A render that does NOT include Tue 09-08 must NOT drag it in.
    final later = sched.renderJobSchedule(
        jobId: 'job-1', rangeStart: '2026-09-14', rangeEnd: '2026-09-20');
    expect(later.occurrences.where((o) => o.shiftDate == '2026-09-08'), isEmpty);
    // And saveOverride REFUSES a CREATE without patternId (official API).
    expect(
        () => sched.saveOverride(Override(
          id: 'op-bad',
          occurrenceId: 'op-bad',
          operation: OverrideOperation.create,
          createdAt: '2026-09-01T05:00:00.000Z',
          createPayload: const CreatePayload(
            date: '2026-09-09',
            templateId: 'st-day',
            startTime: '10:00',
            endTime: '16:00',
            timezone: 'UTC',
          ),
        )),
        throwsA(isA<ArgumentError>()),
        reason: 'CREATE without patternId is refused loudly, never silent');
    db.close();
  });

  test('job isolation: a CREATE on job-2 does not leak into a job-1 render',
      () {
    final db = dblib.openInMemory();
    final pat = PatternRepository(db);
    final sched = ScheduleRepository(db, pat);
    // job-1 Mon/Wed/Fri.
    pat.savePattern(
        jobId: 'job-1', pattern: monWedFri('pat-j1'), templates: [tmpl('st-day')]);
    // job-2 different pattern id + template.
    pat.savePattern(
        jobId: 'job-2',
        pattern: ShiftPattern(
          id: 'pat-j2',
          jobId: 'job-2',
          name: 'j2',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          sequence: List.filled(7, 'st-day-j2'),
          anchorDate: '2026-09-07',
          defaultTimezone: 'UTC',
          effectiveFrom: '2026-01-01',
        ),
        templates: [
          tmpl('st-day-j2'),
        ],
      );
    sched.renderJobSchedule(
        jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
    sched.renderJobSchedule(
        jobId: 'job-2', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');

    // A hand-typed shift on job-2's pattern only.
    sched.saveOverride(
      Override(
        id: 'op-j2',
        occurrenceId: 'op-j2',
        operation: OverrideOperation.create,
        createdAt: '2026-09-01T04:00:00.000Z',
        createPayload: const CreatePayload(
          date: '2026-09-09',
          templateId: 'st-day-j2',
          startTime: '10:00',
          endTime: '16:00',
          timezone: 'UTC',
        ),
      ),
      patternId: 'pat-j2',
    );

    // Rendering job-1 must NOT include job-2's created shift.
    final j1 = sched.renderJobSchedule(
        jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
    expect(j1.occurrences.where((o) => o.id == 'op-j2'), isEmpty,
        reason: 'job-1 render must not see job-2 CREATE (patternId scoping)');
    // Rendering job-2 DOES include it.
    final j2 = sched.renderJobSchedule(
        jobId: 'job-2', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
    expect(j2.occurrences.where((o) => o.id == 'op-j2').single.shiftDate,
        '2026-09-09');
    db.close();
  });
}
