// =============================================================================
// ShiftEase Persistence — database open + schema migrations (Gate 3)
// =============================================================================
//
// INVARIANT-008 (offline-first): everything lives in a LOCAL SQLite database.
// plan2 §6.1 locks SQLCipher for on-disk encryption in production; P7.2
// (production verification, P7_fix1.md) delivers it: with
// `hooks.user_defines.sqlite3.source: sqlcipher` (pubspec.yaml) the native
// library linked into every build of this app IS SQLCipher, so `PRAGMA key`
// really encrypts and `PRAGMA cipher_version` returns a real version.
// [defaultOpener] verifies both on every keyed open and REFUSES to return a
// usable connection otherwise — there is NO silent fallback to plain SQLite.
// Tests without a key keep running plain SQLite through the same seam.
//
// Migrations are tracked with PRAGMA user_version. Version 1 creates every
// table for entities that already have a domain model in lib/core/ (plan4
// §3-§4): jobs, templates, patterns (+sequence), occurrences, overrides
// (append-only — the past is never rewritten), pay rules (+differential /
// overtime children), import sessions (+candidates).
//
// Version 2: overrides.patternId — CREATE overrides produce an occurrence
// whose id IS the override id (not rooted to any baseline occurrence), so the
// render-time log filter cannot scope them by baseline occurrence root. The
// pattern whose schedule the CREATE edits is recorded explicitly; the render
// includes a CREATE override iff its pattern is rendered AND its payload date
// falls inside the requested range (plan4 §4 overridesFor(patternId, range)).
// =============================================================================

import 'dart:math';
import 'package:sqlite3/sqlite3.dart';

/// Schema version this build understands. Bump + add a case in [migrate] when
/// the schema changes; never edit applied migrations.
///
/// v3: import commits feed the schedule (M2, plan7 D-M2-1). Imported shift
/// rows carry `occurrences.jobId` (they have no pattern to scope by) and are
/// marked `isImported`; the import session records its owning job + committed
/// OFF dates so the render can suppress pattern days an approved roster
/// replaces. See db_test 'v3' groups.
const int schemaVersion = 3;

/// Opens a database (plain, or SQLCipher when [key] is provided and the
/// native library supports it). Injectable seam — callers pass their own
/// opener so tests can use `:memory:`.
typedef DatabaseOpener = Database Function({
  required String path,
  String? key,
});

/// Thrown by [defaultOpener] when a keyed open cannot be PROVEN to be an
/// encrypted SQLCipher database. Callers must treat this as fatal: the app
/// refuses to run on an unencrypted store rather than silently degrading to
/// plain SQLite (P7.2 — no fallback in production).
class SqlCipherUnavailableError extends Error {
  final String reason;
  SqlCipherUnavailableError(this.reason);
  @override
  String toString() =>
      'SqlCipherUnavailableError: encrypted database could not be opened ($reason)';
}

Database defaultOpener({required String path, String? key}) {
  final db = sqlite3.open(path);
  if (key != null && key.isNotEmpty) {
    // SQLCipher keying. With the build hook (pubspec.yaml `source:
    // sqlcipher`) the linked library is SQLCipher 4.x and this actually
    // encrypts. On a plain sqlite3 build the same statements would be
    // silently ignored — which is exactly what the checks below prevent.
    db.execute("PRAGMA key = '$key'");
    final cipher = _cipherVersion(db);
    if (cipher == null) {
      db.close();
      throw SqlCipherUnavailableError(
          'the linked SQLite build has no cipher support (PRAGMA '
          "cipher_version returned nothing) — refusing to open '$path' as an "
          'UNENCRYPTED database');
    }
    // P7.2 negative control: prove the file is really ciphertext, not a
    // plain database that ignored PRAGMA key. Reads of a keyed SQLCipher
    // database before keying fail with SQLITE_NOTADB; if this probe
    // somehow succeeds we are looking at an unencrypted file.
    try {
      db.select('SELECT count(*) FROM sqlite_master');
    } on SqliteException catch (e) {
      db.close();
      throw SqlCipherUnavailableError(
          'database is not readable with the provided key (wrong key or '
          'corrupt file): ${e.message}');
    }
  }
  db.execute('PRAGMA foreign_keys = ON');
  // P7.2 fail-closed rule: on THIS build (SQLCipher linked) every on-disk
  // database must be opened KEYED. An unkeyed file connection would either
  // (a) read a legacy PLAIN file as plaintext, or (b) hold a connection to
  // an encrypted file that fails on first read — both are silent-plain
  // paths the plan forbids. Ephemeral `:memory:` databases (tests only,
  // nothing on disk to protect) stay allowed unkeyed. On a hypothetical
  // plain library this check cannot fire (no cipher support to enforce).
  final isKeyed = key != null && key.isNotEmpty;
  if (!isKeyed && path != ':memory:' && _cipherVersion(db) != null) {
    db.close();
    throw SqlCipherUnavailableError(
        'an on-disk database must be opened WITH its encryption key on '
        "this SQLCipher build — refusing unkeyed open of '$path' (the file "
        'stays untouched; open it with its key or restore a backup)');
  }
  return db;
}

/// The SQLCipher version of the linked library, or null when the build has
/// no encryption support (a plain sqlite3 answers the pragma with an EMPTY
/// result set — no error, no row).
String? _cipherVersion(Database db) {
  try {
    final rows = db.select('PRAGMA cipher_version');
    if (rows.isEmpty) return null;
    final v = rows.first.columnAt(0)?.toString();
    return (v == null || v.isEmpty) ? null : v;
  } catch (_) {
    return null;
  }
}

/// True when the linked sqlite3 native library is a real SQLCipher build.
/// Exported for [verifyEncryption] (security_gate.dart) and tests.
bool supportsSqlCipher(Database db) => _cipherVersion(db) != null;

/// Opens (creating if needed) and migrates the database to [schemaVersion].
Database openDatabase({
  required DatabaseOpener opener,
  required String path,
  String? key,
}) {
  final db = opener(path: path, key: key);
  migrate(db);
  return db;
}

/// Applies pending migrations. Never re-runs an applied version (idempotent
/// by construction — each case only runs when user_version is lower).
void migrate(Database db) {
  final current = db.select('PRAGMA user_version').first.columnAt(0) as int;
  if (current < 1) {
    db.execute('BEGIN');
    try {
      for (final ddl in v1Ddl) {
        db.execute(ddl);
      }
      db.execute('PRAGMA user_version = 1');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
  if (current < 2) {
    // v2: scope CREATE overrides to the pattern whose schedule they edit.
    db.execute('BEGIN');
    try {
      db.execute('ALTER TABLE overrides ADD COLUMN patternId TEXT');
      db.execute('PRAGMA user_version = 2');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
  if (current < 3) {
    // v3 (M2 import-commit seam): imported schedule rows + session owner/OFFs.
    db.execute('BEGIN');
    try {
      db.execute('ALTER TABLE occurrences ADD COLUMN jobId TEXT');
      db.execute(
          "ALTER TABLE occurrences ADD COLUMN isImported INTEGER NOT NULL DEFAULT 0");
      for (final alter in [
        'ALTER TABLE import_sessions ADD COLUMN jobId TEXT',
        'ALTER TABLE import_sessions ADD COLUMN committedOffDatesJson TEXT',
        'ALTER TABLE import_sessions ADD COLUMN windowStart TEXT',
        'ALTER TABLE import_sessions ADD COLUMN windowEnd TEXT',
      ]) {
        try {
          db.execute(alter);
        } catch (_) {}
      }
      db.execute('PRAGMA user_version = 3');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}

/// v1 DDL statements (exported for the upgrade-path test; production code
/// uses them only through [migrate]).
const List<String> v1Ddl = [
  '''CREATE TABLE jobs (
    uuid TEXT PRIMARY KEY,
    id TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    defaultTimezone TEXT NOT NULL
  )''',
  '''CREATE TABLE shift_templates (
    uuid TEXT PRIMARY KEY,
    id TEXT NOT NULL UNIQUE,
    jobUuid TEXT NOT NULL REFERENCES jobs(uuid),
    name TEXT NOT NULL,
    code TEXT NOT NULL,
    color TEXT NOT NULL,
    startTime TEXT NOT NULL,
    endTime TEXT NOT NULL,
    breakDurationMinutes INTEGER NOT NULL DEFAULT 0
  )''',
  '''CREATE TABLE shift_patterns (
    uuid TEXT PRIMARY KEY,
    id TEXT NOT NULL UNIQUE,
    jobUuid TEXT NOT NULL REFERENCES jobs(uuid),
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    cycleLengthDays INTEGER NOT NULL,
    anchorDate TEXT NOT NULL,
    defaultTimezone TEXT NOT NULL,
    effectiveFrom TEXT NOT NULL,
    effectiveUntil TEXT
  )''',
  '''CREATE TABLE pattern_sequence (
    uuid TEXT PRIMARY KEY,
    patternUuid TEXT NOT NULL REFERENCES shift_patterns(uuid)
      ON DELETE CASCADE,
    positionIdx INTEGER NOT NULL,
    templateId TEXT,
    UNIQUE(patternUuid, positionIdx)
  )''',
  '''CREATE TABLE occurrences (
    uuid TEXT PRIMARY KEY,
    id TEXT NOT NULL UNIQUE,
    patternId TEXT NOT NULL,
    shiftDate TEXT NOT NULL,
    templateId TEXT,
    startDateTimeUtc TEXT NOT NULL,
    endDateTimeUtc TEXT NOT NULL,
    timezone TEXT NOT NULL,
    source TEXT NOT NULL,
    sourceOverrideId TEXT,
    actualPayEstimate REAL,
    payEstimateFrom TEXT,
    committedAt TEXT
  )''',
  '''CREATE TABLE overrides (
    uuid TEXT PRIMARY KEY,
    id TEXT NOT NULL UNIQUE,
    occurrenceId TEXT NOT NULL,
    operation TEXT NOT NULL,
    payloadJson TEXT NOT NULL,
    swapWithOccurrenceId TEXT,
    createdAt TEXT NOT NULL,
    reason TEXT,
    appliedToRangeStart TEXT
  )''',
  '''CREATE TABLE pay_rules (
    uuid TEXT PRIMARY KEY,
    id TEXT NOT NULL UNIQUE,
    jobUuid TEXT NOT NULL REFERENCES jobs(uuid),
    baseHourlyRate REAL NOT NULL,
    effectiveFrom TEXT NOT NULL,
    effectiveUntil TEXT
  )''',
  '''CREATE TABLE pay_differentials (
    uuid TEXT PRIMARY KEY,
    payRuleUuid TEXT NOT NULL REFERENCES pay_rules(uuid)
      ON DELETE CASCADE,
    type TEXT NOT NULL,
    mode TEXT NOT NULL,
    value REAL NOT NULL,
    scope TEXT NOT NULL,
    windowStartLocal TEXT,
    windowEndLocal TEXT
  )''',
  '''CREATE TABLE pay_overtime_rules (
    uuid TEXT PRIMARY KEY,
    payRuleUuid TEXT NOT NULL REFERENCES pay_rules(uuid)
      ON DELETE CASCADE,
    thresholdHours REAL NOT NULL,
    period TEXT NOT NULL,
    multiplier REAL NOT NULL
  )''',
  '''CREATE TABLE import_sessions (
    uuid TEXT PRIMARY KEY,
    id TEXT NOT NULL UNIQUE,
    sourceType TEXT NOT NULL,
    state TEXT NOT NULL,
    referenceDate TEXT NOT NULL,
    timezone TEXT NOT NULL,
    createdAt TEXT NOT NULL,
    rawExtractionJson TEXT NOT NULL,
    committedIdsJson TEXT NOT NULL,
    historyJson TEXT NOT NULL,
    jobId TEXT,
    committedOffDatesJson TEXT,
    windowStart TEXT,
    windowEnd TEXT
  )''',
  '''CREATE TABLE import_candidates (
    uuid TEXT PRIMARY KEY,
    sessionUuid TEXT NOT NULL REFERENCES import_sessions(uuid)
      ON DELETE CASCADE,
    id TEXT NOT NULL,
    date TEXT,
    templateId TEXT,
    startTime TEXT,
    endTime TEXT,
    shiftType TEXT,
    kind TEXT,
    confidence TEXT NOT NULL,
    reviewStatus TEXT NOT NULL,
    note TEXT,
    UNIQUE(sessionUuid, id)
  )''',
  'CREATE INDEX idx_occurrences_range ON occurrences(patternId, shiftDate)',
  'CREATE INDEX idx_overrides_occ ON overrides(occurrenceId)',
  'CREATE INDEX idx_payrules_job ON pay_rules(jobUuid, effectiveFrom)',
];

/// Convenience: an in-memory database for tests.
Database openInMemory() => openDatabase(
      opener: defaultOpener,
      path: ':memory:',
    );

/// Generate a random UUID string (hex, 32 chars). Used by persistence layers
/// for row-level DB keys so deterministic engine ids (the public contract)
/// never collide across re-imports / restarts.
String newUuid() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
