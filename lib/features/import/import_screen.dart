// =============================================================================
// Import screen (M2, plan7). Smart Paste → parse → MANDATORY review → commit.
// RC plan §C1/C2 adds a CSV mode and a re-import diff preview:
//
//   Paste text : paste → Parse & review → candidates
//   CSV (C1)   : paste CSV → Preview columns (header + auto-detect) → map
//                columns (date/start/end/shiftType) → Validate & review →
//                validation card + candidates
//   Diff (C2)  : once rows are approved, a card previews what COMMIT will
//                change vs the job's current committed roster — Added /
//                Removed / Modified (old → new) / Unchanged + hours delta +
//                income impact (estimate, or the reason it is unavailable).
//
// Flow mirrors the engine state machine: IDLE (paste) → EXTRACTED (parse) →
// REVIEWING (first review action) → COMMITTED (commit). Rules enforced here:
//   - INVARIANT-004: nothing is ever committed without explicit user review —
//     every committed candidate is APPROVED or MODIFIED, never pending.
//   - "Accept All High" touches only HIGH candidates (engine bulkAcceptHigh);
//     MEDIUM/LOW wait for the human.
//   - Every commit goes through ScheduleService.commitRoster → engine
//     commitImport (atomic, UTC via core/time) → rows fed into the job's
//     calendar (plan7 D-M2-1 A). Any error state is shown with its reason —
//     never a silent no-op.
//   - The session is persisted after parse AND after every review action
//     (ImportRepository) so "why is Sep 03 a Night shift?" stays answerable.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/core/import/import_diff.dart'
    show RosterDiff, RosterRow, computeRosterDiff;
import 'package:shiftease/core/import/import_engine.dart' show applyReview;
import 'package:shiftease/core/import/import_parser.dart'
    show autoDetectCsvMapping, csvHeaderRow;
import 'package:shiftease/core/import/import_types.dart';
import 'package:shiftease/core/import/import_validation.dart';
import 'package:shiftease/domain/income_estimate.dart' show IncomeImpact;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/calendar/week_calendar_screen.dart';
import 'package:shiftease/features/ads/ad_banner_widget.dart' show interstitialAds;
import 'package:shiftease/features/common/write_guard.dart';

/// Which input surface the current (pre-parse) import uses. The review/commit
/// phase is identical for both — only the parse entry differs.
enum _ImportMode { paste, csv }

class ImportScreen extends StatefulWidget {
  final ScheduleService service;
  final String jobId;
  const ImportScreen({super.key, required this.service, required this.jobId});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _raw = TextEditingController();
  final _csv = TextEditingController();
  String _referenceDate = _todayIso();
  _ImportMode _mode = _ImportMode.paste;

  // RC §C1 — CSV mapping state (header row + per-field selected column).
  List<String> _csvHeader = const [];
  Map<String, String?> _csvMapping = const {};
  List<CsvIssue> _csvIssues = const [];
  bool _csvPreviewed = false;

  ImportSession? _session;
  String? _error;

  @override
  void dispose() {
    _raw.dispose();
    _csv.dispose();
    super.dispose();
  }

  static String _todayIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  String get _jobTimezone => widget.service
      .jobs()
      .firstWhere((j) => j.id == widget.jobId)
      .defaultTimezone;

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final jobName =
        widget.service.jobs().firstWhere((j) => j.id == widget.jobId).name;

    return Scaffold(
      appBar: AppBar(title: Text('Import roster · $jobName')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (s == null || s.state == ImportState.error) ...[
            _modeSwitch(),
            const SizedBox(height: 8),
            if (_mode == _ImportMode.paste) ...[
              TextField(
                controller: _raw,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Paste your roster here',
                  hintText: 'Sep 03 Day 07:00-19:00\nSep 04 Night 19:00-07:00 +1\nSep 05 OFF',
                ),
              ),
              const SizedBox(height: 8),
              _referenceDateRow(action: _parse, actionLabel: 'Parse & review'),
            ] else ...[
              TextField(
                controller: _csv,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Paste CSV content (including the header row)',
                  hintText: 'date,shift,start,end\n2026-09-01,Day,07:00,19:00\n2026-09-02,OFF,,',
                ),
              ),
              const SizedBox(height: 8),
              _referenceDateRow(
                  action: _previewCsv, actionLabel: 'Preview columns'),
              if (_csvPreviewed) ...[
                const SizedBox(height: 8),
                _csvMappingSection(),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.rule),
                  label: const Text('Validate & review'),
                  onPressed: _parseCsvAndReview,
                ),
              ],
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (s != null && s.state == ImportState.error)
              _errorCard(s.error),
          ] else ...[
            _sessionStatus(s),
            if (s.sourceType == ImportSourceType.csv) _csvIssuesCard(),
            _diffPreview(s),
            if (s.state == ImportState.committed)
              _committedCard(s)
            else ...[
              _bulkRow(s),
              const Divider(),
              for (final c in s.candidates) _candidateCard(c),
              const SizedBox(height: 12),
              if (_pendingCount(s) > 0) _pendingWarningSite(s),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.check_circle),
                label: Text(_commitLabel(s)),
                onPressed: _canCommit(s) ? _commit : null,
              ),
            ],
          ],
        ],
      ),
    );
  }

  // -- input mode + CSV mapping (RC §C1) -------------------------------------

  Widget _modeSwitch() {
    return SegmentedButton<_ImportMode>(
      segments: const [
        ButtonSegment(
          value: _ImportMode.paste,
          icon: Icon(Icons.content_paste),
          label: Text('Paste text'),
        ),
        ButtonSegment(
          value: _ImportMode.csv,
          icon: Icon(Icons.table_chart),
          label: Text('CSV'),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (sel) => setState(() {
        _mode = sel.first;
        _error = null;
      }),
    );
  }

  Widget _referenceDateRow({
    required VoidCallback action,
    required String actionLabel,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text('Reference date: $_referenceDate'),
            onPressed: _pickReferenceDate,
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.preview),
          label: Text(actionLabel),
          onPressed: action,
        ),
      ],
    );
  }

  /// Parse the CSV header, auto-detect the mapping from known synonyms and
  /// let the user adjust every column via dropdowns (RC §C1 flow step 2-3).
  void _previewCsv() {
    if (_csv.text.trim().isEmpty) {
      setState(() => _error = 'Paste CSV content first.');
      return;
    }
    final header = csvHeaderRow(_csv.text);
    if (header.isEmpty) {
      setState(() => _error = 'CSV has no header row.');
      return;
    }
    final detected = autoDetectCsvMapping(header);
    setState(() {
      _csvHeader = header;
      _csvMapping = {
        'date': detected['date'],
        'startTime': detected['startTime'],
        'endTime': detected['endTime'],
        'shiftType': detected['shiftType'],
      };
      _csvPreviewed = true;
      _csvIssues = const [];
      _error = null;
    });
  }

  Widget _csvMappingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Map columns',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            _mappingDropdown('date', 'Date column'),
            _mappingDropdown('startTime', 'Start time column'),
            _mappingDropdown('endTime', 'End time column'),
            _mappingDropdown('shiftType', 'Shift type column (optional)'),
          ],
        ),
      ),
    );
  }

  Widget _mappingDropdown(String field, String label) {
    return DropdownButtonFormField<String?>(
      key: ValueKey('csv-map-$field'),
      initialValue: _csvMapping[field],
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String?>(
            value: null, child: Text('(not mapped)')),
        for (final h in _csvHeader)
          DropdownMenuItem<String?>(value: h, child: Text(h)),
      ],
      onChanged: (v) => setState(() => _csvMapping[field] = v),
    );
  }

  /// Parse the CSV with the user's mapping, run the C1 validation card and
  /// enter review (the SAME review/commit phase as paste — INVARIANT-004).
  void _parseCsvAndReview() {
    final mapping = <String, String>{
      for (final e in _csvMapping.entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    setState(() => _error = null);
    final error = runWrite(() {
      final s = widget.service.parseCsv(
        jobId: widget.jobId,
        rawCsv: _csv.text,
        referenceDate: _referenceDate,
        columnMapping: mapping,
      );
      // RC §C1 — validate BEFORE review: unmapped required columns, missing
      // times, duplicate rows and DST gaps each surface with a severity.
      _csvIssues = validateCsvMapping(
        s.rawExtraction,
        mapping: mapping,
        timezone: _jobTimezone,
      );
      widget.service.persistImportSession(s, jobId: widget.jobId);
      _session = s;
    });
    if (error != null) {
      // RC plan §A1 — persist failure must show, never crash.
      setState(() => _error = error);
      return;
    }
    setState(() {});
  }

  Widget _csvIssuesCard() {
    if (_csvIssues.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.amber.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CSV validation',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final issue in _csvIssues)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (issue.severity) {
                        ValidationSeverity.error => Icons.error_outline,
                        ValidationSeverity.warning => Icons.warning_amber_outlined,
                        ValidationSeverity.info => Icons.check_circle_outline,
                      },
                      size: 16,
                      color: switch (issue.severity) {
                        ValidationSeverity.error => Colors.red,
                        ValidationSeverity.warning => Colors.orange,
                        ValidationSeverity.info => Colors.green,
                      },
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(issue.message,
                            style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // -- re-import diff preview (RC §C2) ---------------------------------------

  /// What COMMIT will change vs the job's current committed roster, computed
  /// over the approved/modified candidates' date span. Only actionable rows
  /// count — pending rows are skipped by commit (Gate A §A5) so they must not
  /// appear as changes. Returns null when there is nothing to compare yet.
  (RosterDiff, IncomeImpact?)? _diffFor(ImportSession s) {
    final actionable = s.candidates
        .where((c) =>
            c.reviewStatus == ReviewStatus.approved ||
            c.reviewStatus == ReviewStatus.modified)
        .toList();
    final dates = actionable
        .map((c) => c.data.date)
        .whereType<String>()
        .toList()
      ..sort();
    if (actionable.isEmpty || dates.isEmpty) return null;
    final from = dates.first;
    final to = dates.last;

    final committed = widget.service.committedRosterRows(
        jobId: widget.jobId, from: from, to: to);
    final incoming = <RosterRow>[
      for (final c in actionable)
        if (c.data.date != null)
          (
            date: c.data.date!,
            start: c.data.kind == ShiftKind.off ? null : c.data.startTime,
            end: c.data.kind == ShiftKind.off ? null : c.data.endTime,
          ),
    ];
    final diff = computeRosterDiff(committed: committed, incoming: incoming);
    final impact = widget.service.payEnabled
        ? widget.service.estimateRosterDiffImpact(
            jobId: widget.jobId,
            from: from,
            to: to,
            prospective: incoming,
          )
        : null;
    return (diff, impact);
  }

  Widget _diffPreview(ImportSession s) {
    if (s.state == ImportState.committed || s.state == ImportState.error) {
      return const SizedBox.shrink();
    }
    final pair = _diffFor(s);
    if (pair == null) return const SizedBox.shrink();
    final (diff, impact) = pair;

    String hoursLabel() {
      final h = diff.hoursDelta;
      if (h == 0) return 'Hours: no change';
      final sign = h > 0 ? '+' : '';
      return 'Hours: $sign${h.toStringAsFixed(h.truncateToDouble() == h ? 0 : 1)}h';
    }

    return Card(
      color: Colors.indigo.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What commit will change (vs current roster)',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '+${diff.added} added · −${diff.removed} removed · '
              '~${diff.modified} changed · =${diff.unchanged} unchanged',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(hoursLabel(),
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
            for (final item in diff.items)
              if (item.kind != 'unchanged')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    item.kind == 'added'
                        ? '+ ${item.date}: ${item.newLabel ?? '?'}'
                        : item.kind == 'removed'
                            ? '− ${item.date}: ${item.oldLabel ?? '?'}'
                            : '~ ${item.date}: ${item.oldLabel ?? '?'} → '
                                '${item.newLabel ?? '?'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            if (impact != null) ...[
              const SizedBox(height: 4),
              if (impact.available)
                Text(
                  'Income impact: \$${impact.before.toStringAsFixed(2)} → '
                  '\$${impact.after.toStringAsFixed(2)} '
                  '(${impact.delta >= 0 ? '+' : ''}'
                  '\$${impact.delta.toStringAsFixed(2)}) — estimate',
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                )
              else
                Text(
                  'Income impact: Unable to calculate accurately — '
                  '${impact.unavailableReason}',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
            ],
            const SizedBox(height: 4),
            const Text(
                'This is a preview only — the roster still goes through '
                'review and the explicit commit step.',
                style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
          ],
        ),
      ),
    );
  }

  // -- state line ------------------------------------------------------------

  Widget _sessionStatus(ImportSession s) {
    final counts = <ReviewStatus, int>{};
    for (final c in s.candidates) {
      counts[c.reviewStatus] = (counts[c.reviewStatus] ?? 0) + 1;
    }
    final approved = counts[ReviewStatus.approved] ?? 0;
    final modified = counts[ReviewStatus.modified] ?? 0;
    final rejected = counts[ReviewStatus.rejected] ?? 0;
    final pending = counts[ReviewStatus.pending] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('State: ${s.state.name.toUpperCase()} · ${s.candidates.length} '
            'candidate(s) — approved $approved · modified $modified · '
            'rejected $rejected · pending $pending',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        const Text('Import never commits automatically — review each row.',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _pendingWarningSite(ImportSession s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: Colors.orange.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
              '${_pendingCount(s)} pending shifts will NOT enter the '
              'schedule if you commit now. Keep reviewing, or commit '
              'only the approved shifts?',
              style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }

  Widget _bulkRow(ImportSession s) {
    final hasHighPending = s.candidates.any((c) =>
        c.reviewStatus == ReviewStatus.pending &&
        c.confidence == Confidence.high);
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.done_all),
          label: const Text('Accept All High'),
          onPressed: hasHighPending
              ? () => _review(null, ReviewAction.bulkAcceptAllHigh, null)
              : null,
        ),
        TextButton(
          onPressed: () => _restart(),
          child: const Text('Restart (paste again)'),
        ),
      ],
    );
  }

  Widget _candidateCard(CandidateShift c) {
    final templates = widget.service.templates(widget.jobId);
    final d = c.data;
    final isOff = d.kind == ShiftKind.off;
    final templateName = d.templateId == null
        ? 'no template'
        : (templates.any((t) => t.id == d.templateId)
            ? templates.firstWhere((t) => t.id == d.templateId).name
            : d.templateId!);
    final color = switch (c.reviewStatus) {
      ReviewStatus.approved => Colors.green,
      ReviewStatus.modified => Colors.blue,
      ReviewStatus.rejected => Colors.red,
      ReviewStatus.pending => Colors.grey,
    };
    return Card(
      color: color.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    c.reviewStatus.name.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
                const SizedBox(width: 6),
                Text(_confidenceLabel(c.confidence),
                    style: const TextStyle(fontSize: 11)),
                const Spacer(),
                Text('${c.id}', style: const TextStyle(fontSize: 10)),
              ],
            ),
            Text(isOff
                ? '${d.date ?? '(no date)'}  ·  OFF'
                : '${d.date ?? '(no date)'}  ·  ${d.startTime ?? '??'}–'
                    '${d.endTime ?? '??'}  ·  ${templateName}'),
            if (c.note != null)
              Text('↳ ${c.note}', style: const TextStyle(fontSize: 11)),
            if (c.reviewStatus == ReviewStatus.pending)
              Row(
                children: [
                  IconButton(
                    tooltip: 'Approve',
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _review(c.id, ReviewAction.approve, null),
                  ),
                  IconButton(
                    tooltip: 'Reject',
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _review(c.id, ReviewAction.reject, null),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editCandidate(c),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _committedCard(ImportSession s) {
    final shifts = s.committedOccurrenceIds.length;
    final off = s.committedOffDates.length;
    // Anchor the calendar on the week of the FIRST committed date so the
    // roster is visible even when it differs from the current real week.
    final dates = s.candidates
        .where((c) =>
            (c.reviewStatus == ReviewStatus.approved ||
                c.reviewStatus == ReviewStatus.modified) &&
            c.data.date != null)
        .map((c) => c.data.date!)
        .toList()
      ..sort();
    final anchor = dates.isEmpty ? null : DateTime.tryParse(dates.first);
    return Card(
      color: Colors.green.withValues(alpha: 0.1),
      child: ListTile(
        leading: const Icon(Icons.verified, color: Colors.green),
        title: Text('Committed $shifts shift(s) + $off OFF day(s).'),
        subtitle: const Text(
            'The approved roster is now this job’s schedule for those dates '
            '(pattern days they cover are replaced).'),
        trailing: FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WeekCalendarScreen(
                service: widget.service,
                jobId: widget.jobId,
                initialDate: anchor),
          )),
          child: const Text('View calendar'),
        ),
      ),
    );
  }

  Widget _errorCard(ImportError? error) {
    final e = error;
    if (e == null) return const SizedBox.shrink();
    return Card(
      color: Colors.red.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text('${e.code}: ${e.message}',
            style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  // -- actions ---------------------------------------------------------------

  Future<void> _pickReferenceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_referenceDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _referenceDate = '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _parse() {
    if (_raw.text.trim().isEmpty) {
      setState(() => _error = 'Paste a roster first.');
      return;
    }
    setState(() => _error = null);
    final error = runWrite(() {
      final s = widget.service.parsePaste(
        jobId: widget.jobId,
        rawText: _raw.text,
        referenceDate: _referenceDate,
      );
      widget.service.persistImportSession(s, jobId: widget.jobId);
      _session = s;
    });
    if (error != null) {
      // RC plan §A1 — persist failure must show, never crash. The session
      // stays null so the form remains editable for a retry.
      setState(() => _error = error);
      return;
    }
    setState(() {});
  }

  void _review(String? candidateId, ReviewAction action, CandidateData? edits) {
    final s = _session;
    if (s == null) return;
    final updated = s.state == ImportState.error
        ? s // never review an errored session — user restarts
        : applyReview(s, candidateId: candidateId, action: action, edits: edits);
    final error = runWrite(
        () => widget.service.persistImportSession(updated, jobId: widget.jobId));
    if (error != null) {
      // RC plan §A1 — a review-persist failure shows the reason instead of
      // crashing; the in-memory session is kept so the user can retry.
      setState(() => _error = error);
      return;
    }
    setState(() => _session = updated);
  }

  void _editCandidate(CandidateShift c) {
    final templates = widget.service.templates(widget.jobId);
    var date = c.data.date ?? _referenceDate;
    var start = c.data.startTime ?? '07:00';
    var end = c.data.endTime ?? '19:00';
    String? templateId = c.data.templateId;
    var isOff = c.data.kind == ShiftKind.off;

    final dateCtrl = TextEditingController(text: date);
    final startCtrl = TextEditingController(text: start);
    final endCtrl = TextEditingController(text: end);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Edit ${c.id}'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('OFF day (no shift)'),
                    value: isOff,
                    onChanged: (v) => setDialog(() => isOff = v),
                  ),
                  TextField(
                    key: const ValueKey('edit-date'),
                    controller: dateCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
                  ),
                  if (!isOff) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('edit-start'),
                            controller: startCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Start HH:mm'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('edit-end'),
                            controller: endCtrl,
                            decoration: const InputDecoration(
                                labelText: 'End HH:mm (+1 overnight)'),
                          ),
                        ),
                      ],
                    ),
                    DropdownButtonFormField<String?>(
                      key: const ValueKey('edit-template'),
                      initialValue: templateId,
                      decoration:
                          const InputDecoration(labelText: 'Template'),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('(no template)')),
                        for (final t in templates)
                          DropdownMenuItem<String?>(
                              value: t.id, child: Text(t.name)),
                      ],
                      onChanged: (v) => setDialog(() => templateId = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final newDate = dateCtrl.text.trim();
                final newStart = startCtrl.text.trim();
                final newEnd = endCtrl.text.trim();
                final edits = CandidateData(
                  date: newDate.isEmpty ? null : newDate,
                  templateId: templateId,
                  startTime: isOff ? null : (newStart.isEmpty ? null : newStart),
                  endTime: isOff ? null : (newEnd.isEmpty ? null : newEnd),
                  shiftType: isOff
                      ? 'OFF'
                      : (templateId == null
                          ? '?'
                          : c.data.shiftType ?? 'Day'),
                  kind: isOff ? ShiftKind.off : ShiftKind.shift,
                );
                Navigator.of(ctx).pop();
                _review(c.id, ReviewAction.modify, edits);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Partial-commit là hành vi CÓ CHỦ ĐÍCH (Gate A §A5): commit chỉ áp dụng
  /// cho ca approved/modified; ca pending bị bỏ qua. Vì vậy khi còn pending,
  /// commit phải qua dialog xác nhận nêu rõ số ca sẽ KHÔNG vào lịch — không
  /// bao giờ commit ngầm bỏ qua.
  Future<void> _commit() async {
    final s = _session!;
    final pending = _pendingCount(s);
    if (pending > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Commit now?'),
          content: Text('$pending shifts are still pending review and will '
              'NOT enter the schedule if you commit now. Keep reviewing, or '
              'commit only the approved shifts?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Keep reviewing')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Commit approved shifts')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _doCommit();
  }

  void _doCommit() {
    final s = _session!;
    CommitResult result;
    try {
      result = widget.service.commitRoster(session: s, jobId: widget.jobId);
    } catch (e) {
      // RC plan §A1 — a DB/transaction failure must surface, never crash.
      // Nothing was written (the service rolls back before rethrowing).
      setState(() => _error = writeErrorMessage(e));
      return;
    }
    setState(() {
      _session = result.session;
      _error = result.error?.message;
    });
    // Interstitial placement (2026-09-11): ONLY after a successful roster
    // commit — a natural completion point, never mid-flow. Frequency-capped
    // inside the service (1 per 3 commits, ≥60s apart); a no-op when ads
    // are disabled or nothing is preloaded. Fire-and-forget: the result UI
    // renders regardless of ad state (INVARIANT-008).
    if (result.error == null) {
      interstitialAds.maybeShowAfterCommit();
    }
  }

  void _restart() {
    setState(() {
      _session = null;
      _error = null;
      _csvIssues = const [];
      _csvPreviewed = false;
    });
  }

  bool _canCommit(ImportSession s) {
    // RC review L1 — the engine rejects EXTRACTED→COMMIT (plan §A4), so a
    // commit attempt before the first review action is a guaranteed error
    // dialog. The button is enabled only in REVIEWING: the state the engine
    // actually accepts. Any review action (approve/modify/reject) moves the
    // session EXTRACTED→REVIEWING, so nothing that was committable before is
    // lost.
    if (s.state != ImportState.reviewing) {
      return false;
    }
    return s.candidates.any((c) =>
        c.reviewStatus == ReviewStatus.approved ||
        c.reviewStatus == ReviewStatus.modified);
  }

  /// Returns the number of PENDING candidates that will be SKIPPED if the
  /// user commits right now (partial-commit semantic — Gate A §A5).
  int _pendingCount(ImportSession s) => s.candidates
      .where((c) => c.reviewStatus == ReviewStatus.pending)
      .length;

  String _commitLabel(ImportSession s) {
    final approved = s.candidates
        .where((c) =>
            c.reviewStatus == ReviewStatus.approved ||
            c.reviewStatus == ReviewStatus.modified)
        .length;
    final pending = _pendingCount(s);
    if (approved == 0) {
      // Nothing to commit yet — say so plainly (the button is disabled).
      return 'Commit (approve at least 1 row first)';
    }
    if (pending > 0) {
      // Partial-commit có chủ đích (Gate A §A5): commit chỉ N ca đã duyệt;
      // số pending còn lại hiện ngay trên nút + dialog xác nhận khi bấm.
      return 'Commit $approved approved row(s) — '
          '$pending pending shifts will NOT enter the schedule';
    }
    return 'Commit $approved approved row(s)';
  }

  String _confidenceLabel(Confidence c) => switch (c) {
        Confidence.high => 'HIGH',
        Confidence.medium => 'MEDIUM',
        Confidence.low => 'LOW',
      };
}
