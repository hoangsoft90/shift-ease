// =============================================================================
// Pattern Builder (M1). Lets the user define a FIXED_CYCLE pattern:
//   - pick a cycle preset (4-on/4-off, 2-2-3, DuPont) which fixes the cycle
//     length + which slots are work vs OFF;
//   - assign a shift template to every work slot (OFF stays null — the engine
//     treats null sequence entries as OFF days, no occurrence is projected);
//   - choose the effectiveFrom date (versioning seam — a roster change later
//     goes through service.changeRosterFrom, anchorDate invariant D9);
//   - PREVIEW the projected occurrences in the engine BEFORE saving (preview
//     never writes anything — savePattern is the only write path).
// Errors (missing template, unresolvable day) surface in the preview exactly
// as they will after save — nothing is silently dropped.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/core/pattern/pattern_engine.dart'
    show projectOccurrences;
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/domain/income_estimate.dart' show IncomeImpact;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/common/write_guard.dart';

class _Preset {
  final String name;
  final int length;
  final List<bool> workSlots; // true = shift, false = OFF
  const _Preset(this.name, this.length, this.workSlots);
}

final List<_Preset> _presets = [
  const _Preset('4-on/4-off', 8,
      [true, true, true, true, false, false, false, false]),
  const _Preset('2-2-3', 7,
      [true, true, true, true, false, false, false]),
  // Canonical EMS DuPont: 4 teams rotate D D N N then 4 OFF (8-day core,
  // 3.5 cycles over 28 days — a real 28-day rota).
  _Preset('DuPont 28-day', 28,
      [for (var i = 0; i < 28; i++) (i % 8) < 4]),
];

class PatternBuilderScreen extends StatefulWidget {
  final ScheduleService service;
  final String jobId;

  /// When set, this screen edits a NEW VERSION of [existing] (roster change
  /// from [newEffectiveFrom] — engine D1/D9 flow through
  /// ScheduleService.changeRosterFrom). When null it creates a brand-new
  /// pattern.
  final ShiftPattern? existing;
  final String? newEffectiveFrom;

  const PatternBuilderScreen({
    super.key,
    required this.service,
    required this.jobId,
    this.existing,
    this.newEffectiveFrom,
  });

  @override
  State<PatternBuilderScreen> createState() => _PatternBuilderScreenState();
}

class _PatternBuilderScreenState extends State<PatternBuilderScreen> {
  late String _name;
  late int _cycleLength;
  late List<String?> _slots; // templateId or null = OFF
  late String _effectiveFrom;

  bool get _isNewVersion => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      // Pre-fill from the current version; the anchor date stays with the
      // engine's createNewVersion (D9 — this screen never touches it).
      _name = ex.name;
      _cycleLength = ex.cycleLengthDays;
      _slots = List<String?>.from(ex.sequence);
      _effectiveFrom = widget.newEffectiveFrom ?? ex.effectiveFrom;
    } else {
      _applyPreset(_presets.first);
      _effectiveFrom = _todayIso();
      _name = 'My pattern';
    }
  }

  String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void _applyPreset(_Preset preset) {
    final templates = widget.service.templates(widget.jobId);
    final firstTemplate = templates.isNotEmpty ? templates.first.id : null;
    _cycleLength = preset.length;
    _slots = [
      for (final work in preset.workSlots) work ? firstTemplate : null,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final templates = widget.service.templates(widget.jobId);
    return Scaffold(
      appBar: AppBar(
          title: Text(_isNewVersion ? 'New version of ${widget.existing!.name}'
                                    : 'Pattern builder')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.visibility),
                  label: const Text('Preview'),
                  onPressed: _preview,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save pattern'),
                  onPressed: templates.isEmpty ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            decoration: const InputDecoration(labelText: 'Pattern name'),
            onChanged: (v) => _name = v.trim().isEmpty ? 'My pattern' : v.trim(),
            controller: TextEditingController(text: _name),
          ),
          const SizedBox(height: 12),
          const Text('Cycle preset', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final p in _presets)
                ChoiceChip(
                  label: Text('${p.name} (${p.length}d)'),
                  selected: p.length == _cycleLength,
                  onSelected: (_) => setState(() => _applyPreset(p)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text('Effective from $_effectiveFrom'),
                  onPressed: _pickEffectiveFrom,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Slots (OFF days are not scheduled)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          for (var i = 0; i < _slots.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('${i + 1}',
                        style: const TextStyle(color: Colors.blueGrey)),
                  ),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('slot-${i}_$_cycleLength'),
                      initialValue: _slots[i],
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('OFF')),
                        for (final t in templates)
                          DropdownMenuItem<String?>(
                              value: t.id, child: Text(t.name)),
                      ],
                      onChanged: (v) => setState(() => _slots[i] = v),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickEffectiveFrom() async {
    final initial = DateTime.tryParse(_effectiveFrom);
    final ex = widget.existing;
    // A new version must start STRICTLY after the version it closes (D1);
    // the picker enforces that instead of failing later.
    final earliest = ex == null
        ? DateTime(2020)
        : DateTime.parse(ex.effectiveFrom).add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial != null && initial.isAfter(earliest)
          ? initial
          : earliest,
      firstDate: earliest,
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _effectiveFrom = '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  ShiftPattern _buildPattern() {
    // D9: when creating a NEW VERSION the anchor stays with the ORIGINAL
    // version (phase continuity) — the preview must project the SAME phase the
    // engine's createNewVersion will produce, or preview would show different
    // weekdays than what actually gets saved (review M1b, result12 §7).
    return ShiftPattern(
      id: slugId('pat', [_name, widget.jobId, _effectiveFrom]),
      jobId: widget.jobId,
      name: _name,
      type: 'FIXED_CYCLE',
      cycleLengthDays: _cycleLength,
      sequence: List<String?>.from(_slots),
      anchorDate: widget.existing?.anchorDate ?? _effectiveFrom,
      defaultTimezone: widget.service
          .jobs()
          .firstWhere((j) => j.id == widget.jobId)
          .defaultTimezone,
      effectiveFrom: _effectiveFrom,
    );
  }

  void _preview() {
    final templates = widget.service.templates(widget.jobId);
    final pattern = _buildPattern();
    final from = _effectiveFrom;
    final end = _addDays(from, 13);
    final projection = projectOccurrences(
      pattern: pattern,
      rangeStart: from,
      rangeEnd: end,
      templates: templates,
    );
    final localRanges = <(String, String, String)>[]; // date, time, name
    for (final o in projection.occurrences) {
      final t = templates.firstWhere((t) => t.id == o.templateId);
      final wall = widget.service.localWallTime(o);
      if (wall == null) continue;
      final name = t.name;
      localRanges.add(
          ('${wall.date} ${wall.start}–${wall.end}', name, t.id));
    }
    localRanges.sort((a, b) => a.$1.compareTo(b.$1));
    // RC plan §B6 — income impact of the re-version over the CURRENT week
    // (persist:false; preview only — nothing is written).
    final impact = _isNewVersion && widget.service.payEnabled
        ? widget.service.estimateReversionImpact(
            jobId: widget.jobId, nextVersion: pattern)
        : null;
    final impactSection = impact == null
        ? const <Widget>[]
        : [
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            const Text('Estimated this week (income impact)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            if (impact.available)
              Text(_impactText(impact),
                  style: const TextStyle(fontSize: 13))
            else
              Text('Unable to calculate accurately: '
                  '${impact.unavailableReason}',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.orange)),
          ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Preview — first 14 days'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$from → $end  ·  ${localRanges.length} shifts',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (projection.issues.isNotEmpty) ...[
                  const Text('Issues:',
                      style: TextStyle(color: Colors.orange)),
                  for (final issue in projection.issues)
                    Text('• ${issue.code}: ${issue.message}',
                        style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                ],
                for (final (line, name, _) in localRanges)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text('$line  ·  $name', style: const TextStyle(fontSize: 13)),
                  ),
                ...impactSection,
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _save() {
    final templates = widget.service.templates(widget.jobId);
    final ex = widget.existing;
    final error = runWrite(() {
      if (ex == null) {
        widget.service.saveNewPattern(pattern: _buildPattern(), templates: templates);
        return;
      }
      if (_effectiveFrom.compareTo(ex.effectiveFrom) <= 0) {
        throw ArgumentError(
            'New version must start after ${ex.effectiveFrom}.');
      }
      // D1: closes [ex] at X−1 and persists the engine-built new version
      // (anchorDate carried over — D9 phase continuity).
      widget.service.changeRosterFrom(
        current: ex,
        newEffectiveFrom: _effectiveFrom,
        newName: _name,
        newCycleLengthDays: _cycleLength,
        newSequence: List<String?>.from(_slots),
        templates: templates,
      );
    });
    if (error != null) {
      // RC plan §A1 — a pattern/re-version failure must show, never crash;
      // nothing was written (changeRosterFrom rolls back atomically).
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ex == null
          ? 'Pattern saved.'
          : 'Pattern version created.')),
    );
    Navigator.of(context).pop(true);
  }

  String _addDays(String iso, int days) {
    final d = DateTime.parse(iso).add(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// RC §B6 — 'Before $X / After $Y / Impact +/-$Z' preview text.
  String _impactText(IncomeImpact impact) {
    final sign = impact.delta >= 0 ? '+' : '';
    return 'Before   \$${impact.before.toStringAsFixed(2)}\n'
        'After    \$${impact.after.toStringAsFixed(2)}\n'
        'Impact   $sign\$${impact.delta.toStringAsFixed(2)}';
  }
}
