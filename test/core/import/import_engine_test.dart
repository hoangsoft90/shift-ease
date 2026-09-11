// =============================================================================
// ShiftEase Import Pipeline — Golden Test Suite Runner (IMPORT-001..008)
// =============================================================================
//
// Reads test/golden/import_pipeline_cases.json and drives the Import Engine
// against every case — no hard-coded expectations (single source of truth).
//
// Golden authoring fixes (documented in the JSON notes; both were needed to
// make the goldens describe reality):
//   - IMPORT-002: one LOW candidate per input line (3 total), not 1.
//   - IMPORT-003: commit candidates carry real date/times so UTC resolution
//     via core/time is actually exercised.
//
// The referenceDate anchors ambiguous dates; the goldens were authored around
// September 2026, so the runner passes '2026-09-01' (the UI's "roster for
// which period?" answer) unless the JSON input overrides it.
//
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:shiftease/core/import/import_types.dart';
import 'package:shiftease/core/import/import_engine.dart';
import 'package:shiftease/core/import/import_parser.dart';

List<Map<String, dynamic>> loadGoldenCases() {
  final candidates = [
    'test/golden/import_pipeline_cases.json',
    '../test/golden/import_pipeline_cases.json',
    '../../test/golden/import_pipeline_cases.json',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return (data['cases'] as List)
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList();
    }
  }
  throw FileSystemException('Could not find import_pipeline_cases.json');
}

Map<String, dynamic> caseById(List<Map<String, dynamic>> cases, String id) =>
    cases.firstWhere((c) => c['id'] == id);

List<TemplateSpec> templatesOf(Map<String, dynamic> input) {
  final raw = (input['existingTemplates'] as List? ?? const []);
  return raw.map((t) {
    final m = Map<String, dynamic>.from(t as Map);
    return TemplateSpec(
      id: m['id'] as String,
      name: m['name'] as String,
      startTime: m['startTime'] as String,
      endTime: m['endTime'] as String,
    );
  }).toList();
}

String referenceOf(Map<String, dynamic> input) =>
    input['referenceDate'] as String? ?? '2026-09-01';

CandidateShift parseCandidate(Map<String, dynamic> json) {
  // Candidate data may be nested under 'data' (IMPORT-008-style ids only) or
  // flattened at the top level (IMPORT-003 'shiftDate'/'startTime'/...).
  final nested = json['data'] as Map?;
  final d = nested == null
      ? json
      : {...json, ...Map<String, dynamic>.from(nested)};
  final date = d['date'] as String? ?? d['shiftDate'] as String?;
  final kindRaw = (d['shiftType'] as String? ?? '').toLowerCase();
  final hasTimes = d['startTime'] != null && d['endTime'] != null;
  return CandidateShift(
    id: json['id'] as String? ?? '?',
    data: CandidateData(
      date: date,
      templateId: d['templateId'] as String?,
      startTime: d['startTime'] as String?,
      endTime: d['endTime'] as String?,
      shiftType: d['shiftType'] as String?,
      kind: kindRaw == 'off'
          ? ShiftKind.off
          : (hasTimes ? ShiftKind.shift : ShiftKind.unknown),
    ),
    confidence: Confidence.fromName(json['confidence'] as String),
    reviewStatus: ReviewStatus.fromName(json['reviewStatus'] as String),
  );
}

void expectCandidateMatches(
  CandidateShift actual,
  Map<String, dynamic> expected, {
  required String caseId,
}) {
  final ed = Map<String, dynamic>.from(expected['data'] as Map);
  expect(actual.id, expected['id'], reason: '$caseId candidate id');
  expect(actual.confidence, Confidence.fromName(expected['confidence'] as String),
      reason: '$caseId ${actual.id} confidence');
  expect(actual.reviewStatus,
      ReviewStatus.fromName(expected['reviewStatus'] as String),
      reason: '$caseId ${actual.id} reviewStatus');
  expect(actual.data.date, ed['date'], reason: '$caseId ${actual.id} date');
  expect(actual.data.templateId, ed['templateId'],
      reason: '$caseId ${actual.id} templateId');
  expect(actual.data.startTime, ed['startTime'],
      reason: '$caseId ${actual.id} startTime');
  expect(actual.data.endTime, ed['endTime'],
      reason: '$caseId ${actual.id} endTime');
  expect(actual.data.shiftType, ed['shiftType'],
      reason: '$caseId ${actual.id} shiftType');
}

void main() {
  tz.initializeTimeZones();
  final cases = loadGoldenCases();
  print('Import golden suite: ${cases.length} cases');

  List<String> stateNames(List<ImportState> history) =>
      history.map((s) => s.name).toList();

  // -------------------------------------------------------------------------
  // IMPORT-001 / 002 / 006 — PASTE_TEXT interpretation.
  // -------------------------------------------------------------------------
  group('PASTE_TEXT interpretation (golden)', () {
    test('IMPORT-001: clean paste -> 3 HIGH candidates, none committed', () {
      final c = caseById(cases, 'IMPORT-001');
      final input = Map<String, dynamic>.from(c['input'] as Map);
      final session = parseDocument(
        sourceType: ImportSourceType.pasteText,
        rawText: input['rawText'] as String,
        templates: templatesOf(input),
        referenceDate: referenceOf(input),
        timezone: input['jobTimezone'] as String,
        id: 'session-import-001',
      );
      expect(stateNames(session.history),
          ['idle', 'parsing', 'extracted']);
      expect(session.state, ImportState.extracted);
      expect(session.candidates.length, 3);

      final expected = (c['expected']['candidates'] as List).cast<Map>();
      for (var i = 0; i < 3; i++) {
        expectCandidateMatches(session.candidates[i],
            Map<String, dynamic>.from(expected[i]),
            caseId: 'IMPORT-001');
      }
      // INVARIANT-004: everything is PENDING — nothing auto-committed.
      expect(session.committedOccurrenceIds, isEmpty);
      expect(
          session.candidates.every(
              (x) => x.reviewStatus == ReviewStatus.pending),
          isTrue);
    });

    test('IMPORT-002: ambiguous input -> 3 LOW candidates, nothing committed',
        () {
      final c = caseById(cases, 'IMPORT-002');
      final input = Map<String, dynamic>.from(c['input'] as Map);
      final session = parseDocument(
        sourceType: ImportSourceType.pasteText,
        rawText: input['rawText'] as String,
        templates: templatesOf(input),
        referenceDate: referenceOf(input),
        timezone: input['jobTimezone'] as String,
        id: 'session-import-002',
      );
      expect(session.candidates.length, 3,
          reason: 'one candidate per input line');
      final expected = (c['expected']['candidates'] as List).cast<Map>();
      for (var i = 0; i < 3; i++) {
        expectCandidateMatches(session.candidates[i],
            Map<String, dynamic>.from(expected[i]),
            caseId: 'IMPORT-002');
        expect(session.candidates[i].confidence, Confidence.low);
        expect(session.candidates[i].data.date, isNull);
        expect(session.candidates[i].reviewStatus, ReviewStatus.pending);
      }
      expect(session.committedOccurrenceIds, isEmpty);
    });

    test('IMPORT-006: time matches template but no label -> MEDIUM', () {
      final c = caseById(cases, 'IMPORT-006');
      final input = Map<String, dynamic>.from(c['input'] as Map);
      final session = parseDocument(
        sourceType: ImportSourceType.pasteText,
        rawText: input['rawText'] as String,
        templates: templatesOf(input),
        referenceDate: referenceOf(input),
        timezone: input['jobTimezone'] as String,
        id: 'session-import-006',
      );
      expect(session.candidates.length, 2);
      final expected = (c['expected']['candidates'] as List).cast<Map>();
      for (var i = 0; i < 2; i++) {
        final cand = session.candidates[i];
        expectCandidateMatches(cand,
            Map<String, dynamic>.from(expected[i]),
            caseId: 'IMPORT-006');
        expect(cand.confidence, Confidence.medium);
        expect(cand.data.templateId, isNotNull);
      }
      expect(session.committedOccurrenceIds, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // IMPORT-004 / 007 — CSV.
  // -------------------------------------------------------------------------
  group('CSV import (golden)', () {
    test('IMPORT-004: column mapping -> 3 HIGH candidates', () {
      final c = caseById(cases, 'IMPORT-004');
      final input = Map<String, dynamic>.from(c['input'] as Map);
      final session = parseDocument(
        sourceType: ImportSourceType.csv,
        rawCsv: input['rawCsv'] as String,
        columnMapping: (input['columnMapping'] as Map)
            .map((k, v) => MapEntry(k as String, v as String)),
        templates: const [],
        referenceDate: referenceOf(input),
        timezone: input['jobTimezone'] as String,
        id: 'session-import-004',
      );
      expect(session.state, ImportState.extracted);
      expect(session.candidates.length, 3);
      expect(
          session.candidates.every((x) => x.confidence == Confidence.high),
          isTrue,
          reason: 'ISO dates + clear mapping = HIGH');
      // The Off row is an OFF day with no occurrence material.
      final off = session.candidates.last;
      expect(off.data.kind, ShiftKind.off);
      expect(off.data.date, '2026-09-05');
    });

    test('D-2: CSV unknown-marker "?" is NOT a type label (never HIGH)', () {
      final session = parseDocument(
        sourceType: ImportSourceType.csv,
        rawCsv: 'Date,Shift,Start,End\n'
            '2026-09-03,?,07:00,19:00\n'
            '2026-09-04,Day,07:00,19:00',
        templates: const [TemplateSpec(
            id: 't', name: 'Day', startTime: '07:00', endTime: '19:00')],
        referenceDate: '2026-09-01',
        timezone: 'UTC',
        id: 's-d2',
      );
      // '?' is not a stated type: the first row must NOT be HIGH (the D-2 bug
      // would have made it HIGH like a stated label). With an exact template
      // time match the type is INFERRED -> MEDIUM, exactly like IMPORT-006's
      // no-label principle — the user confirms before any bulk accept.
      expect(session.candidates[0].confidence, Confidence.medium);
      expect(session.candidates[0].reviewStatus, ReviewStatus.pending);
      expect(session.candidates[0].data.templateId, 't');
      // Stated Day stays HIGH.
      expect(session.candidates[1].confidence, Confidence.high);
    });

    test('IMPORT-007: garbage CSV -> PARSE_FAILED, recoverable error', () {
      final c = caseById(cases, 'IMPORT-007');
      final input = Map<String, dynamic>.from(c['input'] as Map);
      final session = parseDocument(
        sourceType: ImportSourceType.csv,
        rawCsv: input['rawCsv'] as String,
        templates: const [],
        referenceDate: '2026-09-01',
        timezone: 'America/New_York',
        id: 'session-import-007',
      );
      expect(session.state, ImportState.error);
      expect(stateNames(session.history), ['idle', 'parsing', 'error']);
      expect(session.error?.code, ImportErrorCodes.parseFailed);
      expect(session.error?.recoverable, isTrue);
      expect(session.committedOccurrenceIds, isEmpty);
    });

    test('CSV whose header has NO recognizable columns fails with '
        'PARSE_FAILED even when data rows exist (no all-null LOW guesses)',
        () {
      // Header cells match no known synonym — without this guard the rows
      // below would have parsed into all-null LOW candidates the user would
      // have to guess from. The parser must refuse loudly instead.
      final session = parseDocument(
        sourceType: ImportSourceType.csv,
        rawCsv: 'frobnicate,flurb,whiz,zoom\n'
            '2026-09-03,Day,07:00,19:00\n'
            '2026-09-04,Day,07:00,19:00',
        templates: const [TemplateSpec(
            id: 't', name: 'Day', startTime: '07:00', endTime: '19:00')],
        referenceDate: '2026-09-01',
        timezone: 'UTC',
        id: 's-nocols',
      );
      expect(session.state, ImportState.error);
      expect(stateNames(session.history), ['idle', 'parsing', 'error']);
      expect(session.error?.code, ImportErrorCodes.parseFailed);
      expect(session.error?.recoverable, isTrue);
      expect(session.candidates, isEmpty,
          reason: 'garbage columns must not become guessable LOW rows');
      expect(session.committedOccurrenceIds, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // IMPORT-003 — review actions + commit (INVARIANT-004 + INVARIANT-002).
  // -------------------------------------------------------------------------
  group('Review + commit (golden)', () {
    ImportSession reviewingSessionFrom(Map<String, dynamic> input) {
      final candidates = (input['candidatesFromImport001'] as List)
          .map((c) => parseCandidate(Map<String, dynamic>.from(c as Map)))
          .toList();
      return ImportSession(
        id: 'session-import-003',
        createdAt: '2026-09-01T08:00:00Z',
        sourceType: ImportSourceType.pasteText,
        state: ImportState.extracted,
        referenceDate: '2026-09-01',
        timezone: input['jobTimezone'] as String,
        rawExtraction:
            RawExtraction(sourceType: ImportSourceType.pasteText, entries: const []),
        candidates: candidates,
        committedOccurrenceIds: const [],
      );
    }

    test('IMPORT-003: APPROVE/APPROVE/REJECT + COMMIT -> 2 occurrences', () {
      final c = caseById(cases, 'IMPORT-003');
      final input = Map<String, dynamic>.from(c['input'] as Map);
      final actions = (input['userActions'] as List).cast<Map>();

      var session = reviewingSessionFrom(input);
      for (final a in actions) {
        if (a['action'] == 'COMMIT') continue; // commit is the explicit step
        final action = ReviewAction.fromName(a['action'] as String);
        session = applyReview(
          session,
          candidateId: a['candidateId'] as String?,
          action: action,
        );
      }
      expect(session.state, ImportState.reviewing);
      expect(stateNames(session.history), contains('reviewing'));

      final commit = commitImport(session);
      expect(commit.error, isNull, reason: commit.error?.message);
      expect(commit.session.state, ImportState.committed);
      expect(stateNames(commit.session.history),
          containsAll(['reviewing', 'committed']));

      // cand-1 + cand-2 committed; cand-3 (REJECTED Off) never materialized.
      expect(commit.shifts.length, 2);
      expect(commit.shifts.map((s) => s.occurrenceId).toSet(),
          {'occ-cand-1', 'occ-cand-2'});
      expect(commit.session.committedOccurrenceIds,
          ['occ-cand-1', 'occ-cand-2']);
      expect(commit.committedOffDates, isEmpty);

      // INVARIANT-002: UTC resolved from local time + timezone (NY, Sep = EDT,
      // UTC-4): cand-1 07:00 -> 11:00Z; cand-2 19:00 -> 23:00Z next day.
      final c1 = commit.shifts.firstWhere((s) => s.candidateId == 'cand-1');
      expect(c1.startDateTimeUtc, '2026-09-03T11:00:00.000Z');
      expect(c1.endDateTimeUtc, '2026-09-03T23:00:00.000Z');
      final c2 = commit.shifts.firstWhere((s) => s.candidateId == 'cand-2');
      expect(c2.startDateTimeUtc, '2026-09-04T23:00:00.000Z');
      expect(c2.endDateTimeUtc, '2026-09-05T11:00:00.000Z');

      // Audit: committed occurrences link back to their candidate.
      expect(commit.session.candidateForOccurrenceId('occ-cand-1')?.id,
          'cand-1');
    });
  });

  // -------------------------------------------------------------------------
  // IMPORT-005 — re-import diff.
  // -------------------------------------------------------------------------
  group('Re-import diff (golden)', () {
    test('IMPORT-005: added/modified-with-swaps detected, impact computed', () {
      final c = caseById(cases, 'IMPORT-005');
      final input = Map<String, dynamic>.from(c['input'] as Map);
      List<DiffEntry> entriesOf(dynamic list) => (list as List)
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return DiffEntry(
              date: m['date'] as String,
              shiftType: m['shiftType'] as String,
              start: m['start'] as String?,
              end: m['end'] as String?,
            );
          })
          .toList();

      final prev = entriesOf(
          ((input['previousSession'] as Map)['rawExtraction'] as Map)['entries']);
      final next =
          entriesOf((input['newExtraction'] as Map)['entries']);
      final diff = computeImportDiff(previous: prev, next: next);
      final expected = c['expected']['diff'] as Map<String, dynamic>;

      String fmt(List<DiffItem> items) => items
          .map((i) => '${i.date}:${i.changeType.name}')
          .toList()
          .join(',');

      expect(fmt(diff.added),
          (expected['added'] as List).map((e) {
            final m = e as Map;
            return '${m['date']}:${m['changeType'].toString().toLowerCase()}';
          }).join(','));

      final expRemoved = (expected['removed'] as List).length;
      expect(diff.removed.length, expRemoved);

      final expModified = (expected['modified'] as List)
          .map((e) {
            final m = e as Map;
            return '${m['date']}:${m['changeType'].toString().toLowerCase()}';
          })
          .toSet();
      final actModified = diff.modified
          .map((i) => '${i.date}:${i.changeType.name.toLowerCase()}')
          .toSet();
      expect(actModified, expModified);

      expect(diff.unchanged, isEmpty);

      // Impact: Off -> Day on 09-05 adds 12h; the swap pair nets 0.
      expect(diff.impact.totalHoursChanged, closeTo(12.0, 1e-9));
      expect(diff.impact.daysChanged, 3);
      expect(diff.impact.daysAdded, 1);
      expect(diff.impact.daysRemoved, 0);
    });
  });

  // -------------------------------------------------------------------------
  // IMPORT-008 — bulk action.
  // -------------------------------------------------------------------------
  group('Bulk actions (golden)', () {
    test('IMPORT-008: ACCEPT_ALL_HIGH approves only HIGH', () {
      final c = caseById(cases, 'IMPORT-008');
      final input = Map<String, dynamic>.from(c['input'] as Map);
      final candidates = (input['candidates'] as List)
          .map((x) => parseCandidate(Map<String, dynamic>.from(x as Map)))
          .toList();
      final session = ImportSession(
        id: 'session-import-008',
        createdAt: '2026-09-01T08:00:00Z',
        sourceType: ImportSourceType.pasteText,
        state: ImportState.extracted,
        referenceDate: '2026-09-01',
        timezone: 'America/New_York',
        rawExtraction:
            RawExtraction(sourceType: ImportSourceType.pasteText, entries: const []),
        candidates: candidates,
        committedOccurrenceIds: const [],
      );

      final after = bulkAcceptHigh(session);
      final statuses = {
        for (final x in after.candidates) x.id: x.reviewStatus
      };
      final expected = (c['expected']['afterBulkAction'] as List).cast<Map>();
      for (final e in expected) {
        expect(statuses[e['id']],
            ReviewStatus.fromName(e['reviewStatus'] as String),
            reason: 'IMPORT-008 ${e['id']}');
      }
      // INVARIANT-004: MEDIUM/LOW stay PENDING even after a bulk action.
      expect(statuses['c-2'], ReviewStatus.pending);
      expect(statuses['c-4'], ReviewStatus.pending);
      expect(statuses['c-5'], ReviewStatus.pending);
    });
  });

  // -------------------------------------------------------------------------
  // Unit semantics the goldens do not isolate.
  // -------------------------------------------------------------------------
  group('Import engine unit semantics', () {
    test('OCR-gated sources refused until M4.5 spike (no silent OCR)', () {
      for (final src in [ImportSourceType.image, ImportSourceType.pdf]) {
        final s = parseDocument(
          sourceType: src,
          rawText: 'irrelevant',
          templates: const [],
          referenceDate: '2026-09-01',
          timezone: 'UTC',
        );
        expect(s.state, ImportState.error);
        expect(s.error?.code, ImportErrorCodes.ocrPendingSpike);
        expect(s.error?.recoverable, isTrue);
        expect(s.committedOccurrenceIds, isEmpty);
      }
    });

    test('commit is atomic: one unresolvable approved candidate blocks all',
        () {
      // cand-1 resolvable; cand-2 approved but has no date -> whole commit
      // fails with COMMIT_UNRESOLVED; nothing recorded.
      ImportSession mk() => ImportSession(
            id: 's-atomic',
            createdAt: '2026-09-01T08:00:00Z',
            sourceType: ImportSourceType.pasteText,
            state: ImportState.reviewing,
            referenceDate: '2026-09-01',
            timezone: 'UTC',
            rawExtraction: const RawExtraction(
                sourceType: ImportSourceType.pasteText, entries: []),
            candidates: const [
              CandidateShift(
                id: 'ok',
                data: CandidateData(
                  date: '2026-09-03',
                  startTime: '07:00',
                  endTime: '19:00',
                  shiftType: 'Day',
                  kind: ShiftKind.shift,
                ),
                confidence: Confidence.high,
                reviewStatus: ReviewStatus.approved,
              ),
              CandidateShift(
                id: 'broken',
                data: CandidateData(shiftType: '?', kind: ShiftKind.unknown),
                confidence: Confidence.low,
                reviewStatus: ReviewStatus.approved,
              ),
            ],
            committedOccurrenceIds: const [],
          );
      final result = commitImport(mk());
      expect(result.error, isNotNull);
      expect(result.error?.code, ImportErrorCodes.commitUnresolved);
      expect(result.error?.candidateIds, ['broken']);
      expect(result.session.state, ImportState.error);
      expect(result.shifts, isEmpty);
      expect(result.session.committedOccurrenceIds, isEmpty);
    });

    test('modify lets the user fix a candidate before commit', () {
      final parsed = parseDocument(
        sourceType: ImportSourceType.pasteText,
        rawText: 'Sep 03 Night\nSep 04 Day',
        templates: const [
          TemplateSpec(
              id: 'tpl-night', name: 'Night', startTime: '19:00', endTime: '07:00+1'),
          TemplateSpec(
              id: 'tpl-day', name: 'Day', startTime: '07:00', endTime: '19:00'),
        ],
        referenceDate: '2026-09-01',
        timezone: 'UTC',
        id: 's-modify',
      );
      // "Sep 03 Night" has no times -> unknown/LOW; the user types the times.
      final cand = parsed.candidates.first;
      expect(cand.data.kind, ShiftKind.unknown);

      final reviewed = applyReview(
        parsed,
        candidateId: cand.id,
        action: ReviewAction.modify,
        edits: const CandidateData(
          date: '2026-09-03',
          startTime: '19:00',
          endTime: '07:00+1',
          shiftType: 'Night',
        ),
      );
      final modified =
          reviewed.candidates.firstWhere((x) => x.id == cand.id);
      expect(modified.reviewStatus, ReviewStatus.modified);
      expect(modified.data.kind, ShiftKind.shift);
      expect(modified.data.resolvable, isTrue);

      final commit = commitImport(reviewed);
      expect(commit.error, isNull);
      expect(commit.shifts.length, 1);
      expect(commit.shifts.single.occurrenceId, 'occ-${cand.id}');
    });

    // -------------------------------------------------------------------
    // Gate C A1 — the only legal commit transition is REVIEWING -> COMMITTED
    // (EXTRACTED -> COMMIT = reject; a REVIEWING session with nothing
    // approved/modified = reject, never a silent empty commit).
    // -------------------------------------------------------------------
    test('Gate C A1: EXTRACTED -> COMMIT is rejected even with approved rows',
        () {
      // A session whose candidates are approved but whose state was never
      // moved to REVIEWING (a caller bypassing applyReview) must NOT commit.
      final bypassed = ImportSession(
        id: 's-extracted-bypass',
        createdAt: '2026-09-01T08:00:00Z',
        sourceType: ImportSourceType.pasteText,
        state: ImportState.extracted,
        referenceDate: '2026-09-01',
        timezone: 'UTC',
        rawExtraction: const RawExtraction(
            sourceType: ImportSourceType.pasteText, entries: []),
        candidates: const [
          CandidateShift(
            id: 'c1',
            data: CandidateData(
              date: '2026-09-03',
              startTime: '07:00',
              endTime: '19:00',
              shiftType: 'Day',
              kind: ShiftKind.shift,
            ),
            confidence: Confidence.high,
            reviewStatus: ReviewStatus.approved,
          ),
        ],
        committedOccurrenceIds: const [],
      );
      final result = commitImport(bypassed);
      expect(result.error, isNotNull, reason: 'EXTRACTED must be rejected');
      expect(result.error?.code, ImportErrorCodes.illegalState);
      expect(result.error?.recoverable, isTrue);
      expect(result.session.state, ImportState.error);
      expect(result.shifts, isEmpty);
      expect(result.session.committedOccurrenceIds, isEmpty);
      expect(
        result.error!.message,
        contains('Call applyReview before commit'),
        reason: 'message must tell the caller EXTRACTED is not enough',
      );
    });

    test('Gate C A1: REVIEWING with zero approved/modified rows is rejected '
        '(no silent empty commit)', () {
      final rejectedOnly = ImportSession(
        id: 's-rejected-only',
        createdAt: '2026-09-01T08:00:00Z',
        sourceType: ImportSourceType.pasteText,
        state: ImportState.reviewing,
        referenceDate: '2026-09-01',
        timezone: 'UTC',
        rawExtraction: const RawExtraction(
            sourceType: ImportSourceType.pasteText, entries: []),
        candidates: const [
          CandidateShift(
            id: 'c1',
            data: CandidateData(
              date: '2026-09-03',
              startTime: '07:00',
              endTime: '19:00',
              shiftType: 'Day',
              kind: ShiftKind.shift,
            ),
            confidence: Confidence.high,
            reviewStatus: ReviewStatus.rejected,
          ),
        ],
        committedOccurrenceIds: const [],
      );
      final result = commitImport(rejectedOnly);
      expect(result.error, isNotNull);
      expect(result.error?.code, ImportErrorCodes.illegalState);
      expect(result.error!.message, contains('Approve at least 1 row'));
      expect(result.session.state, ImportState.error);
      expect(result.shifts, isEmpty);
      expect(result.session.committedOccurrenceIds, isEmpty);
    });

    test('reviewing a committed session is an ILLEGAL_STATE error', () {
      final parsed = parseDocument(
        sourceType: ImportSourceType.pasteText,
        rawText: 'Sep 03 Day 07:00-19:00',
        templates: const [
          TemplateSpec(
              id: 't', name: 'Day', startTime: '07:00', endTime: '19:00')
        ],
        referenceDate: '2026-09-01',
        timezone: 'UTC',
        id: 's-illegal',
      );
      final approved = applyReview(parsed,
          candidateId: parsed.candidates.single.id,
          action: ReviewAction.approve);
      final committed = commitImport(approved);
      expect(committed.error, isNull);

      final again = applyReview(committed.session,
          candidateId: 'cand-1', action: ReviewAction.reject);
      expect(again.state, ImportState.error);
      expect(again.error?.code, ImportErrorCodes.illegalState);
    });

    // RC plan §A4 — the full invalid-transition matrix: only REVIEWING may
    // COMMIT. ERROR -> COMMIT, COMMITTED -> COMMIT and IDLE -> COMMIT are all
    // rejected loudly, zero shifts recorded.
    test('A4: ERROR -> COMMIT is rejected (zero shifts, no state mutation '
        'past the error)', () {
      final errored = ImportSession(
        id: 's-error-commit',
        createdAt: '2026-09-01T08:00:00Z',
        sourceType: ImportSourceType.pasteText,
        state: ImportState.error,
        referenceDate: '2026-09-01',
        timezone: 'UTC',
        rawExtraction: const RawExtraction(
            sourceType: ImportSourceType.pasteText, entries: []),
        candidates: const [],
        committedOccurrenceIds: const [],
        error: const ImportError(
            code: ImportErrorCodes.parseFailed,
            message: 'previous parse failed',
            recoverable: true),
        history: const [
          ImportState.idle,
          ImportState.parsing,
          ImportState.error
        ],
      );
      final result = commitImport(errored);
      expect(result.error, isNotNull);
      expect(result.error?.code, ImportErrorCodes.illegalState);
      expect(result.session.state, ImportState.error);
      expect(result.shifts, isEmpty);
      expect(result.session.committedOccurrenceIds, isEmpty);
    });

    // -------------------------------------------------------------------
    // RC plan §A5 — conflict validation blocks contradictory approved rows;
    // the engine never picks a winner to "make the commit run".
    // -------------------------------------------------------------------
    ImportSession conflictingSession({
      required String id,
      required List<CandidateShift> candidates,
    }) =>
        ImportSession(
          id: id,
          createdAt: '2026-09-01T08:00:00Z',
          sourceType: ImportSourceType.pasteText,
          state: ImportState.reviewing,
          referenceDate: '2026-09-01',
          timezone: 'UTC',
          rawExtraction: const RawExtraction(
              sourceType: ImportSourceType.pasteText, entries: []),
          candidates: candidates,
          committedOccurrenceIds: const [],
          history: const [
            ImportState.idle,
            ImportState.parsing,
            ImportState.extracted,
            ImportState.reviewing
          ],
        );

    test('A5: OFF + SHIFT approved on the same date -> CONFLICT, zero rows',
        () {
      final s = conflictingSession(id: 's-off-shift', candidates: const [
        CandidateShift(
          id: 'c1',
          data: CandidateData(
            date: '2026-09-03',
            shiftType: 'OFF',
            kind: ShiftKind.off,
          ),
          confidence: Confidence.high,
          reviewStatus: ReviewStatus.approved,
        ),
        CandidateShift(
          id: 'c2',
          data: CandidateData(
            date: '2026-09-03',
            startTime: '07:00',
            endTime: '19:00',
            shiftType: 'Day',
            kind: ShiftKind.shift,
          ),
          confidence: Confidence.high,
          reviewStatus: ReviewStatus.approved,
        ),
      ]);
      final result = commitImport(s);
      expect(result.error, isNotNull);
      expect(result.error?.code, ImportErrorCodes.conflict);
      expect(result.error!.message, contains('OFF and SHIFT'));
      expect(result.error?.recoverable, isTrue);
      expect(result.session.state, ImportState.error);
      expect(result.shifts, isEmpty);
      expect(result.session.committedOccurrenceIds, isEmpty);
    });

    test('A5: two identical approved shifts on one date -> CONFLICT, zero rows',
        () {
      final s = conflictingSession(id: 's-dup', candidates: const [
        CandidateShift(
          id: 'c1',
          data: CandidateData(
            date: '2026-09-03',
            startTime: '07:00',
            endTime: '19:00',
            shiftType: 'Day',
            kind: ShiftKind.shift,
          ),
          confidence: Confidence.high,
          reviewStatus: ReviewStatus.approved,
        ),
        CandidateShift(
          id: 'c2',
          data: CandidateData(
            date: '2026-09-03',
            startTime: '07:00',
            endTime: '19:00',
            shiftType: 'Day',
            kind: ShiftKind.shift,
          ),
          confidence: Confidence.high,
          reviewStatus: ReviewStatus.approved,
        ),
      ]);
      final result = commitImport(s);
      expect(result.error, isNotNull);
      expect(result.error?.code, ImportErrorCodes.conflict);
      expect(result.error!.message, contains('duplicate shift'));
      expect(result.shifts, isEmpty);
      expect(result.session.state, ImportState.error);
    });

    test('A5: non-conflicting roster still commits (no false positive)', () {
      final s = conflictingSession(id: 's-clean', candidates: const [
        CandidateShift(
          id: 'c1',
          data: CandidateData(
            date: '2026-09-03',
            startTime: '07:00',
            endTime: '19:00',
            shiftType: 'Day',
            kind: ShiftKind.shift,
          ),
          confidence: Confidence.high,
          reviewStatus: ReviewStatus.approved,
        ),
        CandidateShift(
          id: 'c2',
          data: CandidateData(
            date: '2026-09-04',
            startTime: '07:00',
            endTime: '19:00',
            shiftType: 'Day',
            kind: ShiftKind.shift,
          ),
          confidence: Confidence.high,
          reviewStatus: ReviewStatus.approved,
        ),
      ]);
      final result = commitImport(s);
      expect(result.error, isNull);
      expect(result.session.state, ImportState.committed);
      expect(result.shifts, hasLength(2));
    });

    test('A4: COMMITTED -> COMMIT and IDLE -> COMMIT are rejected (no '
        'double commit)', () {
      final committed = ImportSession(
        id: 's-committed-commit',
        createdAt: '2026-09-01T08:00:00Z',
        sourceType: ImportSourceType.pasteText,
        state: ImportState.committed,
        referenceDate: '2026-09-01',
        timezone: 'UTC',
        rawExtraction: const RawExtraction(
            sourceType: ImportSourceType.pasteText, entries: []),
        candidates: const [],
        committedOccurrenceIds: const [],
        committedOffDates: const [],
        history: const [
          ImportState.idle,
          ImportState.parsing,
          ImportState.extracted,
          ImportState.reviewing,
          ImportState.committed
        ],
      );
      final result = commitImport(committed);
      expect(result.error, isNotNull,
          reason: 'a committed session must never commit again');
      expect(result.error?.code, ImportErrorCodes.illegalState);
      expect(result.session.state, ImportState.error);
      expect(result.shifts, isEmpty);

      final idle = ImportSession(
        id: 's-idle-commit',
        createdAt: '2026-09-01T08:00:00Z',
        sourceType: ImportSourceType.pasteText,
        state: ImportState.idle,
        referenceDate: '2026-09-01',
        timezone: 'UTC',
        rawExtraction: const RawExtraction(
            sourceType: ImportSourceType.pasteText, entries: []),
        candidates: const [],
        committedOccurrenceIds: const [],
      );
      final idleResult = commitImport(idle);
      expect(idleResult.error, isNotNull);
      expect(idleResult.error?.code, ImportErrorCodes.illegalState);
      expect(idleResult.shifts, isEmpty);
    });

    test('date resolution anchors to referenceDate; never invents past months',
        () {
      String? r(String t) => resolveDateToken(t, referenceDate: '2026-09-01');
      expect(r('2026-09-03'), '2026-09-03');
      expect(r('Sep 03'), '2026-09-03');
      expect(r('03 Sep'), '2026-09-03');
      expect(r('Sep 3, 2026'), '2026-09-03');
      expect(r('Mon 3rd'), isNull); // Sep 2026 has no Monday the 3rd
      expect(r('Mon'), isNull); // bare weekday not pinnable
      // Numeric order follows the dateOrder preference.
      expect(r('03/09/2026'), '2026-03-09'); // monthDay default
      expect(resolveDateToken('03/09/2026',
          referenceDate: '2026-09-01', dateOrder: DateOrder.dayMonth),
          '2026-09-03');
      // M1: never a fake calendar date.
      expect(r('2026-02-31'), isNull);
    });

    test('overnight time pairs normalize with a +1 end marker', () {
      final n = normalizeTimePair('19:00', '07:00');
      expect(n, isNotNull);
      expect(n!.start, '19:00');
      expect(n.end, '07:00+1');
      final same = normalizeTimePair('08:00', '16:00');
      expect(same!.end, '16:00'); // no marker on same-day shifts
    });
  });
}
