// =============================================================================
// ShiftEase Domain Service — ScheduleService (M1 gate, plan5 §4)
// =============================================================================
//
// The only seam between the UI (features/) and the persistence layer
// (core/db). It wraps the typed repositories and the PURE engines behind
// use-case shaped calls. Dependency rule (plan2 §1.1): domain imports only
// core/*; core never imports domain/features/app.
//
// Rules enforced here (the UI never bypasses them):
//   - A job/pattern/template/override is ALWAYS persisted through the repo
//     (single DB, transactional). No in-memory shadow state.
//   - Every user edit to an occurrence is an Override in the append-only log
//     (INVARIANT-001: the pattern is never mutated; plan3 P0-6 chain).
//   - A CREATE override is saved with the official patternId convention
//     (schema v2) — the repo throws if a caller forgets it.
//   - Rendering always goes through ScheduleRepository.renderJobSchedule
//     (baseline from ACTIVE versions + full override log replay through the
//     pure engine), never a hand-rolled render in the UI.
//   - Display times are derived from the occurrence's OWN timezone from its
//     stored UTC (INVARIANT-007 / INVARIANT-002) — never device-local.
// =============================================================================

import 'dart:math';

import 'package:timezone/timezone.dart' as tz;

import 'package:sqlite3/sqlite3.dart' as sq;

import 'package:shiftease/core/db/backup_restore.dart'
    as backup_mod;
import 'package:shiftease/core/db/security_gate.dart' as security_gate;
import 'package:shiftease/core/db/backup_restore.dart'
    show BackupException;
import 'package:shiftease/core/db/db.dart' show schemaVersion;
import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/import/import_diff.dart' show RosterRow;
import 'package:shiftease/core/import/import_engine.dart'
    show TemplateSpec, commitImport, parseDocument;
import 'package:shiftease/core/import/import_types.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/domain/income_estimate.dart';
import 'package:shiftease/core/pattern/pattern_engine.dart'
    show createNewVersion, projectOccurrences;
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/time/time_engine.dart'
    show calculateDuration, resolveShift;
import 'package:shiftease/core/time/time_types.dart' show UtcInstant;

/// IANA zones offered as quick choices in the job form. Any valid IANA zone
/// is accepted (free text validated against the same tz database core/time
/// uses) — this list is UI convenience only, never a constraint.
const List<String> commonTimezones = [
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'Europe/London',
  'Europe/Berlin',
  'Australia/Sydney',
  'Australia/Lord_Howe',
  'Asia/Ho_Chi_Minh',
  'UTC',
];

/// Local wall-clock rendering of an occurrence (INVARIANT-007: the
/// occurrence's own timezone, from the stored UTC instant — never the
/// device timezone, never local-time subtraction).
class LocalTimeRange {
  final String date; // local civil date (ISO) of the shift start
  final String start; // "HH:mm" local civil
  final String end; // "HH:mm" local civil
  const LocalTimeRange({
    required this.date,
    required this.start,
    required this.end,
  });
}

/// Deterministic job/template/pattern id from a human name. Stable across
/// restarts (rows are keyed by it) and collision-resistant for M1.
String slugId(String kind, List<String> parts) {
  final joined = parts.join('|');
  var h = 0;
  for (final c in joined.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final slug = parts.first
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp('^_+|_+\$'), '');
  final name = slug.isEmpty ? 'x' : slug.substring(0, slug.length > 40 ? 40 : slug.length);
  return '${kind}_${name}_${h.toRadixString(16)}';
}

class ScheduleService {
  final PatternRepository _patterns;
  final ScheduleRepository _schedule;
  final ImportRepository? _imports;
  final PayRuleRepository? _pay;
  final sq.Database _db;

  /// The master key used to open [_db], when it was opened encrypted
  /// (P7.2). Null for plain (test/in-memory) databases. The service never
  /// logs or persists it; it only feeds the §G probe so Settings can verify
  /// the LIVE connection's key, not just the library's capabilities.
  final String? _encryptionKeyHex;

  ScheduleService({
    required PatternRepository patterns,
    required ScheduleRepository schedule,
    required sq.Database db,
    ImportRepository? imports,
    PayRuleRepository? pay,
    String? encryptionKeyHex,
  })  : _patterns = patterns,
        _schedule = schedule,
        _db = db,
        _imports = imports,
        _pay = pay,
        _encryptionKeyHex = encryptionKeyHex;

  ImportRepository get _importRepo {
    final r = _imports;
    if (r == null) {
      throw StateError('ScheduleService constructed without an ImportRepository '
          'cannot run the import flow.');
    }
    return r;
  }

  /// Whether this service instance can run the M2 import flow (it was given an
  /// [ImportRepository]). Screens hide the Import entry when false.
  bool get importEnabled => _imports != null;

  // -- pay (Gate C B2 — income estimate + basic pay rules) ------------------

  PayRuleRepository get _payRepo {
    final r = _pay;
    if (r == null) {
      throw StateError('ScheduleService constructed without a PayRuleRepository '
          'cannot manage pay rules or estimate income.');
    }
    return r;
  }

  /// Whether income/PayRule features are available (composeService wires it).
  bool get payEnabled => _pay != null;

  // -- income impact (RC plan §B6 — preview with persist=false) -------------

  /// The current calendar week's shifts of [jobId] (Mon..Sun of today), from
  /// a persist:false render — the basis of every impact preview. Reading
  /// never writes the DB.
  List<ShiftOccurrence> currentWeekShifts(String jobId) {
    final now = DateTime.now();
    final mon = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - DateTime.monday));
    final start = _isoDateOf(mon);
    final end = _isoDateOf(mon.add(const Duration(days: 6)));
    return _schedule.renderJobSchedule(
      jobId: jobId,
      rangeStart: start,
      rangeEnd: end,
      persist: false,
    ).occurrences;
  }

  /// Price [current] vs [prospective] through the SAME estimator (RC §B6).
  /// Nothing is persisted — the caller decides whether to write. Either leg
  /// unavailable (missing rule / multi-version weekly OT / …) → UNAVAILABLE
  /// with the specific reason; never a guessed number.
  IncomeImpact estimateIncomeImpact({
    required String jobId,
    required List<ShiftOccurrence> current,
    required List<ShiftOccurrence> prospective,
  }) {
    WeekIncomeEstimate price(List<ShiftOccurrence> shifts) =>
        estimateJobIncome(
          shifts: shifts,
          jobId: jobId,
          activeRuleFor: (j, date) =>
              _payRepo.activeRuleFor(jobId: j, date: date),
        );
    final before = price(current);
    if (!before.available) {
      return IncomeImpact.unavailable(
          'Before: ${before.unavailableReason}');
    }
    final after = price(prospective);
    if (!after.available) {
      return IncomeImpact.unavailable('After: ${after.unavailableReason}');
    }
    return IncomeImpact(
      available: true,
      before: before.total,
      after: after.total,
      delta: after.total - before.total,
    );
  }

  /// Income impact of a ROSTER RE-VERSION preview (RC §B6) over the current
  /// week: before = the current effective schedule, after = the same week with
  /// the days >= [nextVersion.effectiveFrom] re-projected by the PROSPECTIVE
  /// pattern. Honesty guards:
  ///   - if the affected days carry overrides/imported rows (non-baseline
  ///     provenance) the preview would silently drop them → UNAVAILABLE;
  ///   - if the new projection cannot resolve every day → UNAVAILABLE;
  ///   - persist:false everywhere — nothing is ever written for a preview.
  IncomeImpact estimateReversionImpact({
    required String jobId,
    required ShiftPattern nextVersion,
  }) {
    final current = currentWeekShifts(jobId);
    final affected =
        current.where((o) => o.shiftDate.compareTo(nextVersion.effectiveFrom) >= 0);
    if (affected.any((o) => o.isImported || o.source != OccurrenceSource.baseline)) {
      return IncomeImpact.unavailable(
          'Overrides or imported rows exist on the changed days — cannot '
          'preview precisely.');
    }
    final templates = _patterns.templatesForJob(jobId);
    final segStart = nextVersion.effectiveFrom.compareTo(_weekStartIso()) > 0
        ? nextVersion.effectiveFrom
        : _weekStartIso();
    final projection = projectOccurrences(
      pattern: nextVersion,
      rangeStart: segStart,
      rangeEnd: _weekEndIso(),
      templates: templates,
    );
    if (projection.issues.isNotEmpty) {
      return IncomeImpact.unavailable(
          'The prospective version cannot resolve every day — cannot preview '
          'accurately.');
    }
    final prospective = <ShiftOccurrence>[
      ...current.where(
          (o) => o.shiftDate.compareTo(nextVersion.effectiveFrom) < 0),
      ...projection.occurrences,
    ];
    return estimateIncomeImpact(
        jobId: jobId, current: current, prospective: prospective);
  }

  String _weekStartIso() {
    final now = DateTime.now();
    final mon = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - DateTime.monday));
    return _isoDateOf(mon);
  }

  String _weekEndIso() {
    final now = DateTime.now();
    final mon = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - DateTime.monday));
    return _isoDateOf(mon.add(const Duration(days: 6)));
  }

  String _isoDateOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Persist a rule version (with its differential/OT children). Idempotent on
  /// identical payload; same-id + different payload throws (Gate A §A6).
  void savePayRule(PayRule rule) => _payRepo.savePayRule(rule: rule);

  /// PayRule versioning UX (plan_payrule_version_ux.md): the use-case behind
  /// the editor's Save button. The USER never deals with ids — saving an
  /// edited rule transparently mints a NEW version (new id, old version
  /// closed) instead of hitting the A6 immutability guard. Contract:
  ///
  /// - [rule] is the COMPLETE draft from the editor (already validated).
  /// - [existingId] — the id of the version being edited, or null for a
  ///   first create. NEVER re-save a changed payload under the same id.
  /// - Returns 'noOp' when the draft is identical to the existing version
  ///   (nothing written), 'created' for a first version, 'versioned' when a
  ///   new version was minted and the old one closed.
  ///
  /// Validation (Option B of the plan): a CHANGED draft must carry
  /// [rule.effectiveFrom] >= max(today, existing.effectiveFrom) — future
  /// versions never re-price the past (INVARIANT-006). Close + insert runs
  /// in ONE transaction; a failure rolls both back.
  String savePayRuleFromEditor({required PayRule rule, String? existingId}) {
    if (existingId == null) {
      _payRepo.savePayRule(rule: rule);
      return 'created';
    }
    final existingRows = _payRepo.allRulesFor(rule.jobId);
    final existing = existingRows.where((r) => r.id == existingId).firstOrNull;
    if (existing == null) {
      // Stale/unknown existingId (e.g. data deleted under us): fall back to
      // an honest create of the draft — still never a same-id overwrite.
      _payRepo.savePayRule(rule: rule);
      return 'created';
    }

    // Idempotent no-op: the editor's numeric round-trip can make an
    // untouched rule compare unequal; compare through canonical forms.
    if (_payRulesCanonical(existing) == _payRulesCanonical(rule)) {
      return 'noOp';
    }

    // Option B: changed payload must apply from >= max(today, existing.from).
    final today = DateTime.now();
    final todayIso =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final floorDate = todayIso.compareTo(existing.effectiveFrom) > 0
        ? todayIso
        : existing.effectiveFrom;
    if (rule.effectiveFrom.compareTo(floorDate) < 0) {
      throw ArgumentError(
          'Choose a From date on or after $floorDate to apply new rates.');
    }

    // Close the old version up to the day BEFORE the new From (inclusive
    // semantics: effectiveUntil >= date is still active), then insert the
    // new version atomically.
    final newFrom = DateTime.parse(rule.effectiveFrom);
    final dayBefore = newFrom.subtract(const Duration(days: 1));
    final untilIso =
        '${dayBefore.year.toString().padLeft(4, '0')}-${dayBefore.month.toString().padLeft(2, '0')}-${dayBefore.day.toString().padLeft(2, '0')}';
    _db.execute('BEGIN');
    try {
      _payRepo.closePayRuleVersion(
        ruleId: existingId,
        effectiveUntil: untilIso,
        ownsTransaction: false,
      );
      final newId = slugId('payrule', [rule.jobId, rule.effectiveFrom,
        existingId]);
      _payRepo.savePayRule(
        rule: PayRule(
          id: newId,
          jobId: rule.jobId,
          baseHourlyRate: rule.baseHourlyRate,
          differentials: rule.differentials,
          overtimeRules: rule.overtimeRules,
          effectiveFrom: rule.effectiveFrom,
        ),
        ownsTransaction: false,
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return 'versioned';
  }

  /// Canonical payload comparison for the idempotency check: base rate,
  /// sorted differentials, sorted OT rules, and the effectiveFrom date.
  /// Deliberately EXCLUDES id/effectiveUntil — closing metadata must not
  /// make an untouched save look "changed".
  String _payRulesCanonical(PayRule r) {
    String diffKey(PayDifferential d) =>
        '${d.type.name}|${d.mode.name}|${d.value}|'
        '${d.scope.name}|${d.window?.startLocal ?? '-'}|${d.window?.endLocal ?? '-'}';
    String otKey(OvertimeRule o) =>
        '${o.period.name}|${o.thresholdHours}|${o.multiplier}';
    final diffs = [...r.differentials]..sort((a, b) =>
        diffKey(a).compareTo(diffKey(b)));
    final ots = [...r.overtimeRules]..sort((a, b) => otKey(a).compareTo(otKey(b)));
    return ['${r.baseHourlyRate}', r.effectiveFrom, ...diffs.map(diffKey),
      ...ots.map(otKey)].join('#');
  }

  /// All rule versions of [jobId] (INVARIANT-006 — never rewritten history).
  List<PayRule> payRules(String jobId) => _payRepo.allRulesFor(jobId);

  /// The rule ACTIVE on [date] for [jobId] (newest effectiveFrom wins).
  PayRule? activePayRule({required String jobId, required String date}) =>
      _payRepo.activeRuleFor(jobId: jobId, date: date);

  /// Income estimate for [jobId] over [rangeStart..rangeEnd] (a week in the
  /// Today screen). Renders WITHOUT persisting and prices each shift under the
  /// rule active on its date. Returns an UNAVAILABLE estimate (never a guessed
  /// number) when the config cannot price the range accurately (Gate C B2).
  WeekIncomeEstimate estimateIncome({
    required String jobId,
    required String rangeStart,
    required String rangeEnd,
  }) {
    final rendered = _schedule.renderJobSchedule(
      jobId: jobId,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      persist: false,
    );
    return estimateJobIncome(
      shifts: rendered.occurrences,
      jobId: jobId,
      activeRuleFor: (j, date) => _payRepo.activeRuleFor(jobId: j, date: date),
    );
  }

  // -- helpers ---------------------------------------------------------------

  static final Random _rng = Random.secure();

  /// Deterministic override id (append-only log keys on it). Random suffix
  /// guards against two edits of the same occurrence in the same millisecond.
  String newOverrideId(String occurrenceId) {
    final suffix = List.generate(6, (_) => _rng.nextInt(16).toRadixString(16)).join();
    return '${occurrenceId}_ovr_$suffix';
  }

  static String nowIso() => DateTime.now().toUtc().toIso8601String();

  /// null when [zone] is a valid IANA zone name, else an error message.
  String? validateTimezone(String zone) {
    try {
      tz.getLocation(zone);
      return null;
    } catch (_) {
      return 'Unknown timezone "$zone".';
    }
  }

  /// Local civil clock of a stored UTC instant in the occurrence's own
  /// timezone (INVARIANT-007).
  /// Hours of one occurrence computed from its RESOLVED UTC instants
  /// (INVARIANT-002 — never local-clock subtraction). DST nights come out
  /// as 7h/9h, exactly what pay later consumes.
  double workedHoursOf(ShiftOccurrence o) {
    final start = UtcInstant.parse(o.startDateTimeUtc);
    final end = UtcInstant.parse(o.endDateTimeUtc);
    return calculateDuration(utcStart: start, utcEnd: end).hours;
  }

  double sumHours(Iterable<ShiftOccurrence> occurrences) =>
      occurrences.fold(0.0, (sum, o) => sum + workedHoursOf(o));

  LocalTimeRange? localWallTime(ShiftOccurrence o) {
    try {
      final loc = tz.getLocation(o.timezone);
      final startUtc = DateTime.parse(o.startDateTimeUtc).toUtc();
      final endUtc = DateTime.parse(o.endDateTimeUtc).toUtc();
      final s = tz.TZDateTime.from(startUtc, loc);
      final e = tz.TZDateTime.from(endUtc, loc);
      return LocalTimeRange(
        date: _isoDate(s),
        start: '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}',
        end: '${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')}',
      );
    } catch (_) {
      return null;
    }
  }

  String _isoDate(tz.TZDateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // -- jobs ------------------------------------------------------------------

  List<JobRecord> jobs() => _patterns.allJobs();

  /// Creates the job if its deterministic id is unknown; returns the id.
  /// Validates the timezone first (never stores garbage — the engine would
  /// report INVALID_TIMEZONE later, but a wrong zone is a data error).
  String createJob({required String name, required String timezone}) {
    final tzError = validateTimezone(timezone);
    if (tzError != null) {
      throw ArgumentError(tzError);
    }
    if (name.trim().isEmpty) {
      throw ArgumentError('Job name must not be empty.');
    }
    final id = slugId('job', [name, timezone]);
    _patterns.ensureJob(id: id, name: name.trim(), defaultTimezone: timezone);
    return id;
  }

  // -- templates -------------------------------------------------------------

  void saveTemplate({required String jobId, required ShiftTemplate template}) {
    _patterns.saveTemplate(jobId: jobId, t: template);
  }

  List<ShiftTemplate> templates(String jobId) => _patterns.templatesForJob(jobId);

  // -- patterns --------------------------------------------------------------

  List<ShiftPattern> patterns(String jobId) => _patterns.patternsForJob(jobId);

  // -- import (M2 — Smart Paste + Review + commit seam) ---------------------

  List<TemplateSpec> jobTemplateSpecs(String jobId) => templates(jobId)
      .map((t) => TemplateSpec(
          id: t.id, name: t.name, startTime: t.startTime, endTime: t.endTime))
      .toList();

  /// Parse pasted roster text through the import engine (pure).
  ImportSession parsePaste({
    required String jobId,
    required String rawText,
    required String referenceDate,
    String? id,
  }) {
    return parseDocument(
      sourceType: ImportSourceType.pasteText,
      rawText: rawText,
      templates: jobTemplateSpecs(jobId),
      referenceDate: referenceDate,
      timezone: _jobTimezone(jobId),
      id: id,
    );
  }

  /// RC plan §C1 — parse a CSV roster with an explicit user column mapping
  /// (logical field -> header cell). Mirrors parsePaste but pins sourceType
  /// csv so the session audit records where the roster came from. [mapping]
  /// null = engine auto-detect (header synonyms); the mapping UI passes the
  /// user's dropdown selections. Pure — nothing is persisted here.
  ImportSession parseCsv({
    required String jobId,
    required String rawCsv,
    required String referenceDate,
    Map<String, String>? columnMapping,
    String? id,
  }) {
    return parseDocument(
      sourceType: ImportSourceType.csv,
      rawCsv: rawCsv,
      columnMapping: columnMapping,
      templates: jobTemplateSpecs(jobId),
      referenceDate: referenceDate,
      timezone: _jobTimezone(jobId),
      id: id,
    );
  }

  /// RC plan §C2 — the job's CURRENT committed roster as local wall rows
  /// (RosterRow: date + start/end or OFF), read from the committed-import
  /// occurrence rows + the governing sessions' OFF dates. This is the "old"
  /// side of the re-import diff. [from]/[to] should be the NEW roster's date
  /// span (min/max candidate dates) — committed days outside it cannot be
  /// compared and are simply not part of the diff.
  List<RosterRow> committedRosterRows({
    required String jobId,
    required String from,
    required String to,
  }) {
    final rows = <RosterRow>[
      for (final o in _schedule.importedOccurrencesInRange(
          jobId: jobId, from: from, to: to))
        () {
          final wall = localWallTime(o);
          return (
            date: o.shiftDate,
            start: wall?.start,
            end: wall?.end,
          );
        }(),
    ];
    final shiftDates = rows.map((r) => r.date).toSet();
    // Committed OFF dates inside the window (bounded to [from..to] — the
    // OFF-date scan walks day by day, so never feed it an unbounded range).
    for (final d in _schedule.committedOffDatesInRange(
        jobId: jobId, from: from, to: to)) {
      if (!shiftDates.contains(d)) {
        rows.add((date: d, start: null, end: null));
      }
    }
    rows.sort((a, b) => a.date.compareTo(b.date));
    return rows;
  }

  /// RC plan §C2 — income impact of replacing the committed roster inside
  /// [from..to] with [prospective] (the new roster's rows). Both legs price
  /// through the SAME per-occurrence estimator (persist:false — nothing is
  /// written for a preview). Either leg unpriceable → UNAVAILABLE + reason.
  ///
  /// P7.1 (M1, result18 code review): a row that FAILS to resolve (DST gap,
  /// ambiguous without a preference, malformed times) is never silently
  /// dropped — the whole preview returns UNAVAILABLE naming the row, so the
  /// shown "After" total can never understate real income.
  IncomeImpact estimateRosterDiffImpact({
    required String jobId,
    required String from,
    required String to,
    required List<RosterRow> prospective,
  }) {
    /// Resolves every shift row or returns the failing row + engine reason.
    /// An OFF day (null start/end) is legitimate roster content, not a
    /// failure — it contributes nothing to either income leg.
    (List<ShiftOccurrence>, String?) resolveAll(List<RosterRow> rows) {
      final tzName = _jobTimezone(jobId);
      final out = <ShiftOccurrence>[];
      for (final r in rows) {
        if (r.start == null || r.end == null) continue; // OFF day
        final res = resolveShift(
          shiftDate: r.date,
          startTime: r.start!,
          endTime: r.end!,
          timezone: tzName,
        );
        if (!res.isSuccess || res.utcStart == null || res.utcEnd == null) {
          return (
            out,
            'row ${r.date} ${r.start ?? ''}-${r.end ?? ''} ($tzName) '
                'could not be resolved: ${res.error ?? res.note}',
          );
        }
        out.add(ShiftOccurrence(
          id: 'diff-preview-${r.date}',
          patternId: '',
          shiftDate: r.date,
          templateId: '',
          startDateTimeUtc: res.utcStart!.isoString,
          endDateTimeUtc: res.utcEnd!.isoString,
          timezone: tzName,
          source: OccurrenceSource.created,
          jobId: jobId,
        ));
      }
      return (out, null);
    }

    final (currentShifts, currentError) =
        resolveAll(committedRosterRows(jobId: jobId, from: from, to: to));
    if (currentError != null) {
      return IncomeImpact.unavailable('Before: $currentError');
    }
    final before = estimateJobIncome(
      shifts: currentShifts,
      jobId: jobId,
      activeRuleFor: (j, date) => _payRepo.activeRuleFor(jobId: j, date: date),
    );
    if (!before.available) {
      return IncomeImpact.unavailable('Before: ${before.unavailableReason}');
    }
    final (prospectiveShifts, prospectiveError) = resolveAll(prospective);
    if (prospectiveError != null) {
      return IncomeImpact.unavailable('After: $prospectiveError');
    }
    final after = estimateJobIncome(
      shifts: prospectiveShifts,
      jobId: jobId,
      activeRuleFor: (j, date) => _payRepo.activeRuleFor(jobId: j, date: date),
    );
    if (!after.available) {
      return IncomeImpact.unavailable('After: ${after.unavailableReason}');
    }
    return IncomeImpact(
      available: true,
      before: before.total,
      after: after.total,
      delta: after.total - before.total,
    );
  }

  /// Persist any session state (parse result, review progress, commit) — the
  /// audit trail that makes "why is Sep 03 a Night shift?" answerable.
  void persistImportSession(ImportSession session, {required String jobId}) {
    _importRepo.saveSession(session, jobId: jobId);
  }

  /// Run the engine commit (atomic) and, on success, feed the approved roster
  /// into the job's calendar (plan7 D-M2-1, option A): persist the committed
  /// session (jobId + OFF dates), then REPLACE this job's committed-import
  /// rows inside the roster window with the resolved shifts. Rendering later
  /// shows the roster as authoritative and suppresses pattern days it covers.
  /// Returns the engine result — when [CommitResult.error] != null nothing
  /// was written (fail-atomic).
  CommitResult commitRoster({
    required ImportSession session,
    required String jobId,
  }) {
    final engineResult = commitImport(session);
    if (engineResult.error != null) {
      // Nothing persisted on engine failure (the engine already left the
      // session in error state). Save that state so the audit trail +
      // screen refresh show the reason — but occurrences are NEVER written.
      _importRepo.saveSession(engineResult.session, jobId: jobId);
      return engineResult;
    }

    final dates = {
      for (final s in engineResult.shifts) s.shiftDate,
      ...engineResult.committedOffDates,
    };
    final rows = engineResult.shifts
        .map((s) => ShiftOccurrence(
              id: s.occurrenceId,
              patternId: '',
              shiftDate: s.shiftDate,
              // templateId '' = imported line matched no job template;
              // rendered as a plain chip until the user assigns one when
              // editing (plan7 D-M2-2).
              templateId: s.templateId ?? '',
              startDateTimeUtc: s.startDateTimeUtc,
              endDateTimeUtc: s.endDateTimeUtc,
              timezone: s.timezone,
              source: OccurrenceSource.created,
              jobId: jobId,
              isImported: true,
            ))
        .toList();

    // Atomic commit: session + occurrences in ONE transaction. Fail either
    // step and the whole commit rolls back — sessions are never COMMITTED
    // without their occurrences (or vice-versa).
    final datesList = dates.toList()..sort();
    // The import window is set at commit time (Gate A §A3): it covers the
    // FULL range of committed dates — shifts + OFF days — not just the
    // approved subset. The engine already produced a committed session; we
    // extend it with the window here and persist it in the SAME transaction
    // as the occurrences so the two writes are atomic.
    final sessionWithWindow = engineResult.session.copyWith(
      state: ImportState.committed,
      windowStart: datesList.isEmpty
          ? engineResult.session.referenceDate
          : datesList.first,
      windowEnd: datesList.isEmpty
          ? engineResult.session.referenceDate
          : datesList.last,
    );
    _db.execute('BEGIN');
    try {
      _importRepo.saveSession(sessionWithWindow, jobId: jobId);
      _schedule.replaceImportedOccurrencesInTransaction(
        jobId: jobId,
        from: datesList.isEmpty
            ? sessionWithWindow.referenceDate
            : datesList.first,
        to: datesList.isEmpty
            ? sessionWithWindow.referenceDate
            : datesList.last,
        rows: rows,
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return CommitResult(
      session: sessionWithWindow,
      shifts: engineResult.shifts,
      committedOffDates: engineResult.committedOffDates,
    );
  }

  String _jobTimezone(String jobId) =>
      _patterns.jobById(jobId)?.defaultTimezone ?? 'UTC';

  /// Brand-new pattern for a job (no version history). Persists templates
  /// eagerly (a missing template must surface as an issue, never be
  /// unreferenceable later).
  void saveNewPattern({
    required ShiftPattern pattern,
    List<ShiftTemplate> templates = const [],
  }) {
    _patterns.savePattern(jobId: pattern.jobId, pattern: pattern, templates: templates);
  }

  /// Roster change from a date (plan3 D1/D9 flow): closes the current active
  /// version and persists the engine-built new version (anchorDate carries
  /// over — phase continuity). The old pattern row is refreshed (effectiveUntil
  /// set); the new version is a NEW row (distinct id, per-engine).
  ///
  /// Gate C (A2 / D-C2): BOTH writes happen inside ONE DB transaction — close
  /// old + insert new. If the second write fails the whole change rolls back:
  /// the old version is NOT left closed with no successor (a half-applied
  /// roster change = lost schedule). Never opens a nested BEGIN (the
  /// repository's savePatternInTransaction issues no transaction of its own).
  ShiftPattern changeRosterFrom({
    required ShiftPattern current,
    required String newEffectiveFrom,
    required String newName,
    required int newCycleLengthDays,
    required List<String?> newSequence,
    List<ShiftTemplate> templates = const [],
  }) {
    final (closed, next) = createNewVersion(
      currentPattern: current,
      newEffectiveFrom: newEffectiveFrom,
      newName: newName,
      newCycleLengthDays: newCycleLengthDays,
      newSequence: newSequence,
    );
    _db.execute('BEGIN');
    try {
      _patterns.savePatternInTransaction(
          jobId: closed.jobId, pattern: closed, templates: const []);
      _patterns.savePatternInTransaction(
          jobId: next.jobId, pattern: next, templates: templates);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return next;
  }

  // -- render ----------------------------------------------------------------

  ScheduleRenderResult renderJob({
    required String jobId,
    required String rangeStart,
    required String rangeEnd,
    bool persist = true,
  }) {
    return _schedule.renderJobSchedule(
      jobId: jobId,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      persist: persist,
    );
  }

  // -- overrides -------------------------------------------------------------

  /// Persist an override and re-render so the persisted occurrence rows match
  /// the effective schedule. [patternId] is REQUIRED for CREATE (official
  /// convention — the repo throws when missing); ignored for other ops.
  void applyOverride(
    Override override, {
    required String jobId,
    String? patternId,
  }) {
    _schedule.saveOverride(override, patternId: patternId);
  }

  // -- backup / restore (RC plan §F) -----------------------------------------

  /// Full-data backup document (schema version + checksum + every table).
  /// ICS export is NOT a backup (F3) — this is the data-safety path.
  Map<String, dynamic> createBackup() => backup_mod.createBackup(_db);

  /// Validate a backup document without touching the database — the preview
  /// step of the restore flow (F2: validate → preview → confirm → restore).
  /// Throws [BackupException] with the specific reason.
  Map<String, int> previewBackup(String raw) {
    final doc = backup_mod.parseAndValidateBackup(raw);
    return backup_mod.backupPreviewCounts(doc);
  }

  /// Transactional restore (F2). Returns null on success or a user-facing
  /// error (corrupted file / newer schema / mid-restore failure — the old
  /// data stays intact in every failure case).
  String? restoreBackupFrom(String raw) {
    final result = backup_mod.restoreBackup(
      _db,
      raw,
      currentSchemaVersion: schemaVersion,
    );
    return result.success ? null : result.error;
  }

  /// RC plan §H — delete ALL app data (jobs, schedules, overrides, pay
  /// rules, imports) in ONE transaction. The schema itself is kept
  /// (user_version untouched) so the app keeps working immediately after.
  /// A backup made before this is the only recovery path — the Settings
  /// screen must confirm twice before calling this.
  void deleteAllData() {
    _db.execute('BEGIN');
    try {
      // Children before parents (FK constraints are ON).
      for (final t in backup_mod.backupTables.reversed) {
        _db.execute('DELETE FROM $t');
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// RC plan §H — the encryption status probe for the Settings screen
  /// (§G honesty contract): null = the database IS encrypted and the key
  /// verifies; non-null = the human-readable reason it is NOT.
  String? encryptionStatusReason() =>
      security_gate.verifyEncryption(_db, expectedKeyHex: _encryptionKeyHex);
}
