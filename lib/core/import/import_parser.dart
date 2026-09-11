// =============================================================================
// ShiftEase Import Pipeline — Document Parser (plan2 §3.2 Bước 1)
// =============================================================================
//
// PASTE_TEXT + CSV only. IMAGE/PDF require OCR and are gated behind the M4.5
// spike test — the engine refuses them with OCR_PENDING_SPIKE (no speculative
// OCR architecture until real rosters prove the pipeline).
//
// The parser is AUDIT-FAITHFUL: every output RawEntry keeps its original line
// text + line number so the ImportSession can answer "why is Sep 03 a Night
// shift?" (plan2 §3.3) from the stored raw extraction.
//
// Date tokens are resolved LATER (interpreter) against the user-chosen
// referenceDate — never auto-guessed here or from the system clock.
//
// =============================================================================

import 'import_types.dart';

/// Outcome of running a document through the parser.
class SourceParseResult {
  final RawExtraction? extraction;
  final ImportError? error;

  const SourceParseResult({this.extraction, this.error});

  bool get isSuccess => extraction != null && error == null;
}

/// How two-digit/numeric dates should be read.
enum DateOrder {
  monthDay, // 03/09 = Mar 9 (US default)
  dayMonth, // 03/09 = 3 Sep (UK/DE)
}

const Map<String, int> _monthIndex = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

const Map<String, int> _weekdayIndex = {
  'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
};

int _daysInMonth(int year, int month) {
  // DateTime.utc normalizes overflow; compare components to detect e.g. Feb 30.
  final probe = DateTime.utc(year, month + 1, 0);
  return probe.day;
}

String _pad2(int v) => v.toString().padLeft(2, '0');

/// Strict ISO builder: returns padded 'yyyy-MM-dd' only for real calendar
/// dates (M1 — never let an invalid date silently roll over).
String? _isoDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > _daysInMonth(year, month)) {
    return null;
  }
  return '$year-${_pad2(month)}-${_pad2(day)}';
}

/// Resolve a free-form date token ("Sep 03", "03 Sep", "2026-09-03",
/// "03/09/2026", "Mon 3rd") to an ISO date, anchored on [referenceDate].
///
/// Returns null when the token cannot be pinned to a real calendar date —
/// that candidate then stays LOW-confidence and cannot be committed.
String? resolveDateToken(String token, {
  required String referenceDate,
  DateOrder dateOrder = DateOrder.monthDay,
}) {
  final t = token.trim();
  if (t.isEmpty) return null;
  final ref = DateTime.parse(referenceDate);

  // ISO yyyy-MM-dd / yyyy/MM/dd.
  final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(t);
  if (iso != null) {
    return _isoDate(int.parse(iso.group(1)!), int.parse(iso.group(2)!),
        int.parse(iso.group(3)!));
  }

  // "Sep 03 [2026]" / "Sep 3rd, 2026" / "03 Sep 2026".
  final monthFirst = RegExp(
          r'^([A-Za-z]{3,})\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s*(\d{4}))?$')
      .firstMatch(t);
  final dayFirst = RegExp(
          r'^(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,})\.?(?:,?\s*(\d{4}))?$')
      .firstMatch(t);
  final mf = monthFirst != null ? _monthIndex[monthFirst.group(1)!.toLowerCase().substring(0, 3)] : null;
  final df = dayFirst != null ? _monthIndex[dayFirst.group(2)!.toLowerCase().substring(0, 3)] : null;
  if (mf != null) {
    final year = monthFirst!.group(3) != null
        ? int.parse(monthFirst.group(3)!)
        : ref.year;
    return _isoDate(year, mf, int.parse(monthFirst.group(2)!));
  }
  if (df != null) {
    final year = dayFirst!.group(3) != null
        ? int.parse(dayFirst.group(3)!)
        : ref.year;
    return _isoDate(year, df, int.parse(dayFirst.group(1)!));
  }

  // Numeric: "03/09", "03/09/2026", "3-9-26".
  final num = RegExp(r'^(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?$')
      .firstMatch(t);
  if (num != null) {
    var a = int.parse(num.group(1)!);
    var b = int.parse(num.group(2)!);
    var year = ref.year;
    if (num.group(3) != null) {
      final y = num.group(3)!;
      year = y.length == 2 ? 2000 + int.parse(y) : int.parse(y);
    }
    // Disambiguate by order preference + obvious overflow (>12 can only be
    // the day of the other role).
    int month, day;
    if (dateOrder == DateOrder.dayMonth || a > 12) {
      month = b; day = a;
    } else {
      month = a; day = b;
    }
    return _isoDate(year, month, day);
  }

  // Weekday with optional ordinal day: "Mon", "Mon 3rd".
  final wd = RegExp(
          r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*(?:\s+(\d{1,2})(?:st|nd|rd|th)?)?$',
          caseSensitive: false)
      .firstMatch(t);
  if (wd != null) {
    final target = _weekdayIndex[wd.group(1)!.toLowerCase().substring(0, 3)]!;
    final dayOfMonth = wd.group(2) != null ? int.parse(wd.group(2)!) : null;
    if (dayOfMonth == null) return null; // bare weekday — not pinnable safely
    // Try the reference month, then the next (rosters are near-term; silently
    // reaching into a PAST month is worse than asking the user).
    for (final delta in [0, 1]) {
      final base = DateTime.utc(ref.year, ref.month + delta, 1);
      final iso = _isoDate(base.year, base.month, dayOfMonth);
      if (iso == null) continue;
      final thatDay = DateTime.parse(iso);
      if (thatDay.weekday == target) return iso;
    }
    return null; // weekday+day mismatch in nearby months — leave ambiguous
  }

  return null;
}

/// Normalize a start/end pair to "HH:mm" / "HH:mm[+1]": when the end is not
/// strictly after the start the shift crosses midnight and the end carries a
/// "+1" marker (matching core/time overnight conventions).
({String start, String end})? normalizeTimePair(String start, String end) {
  final st = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(start.trim());
  final en = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(end.trim());
  if (st == null || en == null) return null;
  int mins(RegExpMatch m) =>
      int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  final s = '${_pad2(int.parse(st.group(1)!))}:${st.group(2)}';
  var e = '${_pad2(int.parse(en.group(1)!))}:${en.group(2)}';
  if (mins(en) <= mins(st)) e = '$e+1';
  return (start: s, end: e);
}

// ---------------------------------------------------------------------------
// PASTE_TEXT
// ---------------------------------------------------------------------------

/// Known shift-type labels (case-insensitive match on the trimmed token).
const Set<String> _shiftLabels = {'day', 'night', 'evening', 'off'};

final String _monthNames =
    'Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec';
final String _weekdayNames = 'Mon|Tue|Wed|Thu|Fri|Sat|Sun';

/// Ordered date-phrase recognizers. Each returns (start, end, token) in
/// [original] or null. Phrases may be followed by other roster content
/// ("Sep 03 Day 07:00-19:00") — none of the patterns is end-anchored.
List<(int, int, String)? Function(String)> get _datePhraseRecognizers => [
  // ISO "2026-09-03"
  (s) {
    final m = RegExp(r'\b(\d{4}[-/.]\d{1,2}[-/.]\d{1,2})\b').firstMatch(s);
    return m == null ? null : (m.start, m.end, m.group(1)!);
  },
  // "Sep 03 [2026]"
  (s) {
    final m = RegExp(r'\b(' +
            _monthNames +
            r')[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?')
        .firstMatch(s);
    return m == null ? null : (m.start, m.end, m.group(0)!.trim());
  },
  // "03 Sep [2026]"
  (s) {
    final m = RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(' +
            _monthNames +
            r')[a-z]*\.?(?:,?\s+(\d{4}))?')
        .firstMatch(s);
    return m == null ? null : (m.start, m.end, m.group(0)!.trim());
  },
  // "Mon 3rd" (weekday + ordinal) then bare "Mon"
  (s) {
    final m = RegExp(r'\b(' +
            _weekdayNames +
            r')[a-z]*(?:\s+\d{1,2}(?:st|nd|rd|th)?)?')
        .firstMatch(s);
    return m == null ? null : (m.start, m.end, m.group(0)!.trim());
  },
  // Numeric "03/09", "03/09/2026"
  (s) {
    final m = RegExp(r'\b(\d{1,2}[/.-]\d{1,2}(?:[/.-]\d{2,4})?)\b')
        .firstMatch(s);
    return m == null ? null : (m.start, m.end, m.group(1)!);
  },
];

/// One pasted line -> a RawEntry. Unknown tokens are tolerated but flagged so
/// the interpreter can downgrade confidence ("Wed??" is garbage, not a shift).
RawEntry parseTextLine(String line, int lineNumber) {
  final original = line.trim();
  if (original.isEmpty) {
    return RawEntry(
        lineNumber: lineNumber, original: original, hasGarbage: false);
  }

  // 1. Date phrase — earliest recognizer wins.
  (int, int, String)? dateSpan;
  for (final recognize in _datePhraseRecognizers) {
    final hit = recognize(original);
    if (hit != null &&
        (dateSpan == null || hit.$1 < dateSpan.$1)) {
      dateSpan = hit;
    }
  }
  final dateToken = dateSpan?.$3;

  // 2. Time pair "HH:mm-HH:mm" (en/em dash tolerated).
  String? start;
  String? end;
  int? timeStart;
  int? timeEnd;
  final tp = RegExp(r'(\d{1,2}:\d{2})\s*[-–—~]\s*(\d{1,2}:\d{2})')
      .firstMatch(original);
  if (tp != null) {
    final norm = normalizeTimePair(tp.group(1)!, tp.group(2)!);
    if (norm != null) {
      start = norm.start;
      end = norm.end;
      timeStart = tp.start;
      timeEnd = tp.end;
    }
  }

  // 3. Classify the leftover words (date phrase + time span excluded).
  final leftover = StringBuffer();
  var pos = 0;
  // Flush the gap [pos, p) into the leftover buffer, then jump to p.
  void keepTo(int p) {
    if (p > pos) leftover.write(original.substring(pos, p));
    pos = p;
  }
  // Remove [a, b): flush up to a, then jump over the span without copying.
  void remove(int a, int b) {
    keepTo(a);
    pos = b;
  }
  if (dateSpan != null) remove(dateSpan.$1, dateSpan.$2);
  if (timeStart != null) remove(timeStart, timeEnd!);
  keepTo(original.length);

  String? label;
  var garbage = false;
  final explicitOff = RegExp(r'\boff\b', caseSensitive: false)
      .hasMatch(leftover.toString());
  for (final w in leftover.toString().split(RegExp(r'\s+'))) {
    final clean = w.toLowerCase().replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
    if (clean.isEmpty) continue; // punctuation-only leftovers ("??") are inert
    if (_shiftLabels.contains(clean)) {
      label ??= clean == 'off' ? 'OFF' : _capitalize(clean);
      continue;
    }
    garbage = true; // uninterpretable word — not silently trusted
  }

  return RawEntry(
    lineNumber: lineNumber,
    original: original,
    dateToken: dateToken,
    startTime: start,
    endTime: end,
    shiftTypeLabel: explicitOff ? 'OFF' : label,
    hasGarbage: garbage,
  );
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Parse pasted roster text into raw entries (one per non-empty line).
RawExtraction parseTextRoster(String rawText) {
  final lines = rawText.split('\n');
  final entries = <RawEntry>[];
  for (var i = 0; i < lines.length; i++) {
    final e = parseTextLine(lines[i], i + 1);
    if (e.original.isNotEmpty) entries.add(e);
  }
  return RawExtraction(sourceType: ImportSourceType.pasteText, entries: entries);
}

// ---------------------------------------------------------------------------
// CSV
// ---------------------------------------------------------------------------

const Map<String, String> _knownHeaderSynonym = {
  'date': 'date',
  'day': 'date',
  'shift': 'shiftType',
  'shifttype': 'shiftType',
  'type': 'shiftType',
  'start': 'startTime',
  'starttime': 'startTime',
  'in': 'startTime',
  'end': 'endTime',
  'endtime': 'endTime',
  'out': 'endTime',
};

/// Parse a CSV roster. [columnMapping] maps logical field -> header name;
/// when null the header row is auto-detected from known synonyms. Returns a
/// parse error when no usable columns are found (IMPORT-007).
SourceParseResult parseCsvRoster(
  String rawCsv, {
  Map<String, String>? columnMapping,
}) {
  final lines = rawCsv
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return SourceParseResult(
        error: const ImportError(
            code: ImportErrorCodes.parseFailed,
            message: 'CSV input is empty.',
            recoverable: true));
  }

  final header = _csvRow(lines.first);
  if (header.isEmpty) {
    return const SourceParseResult(
        error: ImportError(
            code: ImportErrorCodes.parseFailed,
            message: 'CSV has no header row.',
            recoverable: true));
  }

  Map<String, String> mapping;
  if (columnMapping != null) {
    mapping = columnMapping;
  } else {
    // Auto-detect: header cell (lowercased, no spaces) -> logical field.
    mapping = {};
    for (final cell in header) {
      final key = cell.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      final field = _knownHeaderSynonym[key];
      if (field != null && !mapping.containsKey(field)) {
        mapping[field] = cell;
      }
    }
  }

  // No usable columns → a clear PARSE_FAILED, never a session of all-null
  // LOW candidates that would make the user guess. This covers garbage CSV
  // (header cells that match no known synonym — IMPORT-007) even when data
  // rows exist below the header.
  if (mapping.isEmpty) {
    return const SourceParseResult(
        error: ImportError(
            code: ImportErrorCodes.parseFailed,
            message: 'CSV header has no recognizable columns — expected '
                'date/shift/start/end (or pass a columnMapping).',
            recoverable: true));
  }

  final colIndex = <String, int>{};
  for (final field in mapping.keys) {
    final idx = header.indexOf(mapping[field]!);
    if (idx < 0) {
      return SourceParseResult(
          error: ImportError(
              code: ImportErrorCodes.parseFailed,
              message: 'Column "${mapping[field]}" (for $field) not found '
                  'in header row.',
              recoverable: true));
    }
    colIndex[field] = idx;
  }

  final entries = <RawEntry>[];
  for (var i = 1; i < lines.length; i++) {
    final cells = _csvRow(lines[i]);
    if (cells.length == 1 && cells.first.trim().isEmpty) continue;
    String cell(String field) =>
        colIndex.containsKey(field) && colIndex[field]! < cells.length
            ? cells[colIndex[field]!].trim()
            : '';

    final dateRaw = cell('date');
    final typeRaw = cell('shiftType').toLowerCase();
    final startRaw = cell('startTime');
    final endRaw = cell('endTime');

    String? start;
    String? end;
    if (startRaw.isNotEmpty && endRaw.isNotEmpty) {
      final norm = normalizeTimePair(startRaw, endRaw);
      if (norm != null) {
        start = norm.start;
        end = norm.end;
      }
    }

    entries.add(RawEntry(
      lineNumber: i + 1,
      original: lines[i],
      dateToken: dateRaw.isEmpty ? null : dateRaw,
      startTime: start,
      endTime: end,
      // '?'/unknown markers are NOT labels (D-2): a '?' cell means the data is
      // uncertain and must stay LOW-confidence — never HIGH like a stated type.
      shiftTypeLabel: typeRaw.isEmpty || typeRaw == '?'
          ? null
          : (typeRaw == 'off' ? 'OFF' : _capitalize(typeRaw)),
    ));
  }

  if (entries.isEmpty) {
    return const SourceParseResult(
        error: ImportError(
            code: ImportErrorCodes.parseFailed,
            message: 'No data rows found in CSV.',
            recoverable: true));
  }
  return SourceParseResult(
      extraction:
          RawExtraction(sourceType: ImportSourceType.csv, entries: entries));
}

/// Header row of [rawCsv] (first non-empty line, quote-aware) — the options
/// the CSV mapping UI offers per column dropdown (RC plan §C1). Empty when
/// the input has no lines.
List<String> csvHeaderRow(String rawCsv) {
  final lines = rawCsv
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return const [];
  return _csvRow(lines.first).map((c) => c.trim()).toList();
}

/// Auto-detect the mapping (logical field -> header cell) from a header row
/// using the SAME synonyms the engine applies when [columnMapping] is null.
/// Exposed so the CSV mapping UI can pre-select the detected columns and the
/// validation card reasons about exactly the mapping that will be used (C1).
Map<String, String> autoDetectCsvMapping(List<String> header) {
  final mapping = <String, String>{};
  for (final cell in header) {
    final key = cell.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final field = _knownHeaderSynonym[key];
    if (field != null && !mapping.containsKey(field)) {
      mapping[field] = cell;
    }
  }
  return mapping;
}

/// Split one CSV line honoring double quotes (roster columns rarely use them,
/// but a parser that chokes on quotes is worse than one that handles them).
List<String> _csvRow(String line) {
  final cells = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch == ',' && !inQuotes) {
      cells.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  cells.add(buf.toString());
  return cells;
}
