// =============================================================================
// DST resolution dialog (Gate C B1 / D-C5; RC plan §D — REAL resolution).
//
// The engine NEVER auto-selects an interpretation for a DST gap or overlap
// (D4). Two situations reach this dialog:
//
//   NONEXISTENT  — the local time falls in a spring-forward gap (clocks jump
//                  forward and skip that hour). There is nothing to pick —
//                  the time cannot be stored at all. The dialog explains and
//                  the user must choose another time (block-save).
//   AMBIGUOUS    — the local time occurs twice in a fall-back overlap. The
//                  dialog offers EVERY candidate interpretation with its
//                  offset/abbreviation (e.g. "01:30 UTC-04:00 (EDT)" vs
//                  "01:30 UTC-05:00 (EST)") and the user EXPLICITLY picks
//                  one. The chosen offset (minutes) is returned to the
//                  caller and travels in the override payload
//                  (startOffsetMinutes/endOffsetMinutes) so the stored UTC
//                  instant is exactly the interpretation the user picked —
//                  never a guess, never silently re-resolved.
//
// Return value: null when the user cancels; otherwise [DstResolutionOutcome].
// For AMBIGUOUS the outcome carries [selectedOffsetMinutes] ONLY after an
// explicit pick — the caller persists it; without a pick nothing is written.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:shiftease/core/time/time_types.dart';

/// A candidate instant for an ambiguous local time (fall-back overlap).
class DstCandidate {
  final UtcInstant utc;
  final String local; // civil time, repeated with the offset that applies
  final String offsetLabel; // e.g. "-04:00 (EDT)" vs "-05:00 (EST)"

  /// The offset in MINUTES east of UTC (e.g. -240 for EDT, -300 for EST) —
  /// the value stored on the payload when the user picks this candidate.
  final int offsetMinutes;

  const DstCandidate({
    required this.utc,
    required this.local,
    required this.offsetLabel,
    required this.offsetMinutes,
  });
}

class DstResolutionOutcome {
  /// Whether the user acknowledged the situation (vs just cancelling).
  final bool acknowledged;

  /// For AMBIGUOUS: the offset in minutes of the interpretation the user
  /// EXPLICITLY picked. Null when nothing was picked (nonexistent case, or
  /// the user acknowledged without choosing — which still refuses the write).
  final int? selectedOffsetMinutes;

  /// For AMBIGUOUS: which candidate the user picked (0-based), else null.
  final int? selectedIndex;

  const DstResolutionOutcome({
    required this.acknowledged,
    this.selectedOffsetMinutes,
    this.selectedIndex,
  });
}

/// Labels each ambiguous candidate with its offset/abbreviation in [timezone].
List<DstCandidate> dstCandidatesFor(
  List<UtcInstant> options,
  String timezone, {
  required String localTime,
}) {
  final tz.Location location;
  try {
    location = tz.getLocation(timezone);
  } catch (_) {
    return const []; // unknown zone: no candidates to label
  }
  return [
    for (final u in options)
      _candidateFor(u, location, localTime: localTime),
  ];
}

DstCandidate _candidateFor(
  UtcInstant u,
  tz.Location location, {
  required String localTime,
}) {
  String offsetLabel = '';
  var offsetMinutes = 0;
  try {
    final z = location.lookupTimeZone(u.millisecondsSinceEpoch).timeZone;
    final total = z.offset;
    offsetMinutes = total ~/ 60000;
    final sign = total < 0 ? '-' : '+';
    final abs = total.abs();
    final h = (abs ~/ 3600000).toString().padLeft(2, '0');
    final m = ((abs % 3600000) ~/ 60000).toString().padLeft(2, '0');
    final abbr = z.abbreviation.isEmpty ? '' : ' (${z.abbreviation})';
    offsetLabel = 'UTC$sign$h:$m$abbr';
  } catch (_) {
    offsetLabel = u.isoString;
  }
  return DstCandidate(
    utc: u,
    local: localTime,
    offsetLabel: offsetLabel,
    offsetMinutes: offsetMinutes,
  );
}

/// Show the DST dialog for one problematic local time.
///
/// [type] is [DstAmbiguityType.nonexistent] or [DstAmbiguityType.ambiguous].
/// [options] (the candidate instants) is required for the ambiguous case.
Future<DstResolutionOutcome?> showDstResolutionDialog(
  BuildContext context, {
  required DstAmbiguityType type,
  required String date,
  required String time,
  required String timezone,
  List<UtcInstant>? options,
}) {
  assert(type == DstAmbiguityType.ambiguous || type == DstAmbiguityType.nonexistent,
      'Only DST gap/overlap situations reach this dialog.');
  final isAmbiguous = type == DstAmbiguityType.ambiguous;
  final candidates = isAmbiguous
      ? dstCandidatesFor(options ?? const [], timezone, localTime: time)
      : const <DstCandidate>[];
  return showDialog<DstResolutionOutcome>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      var selected = -1; // radio index; -1 = nothing picked yet
      return StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(isAmbiguous
              ? 'Time occurs twice (DST)'
              : 'Time does not exist (DST)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAmbiguous
                      ? '$time on $date happens TWICE in $timezone — the '
                          'clocks fall back and that local time repeats. Pick '
                          'which interpretation to store (ShiftEase never '
                          'picks one for you), or change the time.'
                      : '$time on $date does NOT exist in $timezone — the '
                          'clocks spring forward and that local time is '
                          'skipped. ShiftEase never rounds or guesses. Choose '
                          'a different time (or cancel).',
                  style: theme.textTheme.bodyMedium,
                ),
                if (isAmbiguous) ...[
                  const SizedBox(height: 12),
                  Text('Pick the interpretation to store:',
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  RadioGroup<int>(
                    groupValue: selected,
                    onChanged: (v) => setDialog(() => selected = v ?? -1),
                    child: Column(
                      children: [
                        for (var i = 0; i < candidates.length; i++)
                          RadioListTile<int>(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: i,
                            title: Text(
                                '$time ${candidates[i].offsetLabel}  '
                                '(${candidates[i].utc.isoString})'),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              // AMBIGUOUS: only an explicit pick resolves; without one the
              // button keeps the old wording and refuses the write (the
              // payload would carry no interpretation — D-C5).
              onPressed: () {
                if (isAmbiguous && selected < 0) {
                  Navigator.of(ctx).pop(DstResolutionOutcome(
                    acknowledged: true,
                    selectedIndex: null,
                  ));
                  return;
                }
                Navigator.of(ctx).pop(DstResolutionOutcome(
                  acknowledged: true,
                  selectedIndex: isAmbiguous ? selected : null,
                  selectedOffsetMinutes:
                      isAmbiguous ? candidates[selected].offsetMinutes : null,
                ));
              },
              child: Text(isAmbiguous
                  ? 'Store the picked interpretation'
                  : 'Choose a different time'),
            ),
          ],
        ),
      );
    },
  );
}
