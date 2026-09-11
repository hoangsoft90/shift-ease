// =============================================================================
// ShiftEase Import Pipeline — Engine (plan2 §3.1–§3.4)
// =============================================================================
//
// Pure and deterministic. Sections:
//   1. parseDocument      — pick parser per sourceType, refuse OCR-gated
//                           IMAGE/PDF until the M4.5 spike test passes.
//   2. Interpretation     — date resolution + shift-type/template suggestion +
//                           confidence scoring (plan2 §3.2 Bước 2 matrix).
//   3. Review             — approve/reject/modify + bulk ACCEPT_ALL_HIGH.
//   4. Commit             — INVARIANT-004 gate; UTC via core/time resolveShift
//                           (INVARIANT-002); atomic — one unresolvable approved
//                           candidate blocks the whole commit.
//   5. Re-import diff     — plan2 §3.4 "What changed?" with swap-pairing.
//
// NEVER: auto-commit anything (INVARIANT-004), resolve local times here
// (INVARIANT-002), guess the reference period from the system clock, or build
// OCR plumbing before the spike gate.
// =============================================================================

import 'package:shiftease/core/time/time_engine.dart' show resolveShift;

import 'import_parser.dart';
import 'import_types.dart';

/// A template known to the job being imported into — used ONLY to suggest a
/// templateId and (when the line has no label) infer a shift type. Templates
/// live with the job; the import engine does not own them.
class TemplateSpec {
  final String id;
  final String name;
  final String startTime; // "HH:mm" (end may carry "+1")
  final String endTime;

  const TemplateSpec({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
  });
}

// =============================================================================
// 1. Parse entry point
// =============================================================================

ImportSession parseDocument({
  required ImportSourceType sourceType,
  String? rawText,
  String? rawCsv,
  Map<String, String>? columnMapping,
  required List<TemplateSpec> templates,
  required String referenceDate, // user-chosen roster period anchor
  required String timezone, // job timezone (INVARIANT-007 at commit)
  String? id,
  String? createdAt,
}) {
  final sessionId = id ?? 'session-${DateTime.now().microsecondsSinceEpoch}';
  final created = createdAt ?? DateTime.now().toUtc().toIso8601String();

  ImportSession idleSession() => ImportSession(
        id: sessionId,
        createdAt: created,
        sourceType: sourceType,
        state: ImportState.idle,
        referenceDate: referenceDate,
        timezone: timezone,
        rawExtraction:
            RawExtraction(sourceType: sourceType, entries: const []),
        candidates: const [],
        committedOccurrenceIds: const [],
      );

  ImportSession fail(ImportError error, {required List<ImportState> history}) =>
      idleSession().copyWith(
        state: ImportState.error,
        history: history,
        error: error,
      );

  // OCR-gated sources: no speculative OCR architecture before the M4.5 spike
  // (features.md: >=70% dates, >=60% shift types on 20-30 real rosters).
  if (sourceType == ImportSourceType.image ||
      sourceType == ImportSourceType.pdf) {
    return fail(
      const ImportError(
        code: ImportErrorCodes.ocrPendingSpike,
        message: 'IMAGE/PDF import needs OCR, which is gated behind the M4.5 '
            'spike test on 20-30 real rosters. Paste text or use CSV for now.',
        recoverable: true,
      ),
      history: const [
        ImportState.idle,
        ImportState.parsing,
        ImportState.error
      ],
    );
  }

  SourceParseResult parsed;
  if (sourceType == ImportSourceType.csv) {
    if (rawCsv == null) {
      return fail(
        const ImportError(
            code: ImportErrorCodes.invalidPayload,
            message: 'CSV import requires rawCsv input.',
            recoverable: true),
        history: const [
          ImportState.idle,
          ImportState.parsing,
          ImportState.error
        ],
      );
    }
    parsed = parseCsvRoster(rawCsv, columnMapping: columnMapping);
  } else {
    if (rawText == null) {
      return fail(
        const ImportError(
            code: ImportErrorCodes.invalidPayload,
            message: 'PASTE_TEXT import requires rawText input.',
            recoverable: true),
        history: const [
          ImportState.idle,
          ImportState.parsing,
          ImportState.error
        ],
      );
    }
    parsed = SourceParseResult(extraction: parseTextRoster(rawText));
  }

  if (!parsed.isSuccess) {
    return fail(parsed.error!,
        history: const [
          ImportState.idle,
          ImportState.parsing,
          ImportState.error
        ]);
  }

  final extraction = parsed.extraction!;
  final candidates = _interpret(
    extraction,
    templates: templates,
    referenceDate: referenceDate,
  );

  return ImportSession(
    id: sessionId,
    createdAt: created,
    sourceType: sourceType,
    state: ImportState.extracted,
    referenceDate: referenceDate,
    timezone: timezone,
    rawExtraction: extraction,
    candidates: candidates,
    committedOccurrenceIds: const [],
    history: const [
      ImportState.idle,
      ImportState.parsing,
      ImportState.extracted
    ],
  );
}

// =============================================================================
// 2. Schedule interpretation (plan2 §3.2 Bước 2)
// =============================================================================

/// Resolve raw entries into candidates: dates pinned to the reference period,
/// OFF days separated, shift types labelled/inferred, templates suggested,
/// confidence scored per the locked matrix.
List<CandidateShift> _interpret(
  RawExtraction extraction, {
  required List<TemplateSpec> templates,
  required String referenceDate,
}) {
  final candidates = <CandidateShift>[];
  var index = 0;
  for (final entry in extraction.entries) {
    index++;
    if (entry.original.isEmpty) continue;

    final date = entry.dateToken == null
        ? null
        : resolveDateToken(entry.dateToken!, referenceDate: referenceDate);

    final isOff = entry.shiftTypeLabel?.toLowerCase() == 'off';
    final kind = isOff
        ? ShiftKind.off
        : (entry.startTime != null && entry.endTime != null)
            ? ShiftKind.shift
            : ShiftKind.unknown;

    // Template suggestion + inferred shift type (label takes precedence).
    String? templateId;
    String? inferredType;
    if (kind == ShiftKind.shift) {
      final matched = templates
          .where((t) =>
              t.startTime == entry.startTime && t.endTime == entry.endTime)
          .toList();
      if (matched.length == 1) {
        templateId = matched.first.id;
        inferredType = matched.first.name;
      }
    }

    final explicitType = entry.shiftTypeLabel;
    final shiftType = explicitType ??
        (kind == ShiftKind.shift ? inferredType : null);

    // ---- Confidence factors (matrix §3.2) — overall = the WEAKEST factor
    // (largest index: low=2 > medium=1 > high=0). A missing label demotes a
    // perfectly clear time+date line to MEDIUM (IMPORT-006); a missing date
    // demotes everything to LOW (IMPORT-002).
    Confidence weakest(Confidence a, Confidence b) =>
        a.index >= b.index ? a : b;
    final dateFactor = date != null ? Confidence.high : Confidence.low;
    Confidence typeFactor;
    String? note;
    if (explicitType != null && explicitType.isNotEmpty) {
      typeFactor = Confidence.high; // "Day"/"Night"/"Off" stated
    } else if (kind == ShiftKind.shift && inferredType != null) {
      typeFactor = Confidence.medium; // inferred from exact template match
      note = 'Time matches ${templateId} exactly, but no shift type label in '
          'input — MEDIUM not HIGH.';
    } else {
      typeFactor = Confidence.low;
      note = 'No shift type and no exact template match — needs review.';
    }
    final timeFactor = kind == ShiftKind.shift &&
            (entry.startTime == null || entry.endTime == null)
        ? Confidence.low
        : Confidence.high; // OFF / rest lines need no clock times

    var overall = weakest(dateFactor, weakest(timeFactor, typeFactor));

    if (entry.hasGarbage) {
      overall = Confidence.low;
      note = 'Line contains uninterpretable tokens ("${entry.original}").';
    }
    // A line that cannot be pinned to a real date is LOW regardless of how
    // clearly its other fields read (commit requires a date).
    if (date == null) overall = Confidence.low;

    candidates.add(CandidateShift(
      id: 'cand-$index',
      data: CandidateData(
        date: date,
        templateId: templateId,
        startTime: entry.startTime,
        endTime: entry.endTime,
        shiftType: shiftType ?? (isOff ? 'OFF' : '?'),
        kind: kind,
      ),
      confidence: overall,
      note: note,
    ));
  }
  return candidates;
}

// =============================================================================
// 3. Review actions
// =============================================================================

/// Apply one user review action (approve/reject/modify on one candidate, or
/// the bulk ACCEPT_ALL_HIGH). The session moves to [ImportState.reviewing]
/// on its first review action. Errors (unknown candidate, reviewing a
/// committed/errored session) surface as session errors — never silent.
ImportSession applyReview(
  ImportSession session, {
  String? candidateId,
  required ReviewAction action,
  CandidateData? edits, // for modify
}) {
  if (session.state == ImportState.committed) {
    return session.copyWith(
      state: ImportState.error,
      history: [...session.history, ImportState.error],
      error: const ImportError(
          code: ImportErrorCodes.illegalState,
          message: 'Cannot review a committed session.',
          recoverable: false),
    );
  }
  if (session.state == ImportState.error) {
    return session.copyWith(
      state: ImportState.error,
      history: [...session.history, ImportState.error],
      error: const ImportError(
          code: ImportErrorCodes.illegalState,
          message: 'Cannot review an errored session — re-parse first.',
          recoverable: true),
    );
  }

  final reviewing = session.transitionTo(ImportState.reviewing);
  final candidates = List<CandidateShift>.from(session.candidates);

  if (action == ReviewAction.bulkAcceptAllHigh) {
    for (var i = 0; i < candidates.length; i++) {
      if (candidates[i].reviewStatus == ReviewStatus.pending &&
          candidates[i].confidence == Confidence.high) {
        candidates[i] =
            candidates[i].copyWith(reviewStatus: ReviewStatus.approved);
      }
    }
    return reviewing.copyWith(candidates: candidates, error: null);
  }

  if (candidateId == null) {
    return session.copyWith(
      state: ImportState.error,
      history: [...session.history, ImportState.error],
      error: const ImportError(
          code: ImportErrorCodes.invalidPayload,
          message: 'Single-candidate review actions require a candidateId.',
          recoverable: true),
    );
  }
  final idx = session.candidates.indexWhere((c) => c.id == candidateId);
  if (idx < 0) {
    return session.copyWith(
      state: ImportState.error,
      history: [...session.history, ImportState.error],
      error: ImportError(
          code: ImportErrorCodes.candidateNotFound,
          message: 'No candidate with id $candidateId.',
          recoverable: true),
    );
  }

  switch (action) {
    case ReviewAction.approve:
      candidates[idx] = candidates[idx]
          .copyWith(reviewStatus: ReviewStatus.approved);
    case ReviewAction.reject:
      candidates[idx] = candidates[idx]
          .copyWith(reviewStatus: ReviewStatus.rejected);
    case ReviewAction.modify:
      final current = candidates[idx];
      final d = current.data;
      var start = edits?.startTime ?? d.startTime;
      var end = edits?.endTime ?? d.endTime;
      final timesChanged = start != null &&
          end != null &&
          (start != d.startTime || end != d.endTime);
      var kind = d.kind;
      if (timesChanged) {
        final norm = normalizeTimePair(start, end);
        if (norm != null) {
          start = norm.start;
          end = norm.end;
        }
        kind = ShiftKind.shift;
      }
      if ((edits?.shiftType ?? '').toLowerCase() == 'off') {
        kind = ShiftKind.off;
        start = null;
        end = null;
      }
      candidates[idx] = candidates[idx].copyWith(
        data: d.copyWith(
          date: edits?.date ?? d.date,
          templateId: edits?.templateId ?? d.templateId,
          startTime: start,
          endTime: end,
          shiftType: edits?.shiftType ?? d.shiftType,
          kind: kind,
        ),
        reviewStatus: ReviewStatus.modified,
        note: 'User-modified during review.',
      );
    case ReviewAction.bulkAcceptAllHigh:
      break; // handled above
  }

  return reviewing.copyWith(candidates: candidates, error: null);
}

/// Bulk action convenience: approve every HIGH-confidence PENDING candidate
/// (plan2 §3.2 — "Accept All High"); MEDIUM/LOW always stay PENDING.
ImportSession bulkAcceptHigh(ImportSession session) => applyReview(
      session,
      action: ReviewAction.bulkAcceptAllHigh,
    );

// =============================================================================
// 4. Commit (INVARIANT-004 + INVARIANT-002)
// =============================================================================

/// Commit every APPROVED/MODIFIED candidate.
///
/// INVARIANT-004: nothing below happens without the explicit COMMIT call.
/// Atomic: every approved shift candidate is validated and UTC-resolved
/// BEFORE anything is recorded — one unresolvable candidate (missing
/// date/time, DST gap/overlap, end-before-start) aborts the whole commit
/// with COMMIT_UNRESOLVED and zero changes recorded.
CommitResult commitImport(ImportSession session) {
  // Gate C (A1 / D-C1): the ONLY legal commit transition is REVIEWING ->
  // COMMITTED. EXTRACTED means the candidates were generated but never
  // reviewed — committing straight from there would bypass the review step
  // (INVARIANT-004's "explicit review first" intent). idle / error /
  // committed are equally illegal. Never silently accepted.
  if (session.state != ImportState.reviewing) {
    const err = ImportError(
      code: ImportErrorCodes.illegalState,
      message: 'Commit requires a REVIEWING session. Call applyReview before '
          'commit (EXTRACTED is not enough).',
      recoverable: true,
    );
    return CommitResult(
      session: session.copyWith(
        state: ImportState.error,
        history: [...session.history, ImportState.error],
        error: err,
      ),
      error: err,
    );
  }

  final actionable = session.candidates
      .where((c) =>
          c.reviewStatus == ReviewStatus.approved ||
          c.reviewStatus == ReviewStatus.modified)
      .toList();

  // A REVIEWING session with nothing approved/modified has nothing to
  // commit — fail loudly instead of silently committing an empty roster.
  if (actionable.isEmpty) {
    const err = ImportError(
      code: ImportErrorCodes.illegalState,
      message: 'Commit requires at least one APPROVED or MODIFIED row. '
          'Approve at least 1 row before commit.',
      recoverable: true,
    );
    return CommitResult(
      session: session.copyWith(
        state: ImportState.error,
        history: [...session.history, ImportState.error],
        error: err,
      ),
      error: err,
    );
  }

  // Phase 1 — validate every actionable candidate (atomicity).
  final unresolved = <String>[];
  final toResolve = <CandidateShift>[];
  final offDates = <String>[];
  for (final c in actionable) {
    if (c.data.kind == ShiftKind.off) {
      if (c.data.date == null) {
        unresolved.add(c.id);
      } else {
        offDates.add(c.data.date!);
      }
      continue;
    }
    if (!c.data.resolvable) {
      unresolved.add(c.id);
      continue;
    }
    toResolve.add(c);
  }
  if (unresolved.isNotEmpty) {
    final err = ImportError(
      code: ImportErrorCodes.commitUnresolved,
      message: 'Cannot commit — approved candidate(s) ${unresolved.join(', ')} '
          'lack a resolvable date/time. Review them first.',
      recoverable: true,
      candidateIds: unresolved,
    );
    return CommitResult(
      session: session.copyWith(state: ImportState.error, error: err),
      error: err,
    );
  }

  // RC plan §A5 — conflict validation. The engine NEVER picks a winner to
  // "make the commit run": approved candidates that contradict each other
  // block the whole commit until the user resolves them.
  //   - OFF + SHIFT on the same date: the roster cannot both rest and work.
  //   - two identical shifts on the same date: duplicate candidate identity.
  final byDate = <String, List<CandidateShift>>{};
  for (final c in actionable) {
    if (c.data.date == null) continue; // unresolvable already reported above
    byDate.putIfAbsent(c.data.date!, () => []).add(c);
  }
  final conflictMsgs = <String>[];
  for (final entry in byDate.entries) {
    final cands = entry.value;
    final hasOff = cands.any((c) => c.data.kind == ShiftKind.off);
    final shifts = cands.where((c) => c.data.kind == ShiftKind.shift);
    if (hasOff && shifts.isNotEmpty) {
      conflictMsgs.add('${entry.key}: OFF and SHIFT both approved');
      continue;
    }
    final seen = <String>{};
    for (final c in shifts) {
      final key = '${c.data.startTime}|${c.data.endTime}';
      if (!seen.add(key)) {
        conflictMsgs.add('${entry.key}: duplicate shift '
            '${c.data.startTime}-${c.data.endTime}');
        break;
      }
    }
  }
  if (conflictMsgs.isNotEmpty) {
    final err = ImportError(
      code: ImportErrorCodes.conflict,
      message: 'Cannot commit — approved candidates conflict: '
          '${conflictMsgs.join('; ')}. Review and fix them first.',
      recoverable: true,
      candidateIds: actionable.map((c) => c.id).toList(),
    );
    return CommitResult(
      session: session.copyWith(state: ImportState.error, error: err),
      error: err,
    );
  }

  // Phase 2 — resolve UTC via core/time (INVARIANT-002); still nothing
  // recorded until every candidate resolved cleanly.
  final shifts = <CommittedShift>[];
  for (final c in toResolve) {
    final resolution = resolveShift(
      shiftDate: c.data.date!,
      startTime: c.data.startTime!,
      endTime: c.data.endTime!,
      timezone: session.timezone,
    );
    if (!resolution.isSuccess) {
      final err = ImportError(
        code: ImportErrorCodes.commitUnresolved,
        message: 'Cannot commit candidate ${c.id} (${c.data.date} '
            '${c.data.startTime}-${c.data.endTime} in ${session.timezone}): '
            '${resolution.error}. ${resolution.note ?? ''}',
        recoverable: true,
        candidateIds: [c.id],
      );
      return CommitResult(
        session: session.copyWith(state: ImportState.error, error: err),
        error: err,
      );
    }
    shifts.add(CommittedShift(
      candidateId: c.id,
      occurrenceId: 'occ-${c.id}',
      shiftDate: c.data.date!,
      templateId: c.data.templateId,
      startDateTimeUtc: resolution.utcStart!.isoString,
      endDateTimeUtc: resolution.utcEnd!.isoString,
      timezone: session.timezone,
    ));
  }

  final committedIds = shifts.map((s) => s.occurrenceId).toList();
  final committed = session.copyWith(
    state: ImportState.committed,
    committedOccurrenceIds: committedIds,
    committedOffDates: offDates,
    error: null,
    history: [...session.history, ImportState.committed],
  );

  // Attach the import window to the committed session. The window covers
  // the FULL range of committed dates (shifts + OFF days), not just
  // approved days — a roster is authoritative for its whole window (Gate A
  // §A3). Callers without any committed dates keep the session's existing
  // window (typically null at first commit, or a prior window if the engine
  // returned a pre-windowed copy — which it does not do here, but be safe).
  final shifted = shifts.map((s) => s.shiftDate).toSet();
  final allDates = {...shifted, ...offDates};
  final sessionWindow =
      allDates.isEmpty
          ? null
          : committed.withWindow(
              allDates.toList()..sort()
            );

  return CommitResult(
    session: sessionWindow ?? committed,
    shifts: shifts,
    committedOffDates: offDates,
  );
}

// =============================================================================
// 5. Re-import diff (plan2 §3.4)
// =============================================================================

/// Compare the previous roster's extraction with a new one, keyed by date.
/// Two dates whose content swapped between old and new are reported as a pair
/// of SWAPPED entries (not two unrelated CHANGEDs) — the shape employers
/// actually send when two people/rotations trade days.
ImportDiff computeImportDiff({
  required List<DiffEntry> previous,
  required List<DiffEntry> next,
}) {
  String content(DiffEntry e) =>
      '${e.shiftType}|${e.start ?? ''}|${e.end ?? ''}';

  final prevByDate = {for (final e in previous) e.date: e};
  final nextByDate = {for (final e in next) e.date: e};

  final removed = <DiffItem>[];
  final added = <DiffItem>[];
  var modified = <DiffItem>[];
  final unchanged = <DiffItem>[];

  for (final e in previous) {
    final n = nextByDate[e.date];
    if (n == null) {
      removed.add(DiffItem(
          date: e.date, changeType: DiffChangeType.removed, from: e.shiftType));
    } else if (content(e) == content(n)) {
      unchanged.add(DiffItem(
          date: e.date, changeType: DiffChangeType.unchanged, to: n.shiftType));
    } else {
      modified.add(DiffItem(
          date: e.date,
          changeType: DiffChangeType.changed,
          from: e.shiftType,
          to: n.shiftType));
    }
  }
  for (final e in next) {
    if (!prevByDate.containsKey(e.date)) {
      added.add(DiffItem(
          date: e.date,
          changeType: DiffChangeType.added,
          to: e.shiftType));
    }
  }

  // Swap-pairing: any two CHANGED entries A->B and B->A are one exchange.
  for (var i = 0; i < modified.length; i++) {
    for (var j = i + 1; j < modified.length; j++) {
      final a = modified[i];
      final b = modified[j];
      if (a.from == b.to && a.to == b.from) {
        modified[i] = DiffItem(
            date: a.date,
            changeType: DiffChangeType.swapped,
            from: a.from,
            to: a.to);
        modified[j] = DiffItem(
            date: b.date,
            changeType: DiffChangeType.swapped,
            from: b.from,
            to: b.to);
      }
    }
  }

  double hoursOf(String? start, String? end) {
    if (start == null || end == null) return 0;
    final norm = normalizeTimePair(start, end);
    if (norm == null) return 0;
    double mins(String t) {
      final marker = t.contains('+1') ? 1440.0 : 0.0;
      final p = t.replaceAll('+1', '').split(':');
      return double.parse(p[0]) * 60 + double.parse(p[1]) + marker;
    }
    return (mins(norm.end) - mins(norm.start)) / 60.0;
  }

  var hoursChanged = 0.0;
  for (final m in modified) {
    final prev = prevByDate[m.date];
    final nxt = nextByDate[m.date];
    hoursChanged +=
        hoursOf(nxt?.start, nxt?.end) - hoursOf(prev?.start, prev?.end);
  }

  final impact = ImportImpact(
    totalHoursChanged: hoursChanged,
    daysChanged: modified.length,
    daysAdded: added.length,
    daysRemoved: removed.length,
  );

  return ImportDiff(
    added: added,
    removed: removed,
    modified: modified,
    unchanged: unchanged,
    impact: impact,
  );
}
