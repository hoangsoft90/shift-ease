// =============================================================================
// ScheduleRepository — occurrences, overrides, pay-estimate snapshots, render
// =============================================================================
//
// Rules enforced at the persistence boundary:
//   - Overrides are APPEND-ONLY (the audit trail; nothing is ever edited or
//     deleted once written — plan3_final §Gate2 soft-delete/audit decision).
//   - actualPayEstimate is an immutable snapshot (INVARIANT-006): once set it
//     can never be changed to a different value. Re-rendering a schedule
//     refreshes temporal fields only and never touches the snapshot.
//   - renderJobSchedule re-derives the schedule from the ACTIVE pattern
//     versions + the stored override log through the PURE engine, then
//     persists the resulting occurrences — the DB never fabricates results.
// =============================================================================

import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/pattern/pattern_engine.dart'
    show projectOccurrences, applyOverride;

import 'override_codec.dart';
import 'pattern_repository.dart';

/// Thrown when a write would rewrite the immutable past.
class ImmutableHistoryError implements Exception {
  final String message;
  const ImmutableHistoryError(this.message);
  @override
  String toString() => 'ImmutableHistoryError: $message';
}

class ScheduleRepository {
  final Database db;
  final PatternRepository patterns;

  ScheduleRepository(this.db, this.patterns);

  /// Persist resolved occurrences for ONE job as a scoped REPLACE of the
  /// materialized cache (RC plan §A3). The occurrences table is a
  /// materialized effective-schedule projection, NEVER a historical store:
  /// history lives in patterns/versions, the override log and import
  /// sessions. Inside one transaction this
  ///
  ///   1. stamps every row with the job id (baseline/created rows arrive
  ///      without one — the row must be scoped so stale removal is safe),
  ///   2. DELETES rows of this job inside [from..to] that are NOT in the new
  ///      projection (a suppressed/replaced/deleted day must not keep a
  ///      stale row readable as a current shift by any direct table reader),
  ///   3. upserts the effective rows — temporal/source fields refresh, but a
  ///      committed pay snapshot is NEVER overwritten here (INVARIANT-006;
  ///      setPayEstimateSnapshot enforces immutability).
  /// Rows outside [from..to] and rows of other jobs are never touched.
  void saveOccurrencesForJob({
    required String jobId,
    required String from,
    required String to,
    required List<ShiftOccurrence> occurrences,
  }) {
    db.execute('BEGIN');
    try {
      final ids = occurrences.map((o) => o.id).toList();
      if (ids.isEmpty) {
        db.execute(
          'DELETE FROM occurrences WHERE jobId = ? '
          'AND shiftDate >= ? AND shiftDate <= ?',
          [jobId, from, to],
        );
      } else {
        final ph = List.filled(ids.length, '?').join(',');
        db.execute(
          'DELETE FROM occurrences WHERE jobId = ? '
          'AND shiftDate >= ? AND shiftDate <= ? AND id NOT IN ($ph)',
          [jobId, from, to, ...ids],
        );
      }
      for (final o in occurrences) {
        _upsertOccurrenceRow(o.copyWith(jobId: o.jobId ?? jobId));
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _upsertOccurrenceRow(ShiftOccurrence o) {
    db.execute(
      '''INSERT INTO occurrences
         (uuid, id, patternId, shiftDate, templateId, startDateTimeUtc,
          endDateTimeUtc, timezone, source, sourceOverrideId,
          jobId, isImported)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         patternId = excluded.patternId,
         shiftDate = excluded.shiftDate,
         templateId = excluded.templateId,
         startDateTimeUtc = excluded.startDateTimeUtc,
         endDateTimeUtc = excluded.endDateTimeUtc,
         timezone = excluded.timezone,
         source = excluded.source,
         sourceOverrideId = excluded.sourceOverrideId,
         jobId = excluded.jobId,
         isImported = excluded.isImported''',
      [
        newUuid(), o.id, o.patternId, o.shiftDate, o.templateId,
        o.startDateTimeUtc, o.endDateTimeUtc, o.timezone,
        o.source.name, o.sourceOverrideId, o.jobId,
        o.isImported ? 1 : 0,
      ],
    );
  }

  /// Replace a job's COMMITTED-IMPORT rows inside [from..to] with [rows]
  /// (plan7 D-M2-1). Imported rows are authoritative roster rows — they are
  /// not pattern projections and are keyed to the job via [ShiftOccurrence.jobId]
  /// (their [patternId] is ''; the render reads them by job). Rows are a
  /// materialized projection cache, so a NEWER approved import replaces the
  /// older one for its window; the override log is never touched here.
  /// Own-transaction flavour of [replaceImportedOccurrences] — opens its own
  /// BEGIN/COMMIT. Use when NOT already inside a caller-owned transaction.
  void replaceImportedOccurrences({
    required String jobId,
    required String from,
    required String to,
    required List<ShiftOccurrence> rows,
  }) {
    db.execute('BEGIN');
    try {
      _replaceImportedOccurrencesNoTxn(
          jobId: jobId, from: from, to: to, rows: rows);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Same write as [replaceImportedOccurrences] but WITHOUT its own
  /// BEGIN/COMMIT — the CALLER owns the surrounding transaction. Composing
  /// session + occurrences atomically (commitRoster) must never nest a BEGIN
  /// inside an open transaction (sqlite3 rejects it).
  void replaceImportedOccurrencesInTransaction({
    required String jobId,
    required String from,
    required String to,
    required List<ShiftOccurrence> rows,
  }) {
    _replaceImportedOccurrencesNoTxn(
        jobId: jobId, from: from, to: to, rows: rows);
  }

  void _replaceImportedOccurrencesNoTxn({
    required String jobId,
    required String from,
    required String to,
    required List<ShiftOccurrence> rows,
  }) {
    db.execute(
      'DELETE FROM occurrences WHERE jobId = ? AND isImported = 1 '
      'AND shiftDate >= ? AND shiftDate <= ?',
      [jobId, from, to],
    );
    for (final o in rows) {
      db.execute(
        '''INSERT INTO occurrences
           (uuid, id, patternId, shiftDate, templateId, startDateTimeUtc,
            endDateTimeUtc, timezone, source, sourceOverrideId,
            jobId, isImported)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          newUuid(), o.id, o.patternId, o.shiftDate, o.templateId,
          o.startDateTimeUtc, o.endDateTimeUtc, o.timezone,
          o.source.name, o.sourceOverrideId, jobId, 1,
        ],
      );
    }
  }

  /// Committed-import rows of [jobId] inside [from..to] (plan7 D-M2-1).
  List<ShiftOccurrence> importedOccurrencesInRange({
    required String jobId,
    required String from,
    required String to,
  }) {
    final rows = db.select(
      'SELECT * FROM occurrences WHERE jobId = ? AND isImported = 1 '
      'AND shiftDate >= ? AND shiftDate <= ? ORDER BY shiftDate, id',
      [jobId, from, to],
    );
    return rows.map(_occurrenceFromRow).toList();
  }

  /// OFF dates in [from..to] that the NEWEST committed import session
  /// governing that day marks as approved OFF — those days are suppressed
  /// from pattern projection (the approved roster says “no shift”, which wins
  /// over the pattern). Re-imports replace PER WINDOW: for each rendered day
  /// only the latest committed session whose [windowStart..windowEnd]
  /// contains it decides (a session whose OFF list is [] is still
  /// authoritative — “no OFF days here” overrides any earlier import for that
  /// day). Sessions whose window does not contain the day are never consulted.
  Set<String> committedOffDatesInRange({
    required String jobId,
    required String from,
    required String to,
  }) {
    // Locked window semantics (plan4 review1/3/4, Gate A §A3): a committed
    // session governs exactly the dates between its [windowStart] and
    // [windowEnd] (inclusive) — NOT the whole job, and never dates outside
    // the window even if an earlier session covered them. So this resolves
    // PER DAY: for each rendered date d in [from..to], the NEWEST committed
    // session whose window contains d decides whether d is an approved OFF
    // day (its committedOffDatesJson — even when [], which means "no OFF
    // days here" and overrides any earlier import for d).
    final sessions = db.select(
      "SELECT committedOffDatesJson, windowStart, windowEnd "
      "FROM import_sessions "
      "WHERE jobId = ? AND state = 'committed' "
      "AND windowStart IS NOT NULL AND windowEnd IS NOT NULL "
      "AND windowStart <= ? AND windowEnd >= ? "
      "ORDER BY createdAt DESC, id DESC",
      [jobId, to, from],
    );
    if (sessions.isEmpty) return {};
    final parsed = sessions.map((r) {
      final raw = r['committedOffDatesJson'] as String?;
      return (
        windowStart: r['windowStart'] as String,
        windowEnd: r['windowEnd'] as String,
        off: raw == null || raw.isEmpty
            ? <String>{}
            : (jsonDecode(raw) as List).cast<String>().toSet(),
      );
    }).toList();

    final suppressed = <String>{};
    final start = DateTime.parse(from);
    final end = DateTime.parse(to);
    var day = DateTime.utc(start.year, start.month, start.day);
    final last = DateTime.utc(end.year, end.month, end.day);
    while (!day.isAfter(last)) {
      final d =
          '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
      for (final s in parsed) {
        if (d.compareTo(s.windowStart) >= 0 &&
            d.compareTo(s.windowEnd) <= 0) {
          if (s.off.contains(d)) suppressed.add(d);
          break; // newest governing session already decided this day
        }
      }
      day = day.add(const Duration(days: 1));
    }
    return suppressed;
  }

  List<ShiftOccurrence> occurrencesInRange({
    String? patternId,
    required String from,
    required String to,
  }) {
    final rows = patternId == null
        ? db.select(
            'SELECT * FROM occurrences WHERE shiftDate >= ? AND shiftDate <= ? '
            'ORDER BY shiftDate, id',
            [from, to])
        : db.select(
            'SELECT * FROM occurrences WHERE patternId = ? '
            'AND shiftDate >= ? AND shiftDate <= ? ORDER BY shiftDate, id',
            [patternId, from, to]);
    return rows.map(_occurrenceFromRow).toList();
  }

  /// Set the INVARIANT-006 pay snapshot. Refuses to CHANGE an existing value.
  void setPayEstimateSnapshot({
    required String occurrenceId,
    required double amount,
    required String payRuleFrom,
  }) {
    final rows = db.select(
        'SELECT actualPayEstimate FROM occurrences WHERE id = ?',
        [occurrenceId]);
    if (rows.isEmpty) {
      throw ImmutableHistoryError(
          'Cannot snapshot unknown occurrence $occurrenceId');
    }
    final existing = rows.first['actualPayEstimate'] as double?;
    if (existing != null && (existing - amount).abs() > 0.005) {
      throw ImmutableHistoryError(
          'Occurrence $occurrenceId already carries snapshot $existing; '
          'refusing to rewrite history to $amount (INVARIANT-006).');
    }
    db.execute(
      '''UPDATE occurrences SET actualPayEstimate = ?, payEstimateFrom = ?,
         committedAt = COALESCE(committedAt, ?)
       WHERE id = ?''',
      [amount, payRuleFrom, DateTime.now().toUtc().toIso8601String(),
        occurrenceId],
    );
  }

  /// Append an override to the audit log. The log is append-only and each row
  /// is immutable once written (Gate C A3 / D-C3):
  ///   - unknown id            → INSERT (append)
  ///   - same id + IDENTICAL payload → idempotent no-op success (re-run safe)
  ///   - same id + DIFFERENT payload → [ImmutableHistoryError] — NEVER a
  ///     silent return and NEVER an overwrite of the stored history.
  /// Deep equality covers the full override contract: operation, target
  /// occurrence id, swap target, reason and the operation payload (times,
  /// templateId, shift date, split parts).
  ///
  /// CREATE convention (official): a CREATE override produces an occurrence
  /// whose id IS the override id — it is not rooted to any baseline
  /// occurrence, so the render-time log filter cannot scope it by baseline
  /// root. Callers MUST pass [patternId] = the pattern whose schedule the new
  /// occurrence is added to (the row records it; renders include the CREATE
  /// iff that pattern is rendered AND the payload date is in range — plan4
  /// §4 overridesFor(patternId, range)). For every other operation [patternId]
  /// is ignored (scope comes from the target occurrence's baseline root).
  void saveOverride(Override o, {String? patternId}) {
    if (o.operation == OverrideOperation.create &&
        (patternId == null || patternId.isEmpty)) {
      throw ArgumentError(
          'CREATE override ${o.id} requires patternId (the pattern whose '
          'schedule the new occurrence belongs to) — official persistence '
          'convention.');
    }
    final existing =
        db.select('SELECT * FROM overrides WHERE id = ?', [o.id]);
    if (existing.isNotEmpty) {
      final row = existing.first;
      final stored = overrideFromRow(
        id: row['id'] as String,
        occurrenceId: row['occurrenceId'] as String,
        operation: OverrideOperation.values.firstWhere(
            (op) => op.name == (row['operation'] as String)),
        payloadJson: row['payloadJson'] as String,
        swapWithOccurrenceId: row['swapWithOccurrenceId'] as String?,
        createdAt: row['createdAt'] as String,
        reasonName: row['reason'] as String?,
      );
      final samePatternId =
          o.operation != OverrideOperation.create ||
              (row['patternId'] as String?) == patternId;
      if (!_sameOverrideContract(stored, o) || !samePatternId) {
        throw ImmutableHistoryError(
            'Override ${o.id} already exists with a DIFFERENT payload; '
            'refusing to silently overwrite the append-only log (Gate C §A3). '
            'Same-id re-saves must carry an identical payload.');
      }
      return; // idempotent no-op
    }
    db.execute(
      '''INSERT INTO overrides
         (uuid, id, occurrenceId, operation, payloadJson,
          swapWithOccurrenceId, createdAt, reason, patternId)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        newUuid(), o.id, o.occurrenceId, o.operation.name,
        jsonEncode(payloadToJson(o)), o.swapWithOccurrenceId, o.createdAt,
        o.reason?.name,
        o.operation == OverrideOperation.create ? patternId : null,
      ],
    );
  }

  /// Whether [stored] and [newOverride] describe the SAME immutable history
  /// entry (Gate C A3): operation, target occurrence, swap target, reason and
  /// the operation payload all deep-equal. createdAt deliberately excluded — a
  /// deterministic-id retry that reconstructs the identical edit may carry a
  /// fresh timestamp and must still be an idempotent no-op.
  bool _sameOverrideContract(Override stored, Override newOverride) {
    if (stored.operation != newOverride.operation ||
        stored.occurrenceId != newOverride.occurrenceId ||
        stored.swapWithOccurrenceId != newOverride.swapWithOccurrenceId ||
        stored.reason != newOverride.reason) {
      return false;
    }
    return _jsonDeepEqual(
        payloadToJson(stored), payloadToJson(newOverride));
  }

  /// Structural equality over decoded JSON trees (Map keys order-insensitive,
  /// List order-sensitive) — used to compare stored vs incoming override
  /// payloads without depending on map key insertion order.
  bool _jsonDeepEqual(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k)) return false;
        if (!_jsonDeepEqual(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_jsonDeepEqual(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// All stored overrides affecting [occurrenceIds], oldest first.
  List<Override> overridesAffecting(List<String> occurrenceIds) {
    if (occurrenceIds.isEmpty) return const [];
    final placeholders = List.filled(occurrenceIds.length, '?').join(',');
    final rows = db.select(
      'SELECT * FROM overrides WHERE occurrenceId IN ($placeholders) '
      'ORDER BY createdAt, id',
      occurrenceIds,
    );
    return rows.map(_overrideFromRow).toList();
  }

  /// Replay stored overrides over [baseline] in log order through the engine.
  /// Failing overrides surface as issues and leave the list unchanged (the
  /// engine's own command-level atomicity) — nothing is silently dropped.
  ScheduleRenderResult replayOverrides(
    List<ShiftOccurrence> baseline,
    List<Override> overrides,
    Map<String, ShiftTemplate> templates,
  ) {
    var current = List<ShiftOccurrence>.from(baseline);
    final issues = <RenderIssue>[];
    for (final o in overrides) {
      final result = applyOverride(current, o, templates: templates);
      if (result.isSuccess) {
        current = result.occurrences;
      } else {
        issues.addAll(result.issues);
      }
    }
    return ScheduleRenderResult(occurrences: current, issues: issues);
  }

  /// Render a job's effective schedule for [rangeStart..rangeEnd] by running
  /// the PURE engine over persisted patterns/templates/overrides, then
  /// persisting the resulting occurrences. Returns engine-parity results.
  ScheduleRenderResult renderJobSchedule({
    required String jobId,
    required String rangeStart,
    required String rangeEnd,
    bool persist = true,
  }) {
    final templates = patterns.templatesForJob(jobId);
    final templateMap = {for (final t in templates) t.id: t};

    // Versions whose window overlaps the requested range (pattern_repository
    // owns the row -> object mapping; newest versions come last in the list).
    final versions = patterns.patternsOverlapping(
        jobId: jobId, from: rangeStart, to: rangeEnd);

    final patternBaseline = <ShiftOccurrence>[];
    final issues = <RenderIssue>[];

    for (final pattern in versions) {
      final segStart = pattern.effectiveFrom.compareTo(rangeStart) > 0
          ? pattern.effectiveFrom
          : rangeStart;
      final segEnd = pattern.effectiveUntil == null ||
              pattern.effectiveUntil!.compareTo(rangeEnd) > 0
          ? rangeEnd
          : pattern.effectiveUntil!;
      final projection = projectOccurrences(
        pattern: pattern,
        rangeStart: segStart,
        rangeEnd: segEnd,
        templates: templates,
      );
      patternBaseline.addAll(projection.occurrences);
      issues.addAll(projection.issues);
    }

    // ---- Import-commit merge (plan7 D-M2-1, option A) ----------------------
    // An APPROVED import roster is the authoritative schedule for its dates.
    // Its committed rows replace the previous import of this job in the same
    // window, and the days it covers — shifts AND recorded OFF days of the
    // NEWEST committed session — suppress the pattern projection for those
    // days (the roster says what actually happens). Dates the roster does not
    // mention keep pattern behaviour (mixed windows stay correct). Imported
    // rows join the baseline BEFORE override replay, so a later override can
    // target an imported shift (its root is in the allowed set). Overrides
    // that predate an import and targeted a suppressed pattern day surface as
    // engine issues at replay — never silently dropped.
    final imported =
        importedOccurrencesInRange(jobId: jobId, from: rangeStart, to: rangeEnd);
    final suppressed =
        committedOffDatesInRange(jobId: jobId, from: rangeStart, to: rangeEnd)
          ..addAll(imported.map((o) => o.shiftDate));
    final baseline = <ShiftOccurrence>[
      ...patternBaseline.where((o) => !suppressed.contains(o.shiftDate)),
      ...imported,
    ];

    // Admission pass over the WHOLE log, in chronological order (plan3 P0-6:
    // each override applies on the state the previous one left). An override
    // is admitted when it belongs to THIS render:
    //   - targeted ops (UPDATE/DELETE/REPLACE/SPLIT/SWAP) whose occurrence
    //     root is the rendered baseline OR was produced by an admitted
    //     override (split parts '<root>#pN', created occurrences whose id IS
    //     the CREATE override's id — the chain must survive re-render);
    //   - CREATE overrides whose patternId is rendered in this range AND whose
    //     payload date falls inside the requested range (they have no baseline
    //     root to match — the row records patternId + the render compares the
    //     date; official CREATE convention, plan4 overridesFor(patternId,
    //     range)).
    // Admitted CREATE ids widen the allowed-root set so later overrides can
    // chain onto the created occurrence. Overrides of other patterns/jobs are
    // excluded; an admitted override that still finds no target at apply time
    // surfaces as an engine issue — never silently dropped.
    final renderedPatternIds = versions.map((p) => p.id).toSet();
    final allowedRoots = baseline.map((o) => o.id.split('#').first).toSet();
    final rows = db.select('SELECT * FROM overrides ORDER BY createdAt, id');
    final log = <Override>[];
    for (final r in rows) {
      final o = _overrideFromRow(r);
      final isCreate = o.operation == OverrideOperation.create;
      final root = o.occurrenceId.split('#').first;
      final belongs = isCreate
          ? _createInRender(
              r, o, renderedPatternIds, rangeStart, rangeEnd, jobId)
          : allowedRoots.contains(root);
      if (!belongs) continue;
      log.add(o);
      if (isCreate) {
        // The occurrence this CREATE produces carries the override's id;
        // later overrides chain onto it through that id.
        allowedRoots.add(o.id);
      }
    }

    final result =
        replayOverrides(baseline, log, templateMap);
    final effective = ScheduleRenderResult(
      occurrences: result.occurrences,
      issues: [...issues, ...result.issues],
    );

    if (persist) {
      saveOccurrencesForJob(
        jobId: jobId,
        from: rangeStart,
        to: rangeEnd,
        occurrences: effective.occurrences,
      );
    }
    return effective;
  }

  // -- row mappers ------------------------------------------------------------

  ShiftOccurrence _occurrenceFromRow(Row r) {
    return ShiftOccurrence(
      id: r['id'] as String,
      patternId: r['patternId'] as String,
      shiftDate: r['shiftDate'] as String,
      templateId: r['templateId'] as String,
      startDateTimeUtc: r['startDateTimeUtc'] as String,
      endDateTimeUtc: r['endDateTimeUtc'] as String,
      timezone: r['timezone'] as String,
      source: OccurrenceSource.values.firstWhere(
          (s) => s.name == (r['source'] as String),
          orElse: () => OccurrenceSource.baseline),
      sourceOverrideId: r['sourceOverrideId'] as String?,
      actualPayEstimate: r['actualPayEstimate'] as double?,
      payEstimateFrom: r['payEstimateFrom'] as String?,
      jobId: r['jobId'] as String?,
      isImported: (r['isImported'] as int?) == 1,
    );
  }

  Override _overrideFromRow(Row r) {
    return overrideFromRow(
      id: r['id'] as String,
      occurrenceId: r['occurrenceId'] as String,
      operation: OverrideOperation.values.firstWhere(
          (op) => op.name == (r['operation'] as String)),
      payloadJson: r['payloadJson'] as String,
      swapWithOccurrenceId: r['swapWithOccurrenceId'] as String?,
      createdAt: r['createdAt'] as String,
      reasonName: r['reason'] as String?,
    );
  }

  /// A CREATE override belongs to this render iff its recorded [patternId]
  /// (row column, not a domain field) is among the rendered pattern ids and
  /// its payload date is inside the range. (CREATE rows carry patternId from
  /// saveOverride — the official convention; the engine ignores occurrenceId
  /// for CREATE.)
  ///
  /// RC plan §A2 — sentinel admission: a CREATE attached to the job's
  /// imported-schedule sentinel (importedSchedulePatternId) belongs to THIS
  /// job's render even when no pattern version covers the date (imported-only
  /// roster, or a gap between versions). The sentinel embeds the job id, so
  /// it can never admit another job's CREATE. A real pattern is never
  /// fabricated to pass CREATE validation.
  bool _createInRender(
    Row r,
    Override o,
    Set<String> renderedPatternIds,
    String rangeStart,
    String rangeEnd,
    String jobId,
  ) {
    final patternId = r['patternId'] as String?;
    if (patternId == null) return false;
    final isJobSentinel = patternId == importedSchedulePatternId(jobId);
    if (!isJobSentinel && !renderedPatternIds.contains(patternId)) {
      return false;
    }
    final p = o.createPayload;
    if (p == null) return false;
    return p.date.compareTo(rangeStart) >= 0 && p.date.compareTo(rangeEnd) <= 0;
  }

}

