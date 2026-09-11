// =============================================================================
// Occurrence sheet (M1). Every mutation below writes ONE Override to the
// append-only log through override_actions → ScheduleService.applyOverride
// (INVARIANT-001: the pattern is never touched; plan3 P0-6: commands apply in
// order on the evolving state). The calendar re-renders through the engine
// afterwards and surfaces any engine issue in its banner — the UI never
// fabricates success.
//
//   occurrence != null → view + UPDATE times/template · REPLACE template ·
//                        DELETE
//   occurrence == null  → CREATE a shift on an OFF day (date given).
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/time/time_engine.dart' show resolveShift;
import 'package:shiftease/core/time/time_types.dart' show ErrorCodes, DstAmbiguityType;
import 'package:shiftease/domain/income_estimate.dart' show IncomeImpact;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/common/dst_resolution_dialog.dart';
import 'package:shiftease/features/common/write_guard.dart';
import 'package:shiftease/features/occurrence/override_actions.dart';

final RegExp _clock = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

class OccurrenceSheet extends StatefulWidget {
  final ScheduleService service;
  final String jobId;
  final ShiftOccurrence? occurrence; // null = create on [date]
  final String? date; // ISO date for CREATE

  const OccurrenceSheet({
    super.key,
    required this.service,
    required this.jobId,
    this.occurrence,
    this.date,
  }) : assert(occurrence != null || date != null,
            'CREATE needs a date; view/edit needs an occurrence');

  @override
  State<OccurrenceSheet> createState() => _OccurrenceSheetState();
}

class _OccurrenceSheetState extends State<OccurrenceSheet> {
  late final List<ShiftTemplate> _templates;
  String? _error;
  (String, String, String)? _previewSig; // (templateId, start, end)

  @override
  void initState() {
    super.initState();
    _templates = widget.service.templates(widget.jobId);
  }

  /// RC plan §A1 — run a write action (which returns null or a validation
  /// error string) and convert any escaping exception into a user-facing
  /// message. A repository/domain exception must NEVER escape an event
  /// handler as an unhandled crash — the form shows the reason instead and
  /// the transaction guarantees the data is untouched.
  String? _guardedWrite(String? Function() action) {
    try {
      return action();
    } catch (e) {
      return writeErrorMessage(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.occurrence;
    final isCreate = o == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCreate ? 'Add shift on ${widget.date}' : 'Shift on ${o.shiftDate}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (!isCreate) ...[
                const SizedBox(height: 4),
                Text('Template: ${o.templateId}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 12),
              if (isCreate) ...[
                _createForm(),
                // RC §B6 — live income-impact preview for CREATE too
                // (persist:false; _impact() already handles the CREATE leg).
                if (widget.service.payEnabled) _impactLine(_impact()),
              ] else ...[
                _editForm(context, o),
                const SizedBox(height: 8),
                if (_error != null)
                  Text(_error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error)),
                if (widget.service.payEnabled) _impactLine(_impact()),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete shift'),
                    onPressed: _confirmDelete,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // -- CREATE ----------------------------------------------------------------

  /// Gate C B1 (D-C5) + RC plan §D — DST gate with REAL ambiguous
  /// resolution: for a fall-back overlap the user EXPLICITLY picks one of
  /// the two interpretations (e.g. 01:30 EDT vs 01:30 EST) and the picked
  /// offset is returned so the write carries the chosen instants. For a
  /// spring-forward gap nothing can be picked — the write stays refused.
  /// Returns (errorString, pickedOffsetMinutes):
  ///   (null, null)   → the write may proceed (no DST issue, or cancelled)
  ///   (error, null)  → blocked, show [error]
  ///   (null, offset) → proceed WITH the picked interpretation. The offset
  ///     preference only ever alters an AMBIGUOUS boundary inside the engine
  ///     (an unambiguous time ignores it), so passing it for both boundaries
  ///     is safe and covers the both-sides-ambiguous overnight case.
  Future<(String?, int?)> _dstGate({
    required String shiftDate,
    required String timezone,
    required String start,
    required String end,
  }) async {
    final resolution = resolveShift(
      shiftDate: shiftDate,
      startTime: start,
      endTime: end,
      timezone: timezone,
    );
    if (resolution.isSuccess) return const (null, null);
    final err = resolution.error;
    final isDst = err == ErrorCodes.nonexistentLocalTime ||
        err == ErrorCodes.ambiguousLocalTime;
    if (!isDst) {
      // Non-DST engine failures (end-before-start etc.) keep the pre-existing
      // behaviour: the engine surfaces them as render issues after the write.
      return const (null, null);
    }
    final isAmbiguous = err == ErrorCodes.ambiguousLocalTime;
    final outcome = await showDstResolutionDialog(
      context,
      type: isAmbiguous ? DstAmbiguityType.ambiguous : DstAmbiguityType.nonexistent,
      date: shiftDate,
      time: start,
      timezone: timezone,
      options: resolution.options,
    );
    if (outcome == null || !outcome.acknowledged) {
      // Cancelled the dialog — back to the form, nothing written.
      return const (null, null);
    }
    // RC §D — AMBIGUOUS with an explicit pick: store the chosen
    // interpretation. Without a pick the write stays refused (D-C5).
    if (isAmbiguous && outcome.selectedOffsetMinutes != null) {
      return (null, outcome.selectedOffsetMinutes);
    }
    return (
      isAmbiguous
          ? 'Not saved: $start on $shiftDate occurs twice in $timezone '
              '(clocks fall back). Pick an interpretation or change the time.'
          : 'Not saved: $start on $shiftDate does not exist in $timezone '
              '(clocks spring forward). Choose a different time.',
      null,
    );
  }

  /// RC plan §B6 — income impact of the CURRENT form values vs the current
  /// effective week, WITHOUT persisting anything. Returns null when the
  /// preview cannot resolve the edit (the DST gate handles those errors).
  IncomeImpact? _impact() {
    final sig = _previewSig;
    if (sig == null) return null;
    final (templateId, start, end) = sig;
    final week = widget.service.currentWeekShifts(widget.jobId);
    final o = widget.occurrence;
    if (o == null) {
      // CREATE: add a freshly-resolved prospective occurrence.
      final tz = widget.service
          .jobs()
          .firstWhere((j) => j.id == widget.jobId)
          .defaultTimezone;
      final res = resolveShift(
          shiftDate: widget.date!,
          startTime: start,
          endTime: end,
          timezone: tz);
      if (!res.isSuccess) return null;
      final created = ShiftOccurrence(
        id: 'impact-preview',
        patternId: '',
        shiftDate: widget.date!,
        templateId: templateId,
        startDateTimeUtc: res.utcStart!.isoString,
        endDateTimeUtc: res.utcEnd!.isoString,
        timezone: tz,
        source: OccurrenceSource.created,
        jobId: widget.jobId,
      );
      return widget.service.estimateIncomeImpact(
          jobId: widget.jobId,
          current: week,
          prospective: [...week, created]);
    }
    // UPDATE / REPLACE: replace the target with the modified prospective.
    final wall = widget.service.localWallTime(o);
    final sameTimes = wall != null && wall.start == start && wall.end == end;
    ShiftOccurrence modified;
    if (sameTimes) {
      modified = o.copyWith(templateId: templateId);
    } else {
      final res = resolveShift(
          shiftDate: o.shiftDate,
          startTime: start,
          endTime: end,
          timezone: o.timezone);
      if (!res.isSuccess) return null;
      modified = o.copyWith(
        templateId: templateId,
        startDateTimeUtc: res.utcStart!.isoString,
        endDateTimeUtc: res.utcEnd!.isoString,
      );
    }
    return widget.service.estimateIncomeImpact(
      jobId: widget.jobId,
      current: week,
      prospective: [
        for (final x in week)
          if (x.id != o.id) x,
        modified,
      ],
    );
  }

  Widget _impactLine(IncomeImpact? impact) {
    if (impact == null) return const SizedBox.shrink();
    if (!impact.available) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
            'Income impact: Unable to calculate accurately — '
            '${impact.unavailableReason}',
            style: const TextStyle(fontSize: 12, color: Colors.orange)),
      );
    }
    final sign = impact.delta >= 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
          'Income impact (this week): \$${impact.before.toStringAsFixed(2)} '
          '→ \$${impact.after.toStringAsFixed(2)} '
          '(${sign}\$${impact.delta.toStringAsFixed(2)}) — estimate',
          style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
    );
  }

  Widget _createForm() {
    final tzName = widget.service.jobs()
        .firstWhere((j) => j.id == widget.jobId)
        .defaultTimezone;
    return _ShiftForm(
      templates: _templates,
      error: _error,
      onError: (e) => setState(() => _error = e),
      onPreviewChanged: (sig) => setState(() => _previewSig = sig),
      actionLabel: 'Add shift',
      extraActions: const [],
      onCommit: (templateId, start, end) async {
        final (gateError, dstOffset) = await _dstGate(
          shiftDate: widget.date!,
          timezone: tzName,
          start: start,
          end: end,
        );
        if (gateError != null) {
          setState(() => _error = gateError);
          return;
        }
        final error = _guardedWrite(() => createShiftOnDate(
              widget.service,
              jobId: widget.jobId,
              date: widget.date!,
              templateId: templateId,
              start: start,
              end: end,
              dstOffsetMinutes: dstOffset,
            ));
        if (error != null) {
          setState(() => _error = error);
          return;
        }
        Navigator.of(context).pop(true);
      },
    );
  }

  // -- UPDATE / REPLACE ------------------------------------------------------

  Widget _editForm(BuildContext context, ShiftOccurrence o) {
    final wall = widget.service.localWallTime(o);
    return _ShiftForm(
      templates: _templates,
      initialTemplateId: o.templateId,
      initialStart: wall?.start ?? '00:00',
      initialEnd: wall?.end ?? '00:00',
      error: _error,
      onError: (e) => setState(() => _error = e),
      onPreviewChanged: (sig) => setState(() => _previewSig = sig),
      actionLabel: 'Update shift',
      extraActions: [
        // REPLACE template with the engine default times of the new template
        // (a deliberate "change type" action).
        TextButton(
          onPressed: () => _replace(o),
          child: const Text('Change template only'),
        ),
      ],
      onCommit: (templateId, start, end) async {
        final (gateError, dstOffset) = await _dstGate(
          shiftDate: o.shiftDate,
          timezone: o.timezone,
          start: start,
          end: end,
        );
        if (gateError != null) {
          setState(() => _error = gateError);
          return;
        }
        final error = _guardedWrite(() => updateShift(
              widget.service,
              jobId: widget.jobId,
              occurrence: o,
              templateId: templateId,
              start: start,
              end: end,
              dstOffsetMinutes: dstOffset,
            ));
        if (error != null) {
          setState(() => _error = error);
          return;
        }
        Navigator.of(context).pop(true);
      },
    );
  }

  void _replace(ShiftOccurrence o) {
    if (_templates.length < 2) {
      setState(() => _error =
          'Need at least 2 templates to replace with a different one.');
      return;
    }
    final target = _templates.firstWhere((t) => t.id != o.templateId,
        orElse: () => _templates.first);
    final error = _guardedWrite(() => replaceShiftTemplate(
          widget.service,
          jobId: widget.jobId,
          occurrence: o,
          newTemplateId: target.id,
        ));
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _confirmDelete() {
    final o = widget.occurrence!;
    // RC §B6 — DELETE impact preview (persist:false; never touches the DB).
    IncomeImpact? impact;
    if (widget.service.payEnabled) {
      final week = widget.service.currentWeekShifts(widget.jobId);
      impact = widget.service.estimateIncomeImpact(
        jobId: widget.jobId,
        current: week,
        prospective: [
          for (final x in week)
            if (x.id != o.id) x,
        ],
      );
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this shift?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'This writes a DELETE override to the log. The pattern itself is '
                'never changed, and the change is reversible by removing the '
                'override from the audit log.'),
            if (impact != null && impact.available) ...[
              const SizedBox(height: 8),
              Text(
                  'Income impact (this week): '
                  '\$${impact.before.toStringAsFixed(2)} '
                  '→ \$${impact.after.toStringAsFixed(2)} — estimate',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.blueGrey)),
            ] else if (impact != null) ...[
              const SizedBox(height: 8),
              Text('Income impact: Unable to calculate accurately — '
                  '${impact.unavailableReason}',
                  style: const TextStyle(fontSize: 12, color: Colors.orange)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final error = _guardedWrite(() => deleteShift(widget.service,
                  jobId: widget.jobId, occurrence: o));
              if (error != null) {
                setState(() => _error = error);
                return;
              }
              Navigator.of(context).pop(true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Shared time/template form used by CREATE and UPDATE.
class _ShiftForm extends StatefulWidget {
  final List<ShiftTemplate> templates;
  final String? initialTemplateId;
  final String initialStart;
  final String initialEnd;
  final String? error;
  final ValueChanged<String> onError;

  /// Fires whenever the form's (templateId, start, end) signature changes so
  /// the parent can refresh the RC §B6 income-impact preview.
  final ValueChanged<(String, String, String)>? onPreviewChanged;
  final String actionLabel;
  final List<Widget> extraActions;
  final Future<void> Function(String templateId, String start, String end)
      onCommit;

  const _ShiftForm({
    required this.templates,
    required this.error,
    required this.onError,
    required this.actionLabel,
    required this.extraActions,
    required this.onCommit,
    this.onPreviewChanged,
    this.initialTemplateId,
    this.initialStart = '07:00',
    this.initialEnd = '19:00',
  });

  @override
  State<_ShiftForm> createState() => _ShiftFormState();
}

class _ShiftFormState extends State<_ShiftForm> {
  late String? _templateId = widget.templates.isNotEmpty
      ? (widget.initialTemplateId ?? widget.templates.first.id)
      : null;
  late final TextEditingController _start =
      TextEditingController(text: widget.initialStart);
  late final TextEditingController _end =
      TextEditingController(text: widget.initialEnd);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onPreviewChanged
          ?.call((_templateId ?? '', _start.text.trim(), _end.text.trim()));
    });
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('shift-template'),
          initialValue: _templateId,
          decoration: const InputDecoration(labelText: 'Template'),
          items: [
            for (final t in widget.templates)
              DropdownMenuItem(value: t.id, child: Text(t.name)),
            // Imported rows may carry the '' sentinel (no matched template,
            // plan7 D-M2-2) — show it so the initial value stays valid and the
            // user is nudged to assign a template on first edit.
            if (_templateId != null &&
                !widget.templates.any((t) => t.id == _templateId))
              const DropdownMenuItem<String>(
                  value: '', child: Text('(no template — choose one)')),
          ],
          onChanged: (v) {
            setState(() => _templateId = v);
            widget.onPreviewChanged?.call(
                (v ?? '', _start.text.trim(), _end.text.trim()));
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('shift-start'),
                controller: _start,
                decoration: const InputDecoration(labelText: 'Start (HH:mm)'),
                onChanged: (_) => widget.onPreviewChanged?.call(
                    (_templateId ?? '', _start.text.trim(), _end.text.trim())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('shift-end'),
                controller: _end,
                decoration: const InputDecoration(labelText: 'End (HH:mm)'),
                onChanged: (_) => widget.onPreviewChanged?.call(
                    (_templateId ?? '', _start.text.trim(), _end.text.trim())),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.error != null)
          Text(widget.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ...widget.extraActions,
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ),
            Expanded(
              child: FilledButton(
                onPressed: _submit,
                child: Text(widget.actionLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_templateId == null) {
      widget.onError('Create a template first.');
      return;
    }
    final start = _start.text.trim();
    final end = _end.text.trim();
    if (!_clock.hasMatch(start) || !_clock.hasMatch(end)) {
      widget.onError('Times must be HH:mm (e.g. 22:00).');
      return;
    }
    if (start == end) {
      widget.onError('Start and end must differ.');
      return;
    }
    await widget.onCommit(_templateId!, start, end);
  }
}
