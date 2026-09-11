// =============================================================================
// RC plan §C2 — Re-import diff (pure, engine-free).
//
// Compares the incoming roster (new parse) against the job's CURRENT
// committed roster and buckets every date into Added / Removed / Modified /
// Unchanged. Modified items carry old → new. Pure records in, pure result
// out — the caller (ScheduleService/UI) does the UTC↔local conversion.
// =============================================================================

/// One roster day in local wall-clock form: [start]/[end] null = OFF.
typedef RosterRow = ({String date, String? start, String? end});

/// A single date's bucket with both sides (null side = absent that day).
class RosterDiffItem {
  final String date;

  /// 'added' | 'removed' | 'modified' | 'unchanged'
  final String kind;
  final String? oldStart;
  final String? oldEnd;
  final String? newStart;
  final String? newEnd;

  const RosterDiffItem({
    required this.date,
    required this.kind,
    this.oldStart,
    this.oldEnd,
    this.newStart,
    this.newEnd,
  });

  /// "07:00–19:00" or "OFF".
  String? get oldLabel => _label(oldStart, oldEnd);
  String? get newLabel => _label(newStart, newEnd);

  static String? _label(String? s, String? e) =>
      s == null && e == null ? 'OFF' : (s == null ? null : '$s–$e');
}

class RosterDiff {
  final List<RosterDiffItem> items;

  const RosterDiff(this.items);

  int get added => items.where((i) => i.kind == 'added').length;
  int get removed => items.where((i) => i.kind == 'removed').length;
  int get modified => items.where((i) => i.kind == 'modified').length;
  int get unchanged => items.where((i) => i.kind == 'unchanged').length;

  /// Signed hours delta: new roster hours minus old roster hours (shift rows
  /// only; OFF days carry 0). Negative = fewer hours than before.
  double get hoursDelta {
    double hours(RosterDiffItem i, {required bool old}) {
      final s = old ? i.oldStart : i.newStart;
      final e = old ? i.oldEnd : i.newEnd;
      if (s == null || e == null) return 0;
      return _hours(s, e);
    }

    var delta = 0.0;
    for (final i in items) {
      if (i.kind == 'added') {
        delta += hours(i, old: false);
      } else if (i.kind == 'removed') {
        delta -= hours(i, old: true);
      } else if (i.kind == 'modified') {
        delta += hours(i, old: false) - hours(i, old: true);
      }
    }
    return delta;
  }
}

/// [committed] = the current committed roster (local wall rows);
/// [incoming]  = the new parse's rows. Days are matched by date; a date
/// present in both with identical times (or both OFF) is Unchanged, same
/// date different times (including shift → OFF / OFF → shift) is Modified.
RosterDiff computeRosterDiff({
  required List<RosterRow> committed,
  required List<RosterRow> incoming,
}) {
  final oldByDate = <String, RosterRow>{for (final r in committed) r.date: r};
  final newByDate = <String, RosterRow>{for (final r in incoming) r.date: r};
  final dates = <String>{
    ...oldByDate.keys,
    ...newByDate.keys,
  }.toList()..sort();

  final items = <RosterDiffItem>[
    for (final date in dates)
      _bucket(date, oldByDate[date], newByDate[date]),
  ];
  return RosterDiff(items);
}

RosterDiffItem _bucket(String date, RosterRow? oldR, RosterRow? newR) {
  if (oldR == null) {
    return RosterDiffItem(
        date: date, kind: 'added', newStart: newR!.start, newEnd: newR.end);
  }
  if (newR == null) {
    return RosterDiffItem(
        date: date, kind: 'removed', oldStart: oldR.start, oldEnd: oldR.end);
  }
  final same = oldR.start == newR.start && oldR.end == newR.end;
  return RosterDiffItem(
    date: date,
    kind: same ? 'unchanged' : 'modified',
    oldStart: oldR.start,
    oldEnd: oldR.end,
    newStart: newR.start,
    newEnd: newR.end,
  );
}

/// "HH:mm" (with +1 overnight encoded as end < start) → decimal hours.
/// Equal start and end means a zero-length row (0h), NOT a 24h shift —
/// only end STRICTLY BEFORE start wraps to the next day (RC review L2).
double _hours(String start, String end) {
  double parse(String t) {
    final p = t.split(':');
    final h = int.tryParse(p.isEmpty ? '' : p[0]) ?? 0;
    final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
    return h + m / 60.0;
  }

  final s = parse(start);
  var e = parse(end);
  if (e < s) e += 24; // overnight (end carries +1); e == s is 0h
  return e - s;
}