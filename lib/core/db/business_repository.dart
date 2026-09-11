// =============================================================================
// Business repositories — PayRule (+children) and ImportSession (+candidates)
// =============================================================================
//
// PayRule is versioned (INVARIANT-006): all versions of a job live as rows;
// the ACTIVE version on a date is resolved by query, never by rewriting rows.
// ImportSession rows are the audit store for one import (raw extraction +
// candidates + committed ids) so "why is Sep 03 a Night shift?" stays
// answerable after a restart (plan2 §3.3).
// =============================================================================

import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/import/import_types.dart';

import 'pattern_repository.dart' hide newUuid;
import 'db.dart' show newUuid;

class PayRuleRepository {
  final Database db;
  final PatternRepository jobs; // ensureJob helper

  PayRuleRepository(this.db, this.jobs);

  /// Save a rule version with its differential/overtime children atomically.
  /// PayRule UUIDs are generated per-row by the repository via [newUuid] from
  /// core/db/db.dart — identical to how occurrences and patterns are keyed in
  /// this codebase (deterministic engine ids stay as the public contract; the DB
  /// key never collides across re-imports).
  ///
  /// Idempotent on identical content: if a row with the same [rule.id] ALREADY
  /// exists and its payload differs from [rule], throw — silent overwrite of
  /// a persisted version is forbidden (Gate A §A6, version immutability at the
  /// persistence boundary). Identical re-save is a no-op.
  ///
  /// RC plan §A8 — integrity guards BEFORE any write:
  ///   - an UNKNOWN jobId is rejected — a fake job is NEVER auto-created just
  ///     so the rule has somewhere to live (jobs come from the job form);
  ///   - malformed money numbers (non-positive base rate, negative
  ///     differential value, negative OT threshold, multiplier < 1) are
  ///     loud ArgumentErrors — never silently stored as a different rule.
  void savePayRule({required PayRule rule}) {
    final jobRows =
        db.select('SELECT uuid FROM jobs WHERE id = ?', [rule.jobId]);
    if (jobRows.isEmpty) {
      throw ArgumentError(
          'PayRule ${rule.id} references unknown job ${rule.jobId} — '
          'refusing to auto-create a fake job (RC §A8). Create the job first.');
    }
    final jobUuid = jobRows.first['uuid'] as String;
    if (!rule.baseHourlyRate.isFinite || rule.baseHourlyRate <= 0) {
      throw ArgumentError(
          'PayRule base rate must be a positive number (got '
          '${rule.baseHourlyRate}).');
    }
    for (final d in rule.differentials) {
      if (!d.value.isFinite || d.value < 0) {
        throw ArgumentError(
            'PayRule differential ${d.type.name} has invalid value '
            '${d.value} — must be >= 0.');
      }
      if (d.scope == DifferentialScope.hoursInWindow && d.window == null) {
        throw ArgumentError(
            'PayRule differential ${d.type.name} is HOURS_IN_WINDOW but has '
            'no window — every window differential needs one.');
      }
    }
    for (final o in rule.overtimeRules) {
      if (!o.thresholdHours.isFinite || o.thresholdHours < 0) {
        throw ArgumentError(
            'PayRule OT threshold must be >= 0 (got ${o.thresholdHours}).');
      }
      if (!o.multiplier.isFinite || o.multiplier < 1) {
        throw ArgumentError(
            'PayRule OT multiplier must be >= 1 (got ${o.multiplier}).');
      }
    }
    db.execute('BEGIN');
    try {
      // Gate A §A6 — check existence BEFORE any write. A same-id re-save is
      // allowed only when the payload is identical (idempotent no-op); any
      // difference in base rate / window / differentials / overtime rules is
      // a silent-overwrite attempt and is refused loudly. A NEW version must
      // use a new id.
      final existing = db.select(
          'SELECT uuid, baseHourlyRate, effectiveFrom, effectiveUntil '
          'FROM pay_rules WHERE id = ?', [rule.id]);
      String storedUuid;
      if (existing.isEmpty) {
        db.execute(
          '''INSERT INTO pay_rules (uuid, id, jobUuid, baseHourlyRate,
             effectiveFrom, effectiveUntil)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(id) DO NOTHING''',
          [newUuid(), rule.id, jobUuid, rule.baseHourlyRate,
            rule.effectiveFrom, rule.effectiveUntil],
        );
        final after = db.select(
            'SELECT uuid FROM pay_rules WHERE id = ?', [rule.id]);
        if (after.isEmpty) {
          // Outer catch rolls the transaction back and rethrows.
          throw StateError(
              'PayRule $rule.id inserted then not found — DB state invariant '
              'broken.');
        }
        storedUuid = after.first['uuid'] as String;
      } else {
        final e = existing.first;
        if (e['baseHourlyRate'] != rule.baseHourlyRate ||
            e['effectiveFrom'] != rule.effectiveFrom ||
            e['effectiveUntil'] != rule.effectiveUntil ||
            _payChildrenDiffer(e['uuid'] as String, rule)) {
          // Outer catch rolls the transaction back and rethrows.
          throw StateError(
              'PayRule $rule.id already exists with a DIFFERENT payload; '
              'refusing to silently overwrite (Gate A §A6: version '
              'immutability at the persistence boundary). Use a new id for the '
              'new version.');
        }
        storedUuid = e['uuid'] as String;
      }
      // Children: delete + re-insert atomically as part of this rule version
      // (a PayRule version is one unit — diffs+OT rules share the rule uuid).
      db.execute(
          'DELETE FROM pay_differentials WHERE payRuleUuid = ?',
          [storedUuid]);
      for (final d in rule.differentials) {
        db.execute(
          '''INSERT INTO pay_differentials
             (uuid, payRuleUuid, type, mode, value, scope,
              windowStartLocal, windowEndLocal)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            newUuid(), storedUuid, d.type.name, d.mode.name, d.value,
            d.scope.name,
            d.window?.startLocal, d.window?.endLocal,
          ],
        );
      }
      db.execute('DELETE FROM pay_overtime_rules WHERE payRuleUuid = ?',
          [storedUuid]);
      for (final r in rule.overtimeRules) {
        db.execute(
          '''INSERT INTO pay_overtime_rules
             (uuid, payRuleUuid, thresholdHours, period, multiplier)
           VALUES (?, ?, ?, ?, ?)''',
          [newUuid(), storedUuid, r.thresholdHours, r.period.name, r.multiplier],
        );
      }

      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// True when the stored children (differentials + overtime rules) of the
  /// rule row [ruleUuid] differ from [rule] — part of the A6 payload check.
  /// A PayRule version is its differentials and OT rules as much as its base
  /// rate, so a same-id re-save must not silently swap them either.
  ///
  /// RC plan §A8: children are compared ORDER-INDEPENDENTLY (multiset over a
  /// canonical per-child key) — the child lists are semantically unordered, so
  /// a re-save that only reorders the editor's rows is still the SAME version
  /// (idempotent no-op), never a false immutability conflict.
  bool _payChildrenDiffer(String ruleUuid, PayRule rule) {
    final dRows = db.select('SELECT * FROM pay_differentials '
        'WHERE payRuleUuid = ?', [ruleUuid]);
    if (dRows.length != rule.differentials.length) return true;
    final storedD = {
      for (final r in dRows)
        [
          r['type'], r['mode'], (r['value'] as num).toDouble().toString(),
          r['scope'], r['windowStartLocal'], r['windowEndLocal'],
        ].join('|')
    };
    final incomingD = {
      for (final d in rule.differentials)
        [
          d.type.name, d.mode.name, d.value.toString(), d.scope.name,
          d.window?.startLocal, d.window?.endLocal,
        ].join('|')
    };
    if (storedD.length != incomingD.length ||
        !storedD.containsAll(incomingD)) {
      return true;
    }

    final oRows = db.select('SELECT * FROM pay_overtime_rules '
        'WHERE payRuleUuid = ?', [ruleUuid]);
    if (oRows.length != rule.overtimeRules.length) return true;
    final storedO = {
      for (final r in oRows)
        [
          r['period'], (r['thresholdHours'] as num).toDouble().toString(),
          (r['multiplier'] as num).toDouble().toString(),
        ].join('|')
    };
    final incomingO = {
      for (final o in rule.overtimeRules)
        [
          o.period.name, o.thresholdHours.toString(), o.multiplier.toString(),
        ].join('|')
    };
    return storedO.length != incomingO.length ||
        !storedO.containsAll(incomingO);
  }

  /// Resolve the rule ACTIVE on [date] (INVARIANT-006), newest effectiveFrom
  /// first — mirrors money_engine.getActivePayRule semantics over the DB.
  PayRule? activeRuleFor({required String jobId, required String date}) {
    final jobUuid = db.select(
        'SELECT uuid FROM jobs WHERE id = ?', [jobId]);
    if (jobUuid.isEmpty) return null;
    final rows = db.select(
      '''SELECT * FROM pay_rules WHERE jobUuid = ?
         AND effectiveFrom <= ?
         AND (effectiveUntil IS NULL OR effectiveUntil >= ?)
       ORDER BY effectiveFrom DESC, id''',
      [jobUuid.first['uuid'], date, date],
    );
    if (rows.isEmpty) return null;
    return _ruleFromRow(rows.first);
  }

  List<PayRule> allRulesFor(String jobId) {
    final jobUuid = db.select(
        'SELECT uuid FROM jobs WHERE id = ?', [jobId]);
    if (jobUuid.isEmpty) return const [];
    final rows = db.select(
        'SELECT * FROM pay_rules WHERE jobUuid = ? ORDER BY effectiveFrom',
        [jobUuid.first['uuid']]);
    return rows.map(_ruleFromRow).toList();
  }

  PayRule _ruleFromRow(Row r) {
    final uuid = r['uuid'] as String;
    final diffs = db.select(
        'SELECT * FROM pay_differentials WHERE payRuleUuid = ? ORDER BY type',
        [uuid]);
    final ots = db.select(
        'SELECT * FROM pay_overtime_rules WHERE payRuleUuid = ? ORDER BY period',
        [uuid]);
    return PayRule(
      id: r['id'] as String,
      jobId: _jobIdOf(uuid),
      baseHourlyRate: (r['baseHourlyRate'] as num).toDouble(),
      effectiveFrom: r['effectiveFrom'] as String,
      effectiveUntil: r['effectiveUntil'] as String?,
      differentials: diffs.map((d) {
        return PayDifferential(
          type: DifferentialType.fromName(d['type'] as String),
          mode: DifferentialMode.fromName(d['mode'] as String),
          value: (d['value'] as num).toDouble(),
          scope: DifferentialScope.fromName(d['scope'] as String),
          window: d['windowStartLocal'] == null
              ? null
              : DifferentialWindow(
                  startLocal: d['windowStartLocal'] as String,
                  endLocal: d['windowEndLocal'] as String,
                ),
        );
      }).toList(),
      overtimeRules: ots.map((o) {
        return OvertimeRule(
          thresholdHours: (o['thresholdHours'] as num).toDouble(),
          period: OvertimePeriod.fromName(o['period'] as String),
          multiplier: (o['multiplier'] as num).toDouble(),
        );
      }).toList(),
    );
  }

  String _jobIdOf(String ruleUuid) {
    final row = db.select(
      'SELECT j.id FROM pay_rules pr JOIN jobs j ON j.uuid = pr.jobUuid '
      'WHERE pr.uuid = ?',
      [ruleUuid],
    );
    return row.first['id'] as String;
  }
}

class ImportRepository {
  final Database db;
  final PatternRepository? jobs; // read job timezone for import windows (defensive)

  ImportRepository(this.db, [this.jobs]);

  /// Persist one session with its candidates and raw extraction (audit).
  /// [jobId] is the job whose schedule this import belongs to (v3 — the
  /// render needs it to scope suppression/OFF dates; a session can belong to
  /// at most one job).
  ///
  /// Window semantics (Gate A, plan4 review1/3/4): when [session] is
  /// COMMITTED, [windowStart]/[windowEnd] MUST be set (non-null, non-empty).
  /// They define the date range this committed session governs: any later
  /// re-import whose window overlaps a previous one REPLACES it (see
  /// [schedule_repository.committedOffDatesInRange] + the render's import
  /// merge). Outside the window the previous session keeps effect — the
  /// system never deduces a "replace everything" intent.
  void saveSession(ImportSession session, {String? jobId}) {
    _saveSessionInTransaction(session, jobId: jobId);
  }

  /// Same as [saveSession] but issues NO transaction of its own — the caller
  /// owns the surrounding BEGIN/COMMIT/ROLLBACK. [ScheduleService.commitRoster]
  /// calls this inside its own transaction so the session + its occurrences
  /// commit (or roll back) as ONE atomic unit. Never open a BEGIN here.
  void _saveSessionInTransaction(ImportSession session, {String? jobId}) {
    if (session.state == ImportState.committed &&
        (session.windowStart == null ||
            session.windowStart!.isEmpty ||
            session.windowEnd == null ||
            session.windowEnd!.isEmpty)) {
      throw ArgumentError(
          'A COMMITTED ImportSession must carry non-empty windowStart and '
          'windowEnd (Gate A — import window semantics).');
    }
    // Gate C A4 / D-C4: a session whose stored row is COMMITTED is immutable.
    // The check happens BEFORE any write — no unconditional ON CONFLICT
    // overwrite of committed history. Allowed after a committed state:
    //   - an IDENTICAL full-payload re-save (idempotent no-op), or
    //   - nothing else — any payload/state/job change throws loudly.
    final storedRows = db.select(
        'SELECT * FROM import_sessions WHERE id = ?', [session.id]);
    if (storedRows.isNotEmpty &&
        (storedRows.first['state'] as String) ==
            ImportState.committed.name) {
      final row = storedRows.first;
      if (!_sameCommittedSessionPayload(
          row, session, jobId: jobId)) {
        throw StateError(
            'ImportSession ${session.id} is COMMITTED and therefore immutable '
            '(Gate C A4). Refusing to overwrite a committed session — commit '
            'history must never be rewritten. Use a new session id for a new '
            'import.');
      }
      return; // identical committed re-save = idempotent no-op
    }
    db.execute(
      '''INSERT INTO import_sessions
         (uuid, id, sourceType, state, referenceDate, timezone, createdAt,
          rawExtractionJson, committedIdsJson, historyJson, jobId,
          committedOffDatesJson, windowStart, windowEnd)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         state = excluded.state,
         rawExtractionJson = excluded.rawExtractionJson,
         committedIdsJson = excluded.committedIdsJson,
         historyJson = excluded.historyJson,
         jobId = excluded.jobId,
         committedOffDatesJson = excluded.committedOffDatesJson,
         windowStart = excluded.windowStart,
         windowEnd = excluded.windowEnd''',
      [
        newUuid(), session.id, session.sourceType.name, session.state.name,
        session.referenceDate, session.timezone, session.createdAt,
        jsonEncode(_extractionToJson(session.rawExtraction)),
        jsonEncode(session.committedOccurrenceIds),
        jsonEncode(
            session.history.map((s) => s.name).toList(growable: false)),
        jobId,
        jsonEncode(session.committedOffDates),
        session.windowStart,
        session.windowEnd,
      ],
    );
    final sessionUuidRaw =
        db.select('SELECT uuid FROM import_sessions WHERE id = ?',
            [session.id]);
    if (sessionUuidRaw.isEmpty) {
      throw StateError(
          'ImportRepository: session $session.id not found after upsert — '
          'implies unique-key or transaction invariant broken.');
    }
    final sessionUuid = sessionUuidRaw.first['uuid'] as String;
    db.execute('DELETE FROM import_candidates WHERE sessionUuid = ?',
        [sessionUuid]);
    for (final c in session.candidates) {
      db.execute(
        '''INSERT INTO import_candidates
           (uuid, sessionUuid, id, date, templateId, startTime, endTime,
            shiftType, kind, confidence, reviewStatus, note)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          newUuid(), sessionUuid, c.id, c.data.date, c.data.templateId,
          c.data.startTime, c.data.endTime, c.data.shiftType,
          c.data.kind.name, c.confidence.name, c.reviewStatus.name, c.note,
        ],
      );
    }
  }

  /// Gate C A4 — true when [incoming] (which must be COMMITTED) carries the
  /// IDENTICAL full payload of the stored COMMITTED row [row]. Compares the
  /// canonical JSON each field was stored under + the candidate rows, so an
  /// idempotent re-save of a committed session is allowed while ANY real
  /// change (raw, candidates, committed ids/off dates, window, history,
  /// ownership) is detected and refused.
  bool _sameCommittedSessionPayload(
    Row row,
    ImportSession incoming, {
    String? jobId,
  }) {
    if (incoming.state != ImportState.committed) return false;
    if (incoming.createdAt != row['createdAt']) return false;
    if (incoming.sourceType.name != row['sourceType']) return false;
    if (incoming.referenceDate != row['referenceDate']) return false;
    if (incoming.timezone != row['timezone']) return false;
    if (incoming.windowStart != row['windowStart']) return false;
    if (incoming.windowEnd != row['windowEnd']) return false;
    if (jobId != row['jobId']) return false;
    if (jsonEncode(_extractionToJson(incoming.rawExtraction)) !=
        row['rawExtractionJson']) {
      return false;
    }
    if (jsonEncode(incoming.committedOccurrenceIds) !=
        row['committedIdsJson']) {
      return false;
    }
    if (jsonEncode(incoming.committedOffDates) !=
        row['committedOffDatesJson']) {
      return false;
    }
    if (jsonEncode(
            incoming.history.map((s) => s.name).toList(growable: false)) !=
        row['historyJson']) {
      return false;
    }
    // Candidates: compare as a multiset keyed by candidate id (row order vs
    // session order may legitimately differ across a reload).
    final storedCands = db.select(
        'SELECT id, date, templateId, startTime, endTime, shiftType, kind, '
        'confidence, reviewStatus, note FROM import_candidates '
        'WHERE sessionUuid = ?', [row['uuid']]);
    String canon(dynamic c, String id, String? date, String? templateId,
            String? start, String? end, String? shiftType, String? kind,
            String? confidence, String? reviewStatus, String? note) =>
        [id, date, templateId, start, end, shiftType, kind, confidence,
          reviewStatus, note]
            .join('|');
    final storedSet = storedCands
        .map((c) => canon(c, c['id'] as String, c['date'] as String?,
            c['templateId'] as String?, c['startTime'] as String?,
            c['endTime'] as String?, c['shiftType'] as String?,
            c['kind'] as String, c['confidence'] as String,
            c['reviewStatus'] as String, c['note'] as String?))
        .toSet();
    final incomingSet = incoming.candidates
        .map((c) => canon(c, c.id, c.data.date, c.data.templateId,
            c.data.startTime, c.data.endTime, c.data.shiftType,
            c.data.kind.name, c.confidence.name, c.reviewStatus.name,
            c.note))
        .toSet();
    if (storedSet.length != incoming.candidates.length ||
        storedSet.length != storedCands.length) {
      return false;
    }
    return storedSet.containsAll(incomingSet);
  }

  ImportSession? sessionById(String id) {
    final rows =
        db.select('SELECT * FROM import_sessions WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final uuid = r['uuid'] as String;
    final candidates = db.select(
        'SELECT * FROM import_candidates WHERE sessionUuid = ? ORDER BY id',
        [uuid]);
    final offRaw = r['committedOffDatesJson'] as String?;
    return ImportSession(
      id: r['id'] as String,
      createdAt: r['createdAt'] as String,
      sourceType: ImportSourceType.fromName(r['sourceType'] as String),
      state: ImportState.values.firstWhere(
          (s) => s.name == (r['state'] as String),
          orElse: () => ImportState.error),
      referenceDate: r['referenceDate'] as String,
      timezone: r['timezone'] as String,
      rawExtraction: _extractionFromJson(
          r['rawExtractionJson'] as String,
          ImportSourceType.fromName(r['sourceType'] as String)),
      candidates: candidates.map(_candidateFromRow).toList(),
      committedOccurrenceIds: (jsonDecode(r['committedIdsJson'] as String)
              as List)
          .cast<String>(),
      committedOffDates: offRaw == null
          ? const []
          : (jsonDecode(offRaw) as List).cast<String>(),
      windowStart: r['windowStart'] as String?,
      windowEnd: r['windowEnd'] as String?,
      history: (jsonDecode(r['historyJson'] as String) as List)
          .map((s) => ImportState.values.firstWhere(
              (st) => st.name == s as String,
              orElse: () => ImportState.error))
          .toList(),
    );
  }

  CandidateShift _candidateFromRow(Row r) {
    final kindRaw = r['shiftType'] as String?;
    final kindName = r['kind'] as String;
    final kind = ShiftKind.values.firstWhere((k) => k.name == kindName,
        orElse: () => kindRaw?.toLowerCase() == 'off'
            ? ShiftKind.off
            : ((r['startTime'] != null) ? ShiftKind.shift : ShiftKind.unknown));
    return CandidateShift(
      id: r['id'] as String,
      data: CandidateData(
        date: r['date'] as String?,
        templateId: r['templateId'] as String?,
        startTime: r['startTime'] as String?,
        endTime: r['endTime'] as String?,
        shiftType: r['shiftType'] as String?,
        kind: kind,
      ),
      confidence: Confidence.fromName(r['confidence'] as String),
      reviewStatus: ReviewStatus.fromName(r['reviewStatus'] as String),
      note: r['note'] as String?,
    );
  }

  static List<Map<String, dynamic>> _extractionToJson(RawExtraction e) => [
        for (final entry in e.entries)
          {
            'line': entry.lineNumber,
            'original': entry.original,
            'dateToken': entry.dateToken,
            'start': entry.startTime,
            'end': entry.endTime,
            'label': entry.shiftTypeLabel,
            'garbage': entry.hasGarbage,
          }
      ];

  static RawExtraction _extractionFromJson(String json, ImportSourceType type) {
    final entries = (jsonDecode(json) as List).cast<Map>().map((m) {
      return RawEntry(
        lineNumber: (m['line'] as num?)?.toInt() ?? 0,
        original: m['original'] as String? ?? '',
        dateToken: m['dateToken'] as String?,
        startTime: m['start'] as String?,
        endTime: m['end'] as String?,
        shiftTypeLabel: m['label'] as String?,
        hasGarbage: m['garbage'] as bool? ?? false,
      );
    }).toList();
    return RawExtraction(sourceType: type, entries: entries);
  }
}
