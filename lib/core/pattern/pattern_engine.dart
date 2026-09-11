// =============================================================================
// ShiftEase Pattern Engine — Core Implementation (Gate 0 hardening)
// =============================================================================
//
// ARCHITECTURAL INVARIANTS:
//
// INVARIANT-001: Pattern never mutates because an occurrence is edited.
//   Pattern only changes via creating a new version (D1).
//
// INVARIANT-002: Duration is always calculated from resolved UTC instants,
//   never from local-time subtraction. Delegated to core/time.
//
// INVARIANT-003: Local civil time is the basis of recurrence.
//
// INVARIANT-007: timezone is fixed at creation time, never changes. No
//   override operation copies a timezone between occurrences.
//
// Gate 0 (plan3_final.md + plan3_final_v2.md):
// - D1 resolved-only domain: this engine NEVER constructs a ShiftOccurrence
//   with empty startDateTimeUtc/endDateTimeUtc/timezone. Every override
//   resolves through core/time first; a failed resolution returns the input
//   list unchanged plus a RenderIssue.
// - P0-4: every non-CREATE operation whose occurrenceId is missing returns
//   OCCURRENCE_NOT_FOUND — never a silent no-op.
// - P0-5: source (OccurrenceSource) is assigned directly where each operation
//   runs; sourceOverrideId is audit trail only and NEVER used to derive
//   source at render time.
// - P0-6 command-level atomicity: each override is applied independently in
//   list order. A failing override leaves the list as after the previous
//   override, adds its issue, and does NOT block or roll back later ones.
// - H-1 SPLIT invariants: parts chronological, non-overlapping, inside the
//   original occurrence's UTC envelope (except a valid shared boundary
//   between consecutive parts); any violation fails the whole SPLIT.
//
// NEVER:
// - mutate Pattern when editing an occurrence
// - silently drop unresolved occurrences / override failures
// - create an occurrence with empty temporal fields "for the caller to fill"
// - write timezone/DST logic — always delegate to core/time
// - re-resolve UTC when an UPDATE's civil time intent is unchanged (P0-2)
// - use bare error-code string literals — reference ErrorCodes.*
//
// =============================================================================

import 'package:shiftease/core/time/time_engine.dart';
import 'package:shiftease/core/time/time_types.dart';
import 'package:timezone/timezone.dart' as tz;
import 'pattern_types.dart';

// =============================================================================
// 1. projectOccurrences — resolved-only projection (P0-3)
// =============================================================================

/// Project baseline occurrences from a pattern within a date range.
///
/// INVARIANT-003: recurrence is anchored on local civil time.
/// INVARIANT-002: UTC resolution is delegated to core/time's resolveShift().
///
/// P0-3 / D1: the returned [ProjectionResult.occurrences] contains ONLY fully
/// resolved occurrences — never an object with empty UTC/timezone. Every day
/// that fails (DST gap/overlap, MISSING_TEMPLATE, invalid input) is surfaced
/// as a [RenderIssue] in [ProjectionResult.issues]; nothing is dropped.
ProjectionResult projectOccurrences({
  required ShiftPattern pattern,
  required String rangeStart, // ISO date
  required String rangeEnd, // ISO date
  required List<ShiftTemplate> templates, // available templates for this job
}) {
  final occurrences = <ShiftOccurrence>[];
  final issues = <RenderIssue>[];

  // Build template lookup
  final templateMap = <String, ShiftTemplate>{};
  for (final t in templates) {
    templateMap[t.id] = t;
  }

  // Strict date parsing (M1): never let DateTime.parse silently roll over.
  final anchor = _parseDateStrict(pattern.anchorDate);
  final start = _parseDateStrict(rangeStart);
  final end = _parseDateStrict(rangeEnd);
  if (anchor == null || start == null || end == null) {
    issues.add(RenderIssue(
      code: ErrorCodes.invalidDate,
      message: 'Invalid date in projection request (anchor=${pattern.anchorDate}, '
          'range=$rangeStart..$rangeEnd) — one of them is not a real calendar date.',
    ));
    return ProjectionResult(occurrences: occurrences, issues: issues);
  }
  if (pattern.cycleLengthDays <= 0) {
    issues.add(RenderIssue(
      code: ErrorCodes.invalidPayload,
      message: 'Pattern ${pattern.id} has cycleLengthDays=${pattern.cycleLengthDays}; '
          'must be > 0.',
    ));
    return ProjectionResult(occurrences: occurrences, issues: issues);
  }

  // Number of whole days from anchor midnight to rangeStart midnight.
  final daysFromAnchor = start.difference(anchor).inDays;
  var cycleIndex = daysFromAnchor % pattern.cycleLengthDays;
  if (cycleIndex < 0) {
    cycleIndex += pattern.cycleLengthDays;
  }

  var current = start;
  while (!current.isAfter(end)) {
    final shiftDateStr = _formatDate(current);
    final positionInCycle = cycleIndex % pattern.cycleLengthDays;
    final templateId = pattern.sequence[positionInCycle];

    if (templateId == null) {
      // OFF day — nothing to schedule.
      cycleIndex++;
      current = current.add(const Duration(days: 1));
      continue;
    }

    final template = templateMap[templateId];
    if (template == null) {
      // NEVER silently drop the day — surface it (P4 fix, plan3_final §3 M5).
      issues.add(RenderIssue(
        code: ErrorCodes.missingTemplate,
        shiftDate: shiftDateStr,
        message: 'Pattern ${pattern.id} references template "$templateId" on '
            '$shiftDateStr but it is missing from the provided templates list.',
      ));
      cycleIndex++;
      current = current.add(const Duration(days: 1));
      continue;
    }

    // Delegate end-date handling (+1 / endHour < startHour) entirely to
    // core/time resolveShift() (INVARIANT-002) — never duplicated here.
    final resolution = resolveShift(
      shiftDate: shiftDateStr,
      startTime: template.startTime,
      endTime: template.endTime,
      timezone: pattern.defaultTimezone,
    );

    if (resolution.isSuccess) {
      occurrences.add(ShiftOccurrence(
        id: _generateId(pattern.id, shiftDateStr, templateId),
        patternId: pattern.id,
        shiftDate: shiftDateStr,
        templateId: templateId,
        startDateTimeUtc: resolution.utcStart!.isoString,
        endDateTimeUtc: resolution.utcEnd!.isoString,
        timezone: pattern.defaultTimezone,
        source: OccurrenceSource.baseline,
      ));
    } else {
      // D1: the day exists only as an issue — no phantom occurrence object.
      issues.add(RenderIssue(
        code: resolution.error!,
        shiftDate: shiftDateStr,
        message: 'Shift on $shiftDateStr ${template.startTime}-'
            '${template.endTime} in ${pattern.defaultTimezone} cannot be '
            'scheduled: ${resolution.error}. ${resolution.note ?? ''}',
      ));
    }

    cycleIndex++;
    current = current.add(const Duration(days: 1));
  }

  return ProjectionResult(occurrences: occurrences, issues: issues);
}

// =============================================================================
// 2. applyOverride — the 6-operation command pipeline (P0-1, P0-6)
// =============================================================================

/// Apply a single override to a list of occurrences.
///
/// INVARIANT-001: The input list is NEVER mutated — a new list is returned.
///
/// P0-1 signature: returns [OverrideResult]. On success its [occurrences] is
/// the new list and [issues] is empty. On failure its [occurrences] is the
/// input list UNCHANGED and [issues] carries the reason — no silent no-op,
/// no half-applied state, no empty-UTC objects.
OverrideResult applyOverride(
  List<ShiftOccurrence> occurrences,
  Override override, {
  required Map<String, ShiftTemplate> templates,
}) {
  final OverrideResult result;
  switch (override.operation) {
    case OverrideOperation.create:
      result = _applyCreate(occurrences, override);
    case OverrideOperation.update:
      result = _applyUpdate(occurrences, override);
    case OverrideOperation.delete:
      result = _applyDelete(occurrences, override);
    case OverrideOperation.replace:
      result = _applyReplace(occurrences, override, templates);
    case OverrideOperation.split:
      result = _applySplit(occurrences, override);
    case OverrideOperation.swap:
      result = _applySwap(occurrences, override, templates);
  }

  // M3: view-level duplicate-id warning after every operation. This is a
  // warning, not an atomic failure — the list is still returned.
  if (result.issues.isEmpty) {
    final dupIssues = _duplicateIdIssues(result.occurrences);
    if (dupIssues.isNotEmpty) {
      return OverrideResult(
        occurrences: result.occurrences,
        issues: [...result.issues, ...dupIssues],
      );
    }
  }
  return result;
}

/// CREATE: add a hand-created occurrence, fully resolved (P0-1 in plan3).
OverrideResult _applyCreate(
  List<ShiftOccurrence> occurrences,
  Override override,
) {
  final payload = override.createPayload;
  if (payload == null) {
    return _failure(occurrences, ErrorCodes.invalidPayload,
        'CREATE override ${override.id} has no createPayload.', null, null);
  }

  final resolution = resolveShift(
    shiftDate: payload.date,
    startTime: payload.startTime,
    endTime: payload.endTime,
    timezone: payload.timezone,
    preferStartOffsetMinutes: payload.startOffsetMinutes,
    preferEndOffsetMinutes: payload.endOffsetMinutes,
  );
  if (!resolution.isSuccess) {
    return _failure(
      occurrences,
      resolution.error!,
      'Cannot create occurrence on ${payload.date} '
          '${payload.startTime}-${payload.endTime} in ${payload.timezone}: '
          '${resolution.error}. ${resolution.note ?? ''}',
      payload.date,
      override.id,
    );
  }

  final created = ShiftOccurrence(
    id: override.id,
    patternId: '',
    shiftDate: payload.date,
    templateId: payload.templateId,
    startDateTimeUtc: resolution.utcStart!.isoString,
    endDateTimeUtc: resolution.utcEnd!.isoString,
    timezone: payload.timezone,
    source: OccurrenceSource.created,
    sourceOverrideId: override.id,
  );

  return OverrideResult(
    occurrences: [...occurrences, created],
    issues: const [],
  );
}

/// UPDATE: modify template and/or times of an existing occurrence.
///
/// D3: >= 1 of {templateId, startTime, endTime} must be present (else
/// INVALID_PAYLOAD). Missing fields keep their current value — where the
/// current local civil time is derived from the occurrence's stored UTC
/// through its OWN timezone.
///
/// P0-2 preserve-UTC rule: if neither startTime nor endTime actually changed
/// the civil time intent, the stored UTC is preserved BIT-FOR-BIT and the
/// resolver is NOT invoked again (re-resolving an occurrence created inside
/// a DST overlap would spuriously fail with AMBIGUOUS_LOCAL_TIME).
OverrideResult _applyUpdate(
  List<ShiftOccurrence> occurrences,
  Override override,
) {
  final payload = override.updatePayload;
  if (payload == null) {
    return _failure(occurrences, ErrorCodes.invalidPayload,
        'UPDATE override ${override.id} has no updatePayload.', null, null);
  }
  if (payload.startTime == null &&
      payload.endTime == null &&
      payload.templateId == null) {
    return _failure(
        occurrences,
        ErrorCodes.invalidPayload,
        'UPDATE override ${override.id} is empty — at least one of '
            'startTime/endTime/templateId is required (D3).',
        null,
        override.occurrenceId);
  }

  final index = occurrences.indexWhere((o) => o.id == override.occurrenceId);
  if (index < 0) {
    return _failure(occurrences, ErrorCodes.occurrenceNotFound,
        'UPDATE targets occurrence "${override.occurrenceId}" which does not '
            'exist in the current list.',
        null, override.occurrenceId);
  }
  final occ = occurrences[index];

  // Derive the occurrence's current local civil times from its stored UTC
  // (never guessed, never taken from another occurrence).
  final derivedStart = _localWallTime(occ.startDateTimeUtc, occ.timezone);
  final derivedEnd = _localWallTime(occ.endDateTimeUtc, occ.timezone);

  final newTemplateId = payload.templateId ?? occ.templateId;

  // P0-2: detect whether the civil-time intent actually changed.
  final startChanged =
      payload.startTime != null && payload.startTime != derivedStart;
  final endChanged = payload.endTime != null && payload.endTime != derivedEnd;
  final timeChanged = startChanged || endChanged;

  if (!timeChanged) {
    // Template/metadata-only change (or re-sending identical times): preserve
    // UTC exactly — do NOT call the resolver again.
    final updated = occ.copyWith(
      templateId: newTemplateId,
      source: OccurrenceSource.modified,
      sourceOverrideId: override.id,
    );
    return OverrideResult(
      occurrences: [
        for (final o in occurrences)
          if (o.id == occ.id) updated else o
      ],
      issues: const [],
    );
  }

  final effectiveStart = payload.startTime ?? derivedStart;
  final effectiveEnd = payload.endTime ?? derivedEnd;

  final resolution = resolveShift(
    shiftDate: occ.shiftDate,
    startTime: effectiveStart,
    endTime: effectiveEnd,
    timezone: occ.timezone,
    preferStartOffsetMinutes:
        timeChanged ? payload.startOffsetMinutes : null,
    preferEndOffsetMinutes: timeChanged ? payload.endOffsetMinutes : null,
  );
  if (!resolution.isSuccess) {
    return _failure(
      occurrences,
      resolution.error!,
      'Cannot update "${occ.id}" to ${effectiveStart}-${effectiveEnd} on '
          '${occ.shiftDate} in ${occ.timezone}: ${resolution.error}. '
          '${resolution.note ?? ''}',
      occ.shiftDate,
      occ.id,
    );
  }

  final updated = occ.copyWith(
    templateId: newTemplateId,
    startDateTimeUtc: resolution.utcStart!.isoString,
    endDateTimeUtc: resolution.utcEnd!.isoString,
    source: OccurrenceSource.modified,
    sourceOverrideId: override.id,
  );
  return OverrideResult(
    occurrences: [
      for (final o in occurrences)
        if (o.id == occ.id) updated else o
    ],
    issues: const [],
  );
}

/// DELETE: remove an occurrence from the rendered view.
/// D6: NO soft-delete flag at Gate 0 — the Override record itself is the
/// audit trail and the undo source. Occurrence simply stops being applied.
OverrideResult _applyDelete(
  List<ShiftOccurrence> occurrences,
  Override override,
) {
  final index = occurrences.indexWhere((o) => o.id == override.occurrenceId);
  if (index < 0) {
    return _failure(occurrences, ErrorCodes.occurrenceNotFound,
        'DELETE targets occurrence "${override.occurrenceId}" which does not '
            'exist in the current list.',
        null, override.occurrenceId);
  }
  return OverrideResult(
    occurrences: [
      for (final o in occurrences)
        if (o.id != override.occurrenceId) o
    ],
    issues: const [],
  );
}

/// REPLACE: swap an occurrence onto a different template.
///
/// D3 time source: payload.overrideTime when present; otherwise the new
/// template's default start/end from the templates map (missing template ->
/// MISSING_TEMPLATE). Times that equal the occurrence's current civil times
/// preserve stored UTC (same rationale as P0-2 — re-resolving an
/// already-resolved ambiguous instant must not spuriously fail).
OverrideResult _applyReplace(
  List<ShiftOccurrence> occurrences,
  Override override,
  Map<String, ShiftTemplate> templates,
) {
  final payload = override.replacePayload;
  if (payload == null) {
    return _failure(occurrences, ErrorCodes.invalidPayload,
        'REPLACE override ${override.id} has no replacePayload.', null, null);
  }
  final index = occurrences.indexWhere((o) => o.id == override.occurrenceId);
  if (index < 0) {
    return _failure(occurrences, ErrorCodes.occurrenceNotFound,
        'REPLACE targets occurrence "${override.occurrenceId}" which does not '
            'exist in the current list.',
        null, override.occurrenceId);
  }
  final occ = occurrences[index];

  final template = templates[payload.newTemplateId];
  if (template == null) {
    return _failure(
        occurrences,
        ErrorCodes.missingTemplate,
        'REPLACE "${occ.id}" references template "${payload.newTemplateId}" '
            'which is missing from the provided templates list.',
        occ.shiftDate,
        occ.id);
  }

  final derivedStart = _localWallTime(occ.startDateTimeUtc, occ.timezone);
  final derivedEnd = _localWallTime(occ.endDateTimeUtc, occ.timezone);

  final startTime = payload.overrideTime?.startTime ?? template.startTime;
  final endTime = payload.overrideTime?.endTime ?? template.endTime;

  if (startTime == derivedStart && endTime == derivedEnd) {
    // Same civil-time intent: preserve UTC; only the template changes.
    final updated = occ.copyWith(
      templateId: payload.newTemplateId,
      source: OccurrenceSource.modified,
      sourceOverrideId: override.id,
    );
    return OverrideResult(
      occurrences: [
        for (final o in occurrences)
          if (o.id == occ.id) updated else o
      ],
      issues: const [],
    );
  }

  final resolution = resolveShift(
    shiftDate: occ.shiftDate,
    startTime: startTime,
    endTime: endTime,
    timezone: occ.timezone,
  );
  if (!resolution.isSuccess) {
    return _failure(
      occurrences,
      resolution.error!,
      'Cannot replace "${occ.id}" with template "${payload.newTemplateId}" '
          '($startTime-$endTime) on ${occ.shiftDate} in ${occ.timezone}: '
          '${resolution.error}. ${resolution.note ?? ''}',
      occ.shiftDate,
      occ.id,
    );
  }

  final updated = occ.copyWith(
    templateId: payload.newTemplateId,
    startDateTimeUtc: resolution.utcStart!.isoString,
    endDateTimeUtc: resolution.utcEnd!.isoString,
    source: OccurrenceSource.modified,
    sourceOverrideId: override.id,
  );
  return OverrideResult(
    occurrences: [
      for (final o in occurrences)
        if (o.id == occ.id) updated else o
    ],
    issues: const [],
  );
}

/// SPLIT: replace one occurrence with N parts, resolved independently.
///
/// H-1 invariants (checked on RESOLVED UTC instants):
///   - parts strictly increase in time and never overlap;
///   - every part lies inside the original occurrence's UTC envelope
///     [occ.startDateTimeUtc, occ.endDateTimeUtc] (an equal shared boundary
///     between two consecutive parts — e.g. a midnight split of an overnight
///     shift — is allowed);
///   - dateOffsetDays of each part is 0 or 1 (part starts same/next day).
/// Any violation, or any part that fails to resolve (DST etc.), fails the
/// WHOLE split atomically: input list returned unchanged + issue(s).
OverrideResult _applySplit(
  List<ShiftOccurrence> occurrences,
  Override override,
) {
  final payload = override.splitPayload;
  if (payload == null || payload.parts.isEmpty) {
    return _failure(occurrences, ErrorCodes.invalidPayload,
        'SPLIT override ${override.id} has no parts (splitPayload).', null,
        override.occurrenceId);
  }
  final index = occurrences.indexWhere((o) => o.id == override.occurrenceId);
  if (index < 0) {
    return _failure(occurrences, ErrorCodes.occurrenceNotFound,
        'SPLIT targets occurrence "${override.occurrenceId}" which does not '
            'exist in the current list.',
        null, override.occurrenceId);
  }
  final occ = occurrences[index];
  final occStartMs =
      DateTime.parse(occ.startDateTimeUtc).millisecondsSinceEpoch;
  final occEndMs = DateTime.parse(occ.endDateTimeUtc).millisecondsSinceEpoch;

  // Resolve every part first — the whole split is atomic.
  final partResolutions = <({String date, int startMs, int endMs})>[];
  final partIssues = <RenderIssue>[];
  for (var i = 0; i < payload.parts.length; i++) {
    final part = payload.parts[i];
    if (part.dateOffsetDays != 0 && part.dateOffsetDays != 1) {
      partIssues.add(RenderIssue(
        code: ErrorCodes.splitInvalidParts,
        shiftDate: occ.shiftDate,
        occurrenceId: occ.id,
        message: 'SPLIT part $i of "${occ.id}" has dateOffsetDays='
            '${part.dateOffsetDays}; only 0 (same day) or 1 (next day) are '
            'allowed.',
      ));
      continue;
    }
    final partDate = _addDays(occ.shiftDate, part.dateOffsetDays);
    final resolution = resolveShift(
      shiftDate: partDate,
      startTime: part.startTime,
      endTime: part.endTime,
      timezone: occ.timezone,
    );
    if (!resolution.isSuccess) {
      partIssues.add(RenderIssue(
        code: resolution.error!,
        shiftDate: partDate,
        occurrenceId: occ.id,
        message: 'SPLIT part $i of "${occ.id}" '
            '(${part.startTime}-${part.endTime} on $partDate) cannot be '
            'resolved: ${resolution.error}. ${resolution.note ?? ''}',
      ));
      continue;
    }
    partResolutions.add((
      date: partDate,
      startMs: resolution.utcStart!.millisecondsSinceEpoch,
      endMs: resolution.utcEnd!.millisecondsSinceEpoch,
    ));
  }

  if (partIssues.isNotEmpty || partResolutions.length != payload.parts.length) {
    // Atomic failure — nothing changes.
    return OverrideResult(
      occurrences: occurrences,
      issues: partIssues.isEmpty
          ? [
              RenderIssue(
                code: ErrorCodes.splitInvalidParts,
                shiftDate: occ.shiftDate,
                occurrenceId: occ.id,
                message: 'SPLIT of "${occ.id}" could not resolve all parts; '
                    'aborting atomically.',
              )
            ]
          : partIssues,
    );
  }

  // H-1: envelope + ordering + non-overlap on resolved UTC.
  final envelopeOk = partResolutions.every(
    (p) => p.startMs >= occStartMs && p.endMs <= occEndMs,
  );
  final orderingOk = () {
    for (var i = 0; i + 1 < partResolutions.length; i++) {
      // Chronological + non-overlapping: next start >= this end.
      if (partResolutions[i].endMs > partResolutions[i + 1].startMs) {
        return false;
      }
    }
    return true;
  }();

  if (!envelopeOk || !orderingOk) {
    return OverrideResult(
      occurrences: occurrences,
      issues: [
        RenderIssue(
          code: ErrorCodes.splitInvalidParts,
          shiftDate: occ.shiftDate,
          occurrenceId: occ.id,
          message: 'SPLIT of "${occ.id}" violates an invariant (parts must be '
              'chronological, non-overlapping, and inside the original '
              '${occ.startDateTimeUtc}..${occ.endDateTimeUtc} envelope) — '
              'aborting atomically.',
        ),
      ],
    );
  }

  // Build the parts replacing the original in place.
  final parts = <ShiftOccurrence>[
    for (var i = 0; i < payload.parts.length; i++)
      ShiftOccurrence(
        id: '${occ.id}#p$i',
        patternId: occ.patternId,
        shiftDate: partResolutions[i].date,
        templateId: payload.parts[i].templateId,
        startDateTimeUtc:
            UtcInstant.fromEpoch(partResolutions[i].startMs).isoString,
        endDateTimeUtc:
            UtcInstant.fromEpoch(partResolutions[i].endMs).isoString,
        timezone: occ.timezone,
        source: OccurrenceSource.modified,
        sourceOverrideId: override.id,
      ),
  ];

  final newList = <ShiftOccurrence>[
    ...occurrences.sublist(0, index),
    ...parts,
    ...occurrences.sublist(index + 1),
  ];
  return OverrideResult(occurrences: newList, issues: const []);
}

/// SWAP: exchange shiftDate + template (+ local time) between two
/// occurrences.
///
/// D5: only valid when both occurrences share job AND timezone — otherwise
/// SWAP_CROSS_JOB (user should DELETE + CREATE instead). Each side keeps its
/// own id and its own timezone (INVARIANT-007); UTC is re-resolved from the
/// other occurrence's local civil intent on the other's shiftDate. Both sides
/// must resolve; otherwise the swap is atomic and nothing changes.
OverrideResult _applySwap(
  List<ShiftOccurrence> occurrences,
  Override override,
  Map<String, ShiftTemplate> templates,
) {
  final swapWithId = override.swapWithOccurrenceId;
  if (swapWithId == null) {
    return _failure(occurrences, ErrorCodes.invalidPayload,
        'SWAP override ${override.id} has no swapWithOccurrenceId.', null,
        override.occurrenceId);
  }

  final indexA = occurrences.indexWhere((o) => o.id == override.occurrenceId);
  if (indexA < 0) {
    return _failure(occurrences, ErrorCodes.occurrenceNotFound,
        'SWAP targets occurrence "${override.occurrenceId}" which does not '
            'exist in the current list.',
        null, override.occurrenceId);
  }
  final indexB = occurrences.indexWhere((o) => o.id == swapWithId);
  if (indexB < 0) {
    return _failure(occurrences, ErrorCodes.occurrenceNotFound,
        'SWAP partner "${swapWithId}" does not exist in the current list.',
        null, override.occurrenceId);
  }
  final occA = occurrences[indexA];
  final occB = occurrences[indexB];

  // Gate A §A4: effectiveJobId replaces template only where the swap
  // boundary needs it. Imported occurrences (patternId == '') have no
  // template → no template-resolved job; they carry their own [jobId] which
  // is authoritative. Non-imported occurrences fall back to the template's
  // jobId then the occurrence's own [jobId] (defensive).
  String effectiveJobId(ShiftOccurrence o, Map<String, ShiftTemplate> tpl) {
    if (o.jobId != null && o.jobId!.isNotEmpty) return o.jobId!;
    final tmpl = tpl[o.templateId];
    if (tmpl != null) return tmpl.jobId;
    return '';
  }

  final jobA = effectiveJobId(occA, templates);
  final jobB = effectiveJobId(occB, templates);
  final tzA = occA.timezone;
  final tzB = occB.timezone;

  if (jobA.isEmpty || jobB.isEmpty) {
    return _failure(
        occurrences,
        ErrorCodes.incompleteSwap,
        'SWAP cannot proceed: effectiveJobId is empty for one side '
            '("${occA.id}" job="$jobA", "${occB.id}" job="$jobB"). '
            'A SWAP needs both sides to know which job they belong to — '
            'imported occurrences must carry jobId. Use DELETE + CREATE '
            'instead if the job is genuinely unknown.',
        null,
        occA.id);
  }
  if (jobA != jobB || tzA != tzB) {
    return _failure(
        occurrences,
        ErrorCodes.swapCrossJob,
        'SWAP between "${occA.id}" (job $jobA, $tzA) and '
            '"${occB.id}" (job $jobB, $tzB) is not allowed: both '
            'must share the same job and timezone (D5). Use DELETE + CREATE '
            'instead.',
        null,
        occA.id);
  }

  // Local civil intent travels with each occurrence to the other's day.
  final aStart = _localWallTime(occA.startDateTimeUtc, occA.timezone);
  final aEnd = _localWallTime(occA.endDateTimeUtc, occA.timezone);
  final bStart = _localWallTime(occB.startDateTimeUtc, occB.timezone);
  final bEnd = _localWallTime(occB.endDateTimeUtc, occB.timezone);

  // Atomic: resolve BOTH new sides before mutating anything.
  final newAResolution = resolveShift(
    shiftDate: occB.shiftDate,
    startTime: bStart,
    endTime: bEnd,
    timezone: occA.timezone,
  );
  final newBResolution = resolveShift(
    shiftDate: occA.shiftDate,
    startTime: aStart,
    endTime: aEnd,
    timezone: occB.timezone,
  );

  if (!newAResolution.isSuccess || !newBResolution.isSuccess) {
    final failing = !newAResolution.isSuccess
        ? newAResolution
        : newBResolution;
    return _failure(
      occurrences,
      failing.error!,
      'SWAP "${occA.id}" <-> "${occB.id}" cannot be re-resolved: '
          '${failing.error}. ${failing.note ?? ''}',
      null,
      occA.id,
    );
  }

  final newA = occA.copyWith(
    shiftDate: occB.shiftDate,
    templateId: occB.templateId,
    startDateTimeUtc: newAResolution.utcStart!.isoString,
    endDateTimeUtc: newAResolution.utcEnd!.isoString,
    source: OccurrenceSource.modified,
    sourceOverrideId: override.id,
  );
  final newB = occB.copyWith(
    shiftDate: occA.shiftDate,
    templateId: occA.templateId,
    startDateTimeUtc: newBResolution.utcStart!.isoString,
    endDateTimeUtc: newBResolution.utcEnd!.isoString,
    source: OccurrenceSource.modified,
    sourceOverrideId: override.id,
  );

  return OverrideResult(
    occurrences: [
      for (final o in occurrences)
        if (o.id == occA.id)
          newA
        else if (o.id == occB.id)
          newB
        else
          o
    ],
    issues: const [],
  );
}

// =============================================================================
// 3. renderEffectiveSchedule — baseline + overrides (D8)
// =============================================================================

/// Render the effective schedule: pattern baseline + overrides applied in
/// order at render time.
///
/// INVARIANT-001: overrides apply to projected occurrences, never to the
/// pattern.
///
/// P0-6 chain semantics: each override is applied on the state left by the
/// previous one. A failing override keeps that state, contributes its issue,
/// and does NOT block later overrides nor roll back earlier successes.
///
/// D8: returns [ScheduleRenderResult] — nothing is silently dropped; every
/// unresolved day and every override failure lands in [issues].
ScheduleRenderResult renderEffectiveSchedule({
  required ShiftPattern pattern,
  required List<Override> overrides,
  required String rangeStart,
  required String rangeEnd,
  required List<ShiftTemplate> templates,
}) {
  // 1. Project baseline — resolved-only (P0-3).
  final projection = projectOccurrences(
    pattern: pattern,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    templates: templates,
  );

  var occurrences = projection.occurrences;
  final issues = <RenderIssue>[...projection.issues];

  final templateMap = <String, ShiftTemplate>{
    for (final t in templates) t.id: t,
  };

  // 2. Apply each override in order on the evolving state.
  for (final override in overrides) {
    final result = applyOverride(occurrences, override, templates: templateMap);
    occurrences = result.occurrences;
    issues.addAll(result.issues);
  }

  // 3. Whole-view duplicate-id check (M3).
  issues.addAll(_duplicateIdIssues(occurrences));

  // 4. Deterministic ordering: by shiftDate, then by id.
  final sorted = [...occurrences]
    ..sort((a, b) {
      final byDate = a.shiftDate.compareTo(b.shiftDate);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    });

  return ScheduleRenderResult(occurrences: sorted, issues: issues);
}

// =============================================================================
// 4. Pattern Versioning (D1 + D9)
// =============================================================================

/// Get the active pattern version for a given date.
///
/// Patterns are versioned using VersionedEntity { effectiveFrom, effectiveUntil }.
/// Query: effectiveFrom <= date && (effectiveUntil == null || effectiveUntil >= date).
///
/// Returns null if no version matches the date.
ShiftPattern? getActivePattern({
  required List<ShiftPattern> versions,
  required String date,
}) {
  // Sort by effectiveFrom descending (newest first)
  final sorted = List<ShiftPattern>.from(versions)
    ..sort((a, b) => b.effectiveFrom.compareTo(a.effectiveFrom));

  for (final pattern in sorted) {
    if (pattern.isActiveOn(date)) {
      return pattern;
    }
  }
  return null;
}

/// Create a new pattern version, ending the previous one.
///
/// INVARIANT-001: The old pattern is NEVER mutated — a closed copy and a new
/// pattern are returned.
///
/// D9: the new version KEEPS the original pattern's anchorDate (phase
/// continuity). A roster change mid-cycle must not reset where the cycle is;
/// occurrences right after effectiveFrom continue in the old phase. To truly
/// change phase, create a NEW pattern (new id), not a new version.
///
/// Returns: [closed old pattern, new pattern]. Caller persists both.
(ShiftPattern oldPattern, ShiftPattern newPattern) createNewVersion({
  required ShiftPattern currentPattern,
  required String newEffectiveFrom, // ISO date
  required String newName,
  required int newCycleLengthDays,
  required List<String?> newSequence,
}) {
  final newFrom = _parseDateStrict(newEffectiveFrom)!;
  final dayBefore = newFrom.subtract(const Duration(days: 1));

  final closedPattern = ShiftPattern(
    id: currentPattern.id,
    jobId: currentPattern.jobId,
    name: currentPattern.name,
    type: currentPattern.type,
    cycleLengthDays: currentPattern.cycleLengthDays,
    sequence: currentPattern.sequence,
    anchorDate: currentPattern.anchorDate,
    defaultTimezone: currentPattern.defaultTimezone,
    effectiveFrom: currentPattern.effectiveFrom,
    effectiveUntil: _formatDate(dayBefore),
  );

  final newPattern = ShiftPattern(
    id: '${currentPattern.id}_v${DateTime.now().millisecondsSinceEpoch}',
    jobId: currentPattern.jobId,
    name: newName,
    type: currentPattern.type,
    cycleLengthDays: newCycleLengthDays,
    sequence: newSequence,
    // D9: anchorDate carries over from the original version.
    anchorDate: currentPattern.anchorDate,
    defaultTimezone: currentPattern.defaultTimezone,
    effectiveFrom: newEffectiveFrom,
    effectiveUntil: null, // currently active
  );

  return (closedPattern, newPattern);
}

/// Project occurrences respecting pattern versioning.
///
/// For a date range spanning multiple pattern versions, uses the active
/// version for each date. Occurrences before a version change remain
/// unchanged (INVARIANT-001).
ProjectionResult projectOccurrencesVersioned({
  required List<ShiftPattern> versions, // all versions
  required String rangeStart,
  required String rangeEnd,
  required List<ShiftTemplate> templates,
}) {
  final occurrences = <ShiftOccurrence>[];
  final issues = <RenderIssue>[];

  final start = _parseDateStrict(rangeStart);
  final end = _parseDateStrict(rangeEnd);
  if (start == null || end == null) {
    return ProjectionResult(occurrences: occurrences, issues: [
      RenderIssue(
        code: ErrorCodes.invalidDate,
        message: 'Invalid range ($rangeStart..$rangeEnd) — not real dates.',
      ),
    ]);
  }

  var current = start;
  while (!current.isAfter(end)) {
    final dateStr = _formatDate(current);
    final activePattern = getActivePattern(versions: versions, date: dateStr);
    if (activePattern != null) {
      final dayResult = projectOccurrences(
        pattern: activePattern,
        rangeStart: dateStr,
        rangeEnd: dateStr,
        templates: templates,
      );
      occurrences.addAll(dayResult.occurrences);
      issues.addAll(dayResult.issues);
    }
    current = current.add(const Duration(days: 1));
  }

  return ProjectionResult(occurrences: occurrences, issues: issues);
}

// =============================================================================
// Helpers
// =============================================================================

/// Build a failed [OverrideResult]: input list unchanged + one issue.
OverrideResult _failure(
  List<ShiftOccurrence> occurrences,
  String code,
  String message,
  String? shiftDate,
  String? occurrenceId,
) {
  return OverrideResult(
    occurrences: occurrences,
    issues: [
      RenderIssue(
        code: code,
        shiftDate: shiftDate,
        occurrenceId: occurrenceId,
        message: message,
      ),
    ],
  );
}

/// Detect duplicate ids in a view (M3). Returns one issue per duplicated id.
List<RenderIssue> _duplicateIdIssues(List<ShiftOccurrence> occurrences) {
  final seen = <String>{};
  final duplicated = <String>{};
  for (final occ in occurrences) {
    if (!seen.add(occ.id)) {
      duplicated.add(occ.id);
    }
  }
  return [
    for (final id in duplicated)
      RenderIssue(
        code: ErrorCodes.duplicateOccurrenceId,
        occurrenceId: id,
        message: 'Duplicate occurrence id "$id" in the same schedule view — '
            'override targeting by id is ambiguous.',
      ),
  ];
}

/// Wall-clock "HH:mm" of a UTC instant rendered in [timezone].
String _localWallTime(String utcIso, String timezone) {
  final location = tz.getLocation(timezone);
  final utc = DateTime.parse(utcIso).toUtc();
  final local = tz.TZDateTime.from(utc, location);
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// Strict calendar-date parse (M1): null when not parseable or when
/// DateTime would silently roll over (2026-02-31 -> 2026-03-03).
DateTime? _parseDateStrict(String date) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  final probe = DateTime.utc(year, month, day);
  if (probe.year != year || probe.month != month || probe.day != day) {
    return null;
  }
  return probe;
}

String _addDays(String date, int days) {
  final parsed = _parseDateStrict(date)!;
  final next = parsed.add(Duration(days: days));
  return _formatDate(next);
}

String _formatDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Generate a deterministic ID for a baseline occurrence.
String _generateId(String patternId, String shiftDate, String templateId) {
  return '${patternId}_${shiftDate}_$templateId';
}
