// =============================================================================
// PatternRepository — jobs, shift templates, shift patterns (+sequence)
// =============================================================================
//
// Maps core/pattern objects to/from SQLite rows. UUIDs are generated here and
// never leak into the core deterministic ids (plan4 §3). Writes are
// transactional; reads return fresh core objects (immutable, INVARIANT-001).
// =============================================================================

import 'dart:math';
import 'package:sqlite3/sqlite3.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';

/// Cryptographically-secure hex uuid (32 chars) — deterministic engine ids
/// stay the app-facing contract; the DB key never collides across re-imports.
String newUuid() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class JobRecord {
  final String id;
  final String name;
  final String defaultTimezone;

  const JobRecord({
    required this.id,
    required this.name,
    required this.defaultTimezone,
  });
}

class PatternRepository {
  final Database db;

  PatternRepository(this.db);

  /// Inserts the job if unknown; returns its uuid. Idempotent.
  String ensureJob({
    required String id,
    required String name,
    required String defaultTimezone,
  }) {
    final existing = db.select(
        'SELECT uuid FROM jobs WHERE id = ?', [id]);
    if (existing.isNotEmpty) return existing.first['uuid'] as String;
    final uuid = newUuid();
    db.execute(
      'INSERT INTO jobs (uuid, id, name, defaultTimezone) VALUES (?, ?, ?, ?)',
      [uuid, id, name, defaultTimezone],
    );
    return uuid;
  }

  JobRecord? jobById(String id) {
    final rows = db.select('SELECT * FROM jobs WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return JobRecord(
      id: rows.first['id'] as String,
      name: rows.first['name'] as String,
      defaultTimezone: rows.first['defaultTimezone'] as String,
    );
  }

  /// All jobs, ordered by name. Read-only — used by the UI job list.
  List<JobRecord> allJobs() {
    final rows = db.select('SELECT * FROM jobs ORDER BY name, id');
    return rows
        .map((r) => JobRecord(
              id: r['id'] as String,
              name: r['name'] as String,
              defaultTimezone: r['defaultTimezone'] as String,
            ))
        .toList();
  }

  /// Save a template for a job (idempotent by deterministic id — later saves
  /// refresh the row rather than duplicate).
  void saveTemplate({required String jobId, required ShiftTemplate t}) {
    final jobUuid = ensureJob(
      id: jobId,
      name: t.name,
      defaultTimezone: 'UTC',
    );
    db.execute(
      '''INSERT INTO shift_templates
         (uuid, id, jobUuid, name, code, color, startTime, endTime,
          breakDurationMinutes)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         jobUuid = excluded.jobUuid,
         name = excluded.name,
         code = excluded.code,
         color = excluded.color,
         startTime = excluded.startTime,
         endTime = excluded.endTime,
         breakDurationMinutes = excluded.breakDurationMinutes''',
      [newUuid(), t.id, jobUuid, t.name, t.code, t.color, t.startTime,
        t.endTime, t.breakDurationMinutes],
    );
  }

  List<ShiftTemplate> templatesForJob(String jobId) {
    final rows = db.select(
      'SELECT st.* FROM shift_templates st '
      'JOIN jobs j ON j.uuid = st.jobUuid WHERE j.id = ? ORDER BY st.id',
      [jobId],
    );
    return rows.map((r) {
      return ShiftTemplate(
        id: r['id'] as String,
        jobId: jobId,
        name: r['name'] as String,
        code: r['code'] as String,
        color: r['color'] as String,
        startTime: r['startTime'] as String,
        endTime: r['endTime'] as String,
        breakDurationMinutes: r['breakDurationMinutes'] as int,
      );
    }).toList();
  }

  /// Save a pattern (all versions of one id live as separate rows sharing the
  /// deterministic id via ON CONFLICT) with its sequence replaced atomically.
  /// Own-transaction flavour — opens its own BEGIN/COMMIT. Use when NOT
  /// already inside a caller-owned transaction.
  void savePattern({
    required String jobId,
    required ShiftPattern pattern,
    List<ShiftTemplate> templates = const [],
  }) {
    db.execute('BEGIN');
    try {
      _savePatternNoTxn(
          jobId: jobId, pattern: pattern, templates: templates);
      db.execute('COMMIT');
    } catch (_) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  /// Same write as [savePattern] but WITHOUT its own BEGIN/COMMIT — the
  /// CALLER owns the surrounding transaction (Gate C A2: changeRosterFrom
  /// closes the old version and inserts the new one in ONE transaction, so a
  /// failure in the second write rolls the first back too — never a roster
  /// left half-closed). Never open a BEGIN here.
  void savePatternInTransaction({
    required String jobId,
    required ShiftPattern pattern,
    List<ShiftTemplate> templates = const [],
  }) {
    _savePatternNoTxn(jobId: jobId, pattern: pattern, templates: templates);
  }

  void _savePatternNoTxn({
    required String jobId,
    required ShiftPattern pattern,
    List<ShiftTemplate> templates = const [],
  }) {
    final jobUuid = ensureJob(
      id: jobId,
      name: pattern.name,
      defaultTimezone: pattern.defaultTimezone,
    );
    // Version immutability at the persistence boundary (Gate A §A6): a NEW
    // version MUST carry a new id. Re-saving an existing [pattern.id] is
    // allowed in exactly two cases: (1) identical payload (idempotent
    // no-op), or (2) the D9 CLOSE operation — the caller re-persists the
    // same version with only effectiveUntil newly set (null → date), which
    // is how changeRosterFrom ends the previous version (pattern_engine
    // createNewVersion keeps the old id on the closed copy). Anything else
    // that differs throws — silent overwrite is forbidden.
    final existingRows = db.select(
        'SELECT uuid, name, type, cycleLengthDays, anchorDate, '
        'effectiveFrom, effectiveUntil, defaultTimezone '
        'FROM shift_patterns WHERE id = ?', [pattern.id]);
    String patternUuid;
    if (existingRows.isEmpty) {
      patternUuid = newUuid();
    } else {
      final e = existingRows.first;
      // Sequence is part of the version payload — compare it too, so a
      // same-id re-save cannot silently swap a version's roster content.
      final existingSeq = db
          .select('SELECT templateId FROM pattern_sequence '
              'WHERE patternUuid = ? ORDER BY positionIdx', [e['uuid']])
          .map((s) => s['templateId'] as String?)
          .toList();
      bool sameSeq = existingSeq.length == pattern.sequence.length;
      if (sameSeq) {
        for (var i = 0; i < pattern.sequence.length; i++) {
          if (existingSeq[i] != pattern.sequence[i]) {
            sameSeq = false;
            break;
          }
        }
      }
      final coreDiffers = e['name'] != pattern.name ||
          e['type'] != pattern.type ||
          e['cycleLengthDays'] != pattern.cycleLengthDays ||
          e['anchorDate'] != pattern.anchorDate ||
          e['effectiveFrom'] != pattern.effectiveFrom ||
          e['defaultTimezone'] != pattern.defaultTimezone ||
          !sameSeq;
      if (coreDiffers) {
        throw StateError(
            'ShiftPattern ${pattern.id} already exists with a DIFFERENT '
            'payload; refusing to silently overwrite (Gate A §A6: version '
            'immutability at the persistence boundary). Use a new id for the '
            'new version — convention enforced by PatternRepository.');
      }
      patternUuid = e['uuid'] as String;
      // Effective-window mutation is allowed EXACTLY once and in one
      // direction only: closing an OPEN version (existing null → a date) —
      // the D9 flow (changeRosterFrom). An identical re-save keeps the same
      // effectiveUntil. Re-opening a closed version or re-closing it at a
      // different date would silently rewrite history — refuse loudly.
      final existingUntil = e['effectiveUntil'] as String?;
      if (existingUntil != null &&
          existingUntil != pattern.effectiveUntil) {
        throw StateError(
            'ShiftPattern ${pattern.id} is already closed at '
            '$existingUntil; refusing to re-open or re-close it (Gate A '
            '§A6). Create a new version instead.');
      }
      if (existingUntil != pattern.effectiveUntil) {
        db.execute('UPDATE shift_patterns SET effectiveUntil = ? '
            'WHERE uuid = ?', [pattern.effectiveUntil, patternUuid]);
      }
    }
    db.execute(
      '''INSERT INTO shift_patterns
         (uuid, id, jobUuid, name, type, cycleLengthDays, anchorDate,
          defaultTimezone, effectiveFrom, effectiveUntil)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO NOTHING''',
      [
        patternUuid, pattern.id, jobUuid, pattern.name, pattern.type,
        pattern.cycleLengthDays, pattern.anchorDate,
        pattern.defaultTimezone, pattern.effectiveFrom,
        pattern.effectiveUntil,
      ],
    );
    // Replace the sequence rows for this pattern version.
    db.execute('DELETE FROM pattern_sequence WHERE patternUuid = ?',
        [patternUuid]);
    for (var i = 0; i < pattern.sequence.length; i++) {
      db.execute(
        'INSERT INTO pattern_sequence '
        '(uuid, patternUuid, positionIdx, templateId) VALUES (?, ?, ?, ?)',
        [newUuid(), patternUuid, i, pattern.sequence[i]],
      );
    }
    // Referenced templates are persisted eagerly so a schedule render can
    // always resolve them (missing templates must surface, never silently).
    for (final t in templates) {
      saveTemplate(jobId: jobId, t: t);
    }
  }

  /// Versions whose effective window overlaps [from..to], ordered by
  /// effectiveFrom (oldest first — version segments apply in order).
  List<ShiftPattern> patternsOverlapping({
    required String jobId,
    required String from,
    required String to,
  }) {
    final rows = db.select(
      '''SELECT sp.* FROM shift_patterns sp
         JOIN jobs j ON j.uuid = sp.jobUuid
         WHERE j.id = ?
           AND sp.effectiveFrom <= ?
           AND (sp.effectiveUntil IS NULL OR sp.effectiveUntil >= ?)
         ORDER BY sp.effectiveFrom, sp.id''',
      [jobId, to, from],
    );
    return rows.map((r) => _patternFromRow(r, jobId)).toList();
  }

  /// All versions of a pattern that are active on [date], newest first.
  List<ShiftPattern> patternsActiveOn({required String jobId, required String date}) {
    final rows = db.select(
      '''SELECT sp.* FROM shift_patterns sp
         JOIN jobs j ON j.uuid = sp.jobUuid
         WHERE j.id = ?
           AND sp.effectiveFrom <= ?
           AND (sp.effectiveUntil IS NULL OR sp.effectiveUntil >= ?)
         ORDER BY sp.effectiveFrom DESC''',
      [jobId, date, date],
    );
    return rows.map((r) => _patternFromRow(r, jobId)).toList();
  }

  List<ShiftPattern> patternsForJob(String jobId) {
    final rows = db.select(
      'SELECT sp.* FROM shift_patterns sp JOIN jobs j ON j.uuid = sp.jobUuid '
      'WHERE j.id = ? ORDER BY sp.id, sp.effectiveFrom',
      [jobId],
    );
    return rows.map((r) => _patternFromRow(r, jobId)).toList();
  }

  ShiftPattern _patternFromRow(Row r, String jobId) {
    final seqRows = db.select(
      'SELECT templateId FROM pattern_sequence WHERE patternUuid = ? '
      'ORDER BY positionIdx',
      [r['uuid']],
    );
    return ShiftPattern(
      id: r['id'] as String,
      jobId: jobId,
      name: r['name'] as String,
      type: r['type'] as String,
      cycleLengthDays: r['cycleLengthDays'] as int,
      sequence: seqRows
          .map((s) => s['templateId'] as String?)
          .toList(growable: false),
      anchorDate: r['anchorDate'] as String,
      defaultTimezone: r['defaultTimezone'] as String,
      effectiveFrom: r['effectiveFrom'] as String,
      effectiveUntil: r['effectiveUntil'] as String?,
    );
  }
}
