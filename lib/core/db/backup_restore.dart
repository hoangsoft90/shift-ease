// =============================================================================
// RC plan §F — Backup / Restore (plan2 §6.1 local-first data safety).
//
// A backup is a JSON document carrying a schema/version header, a checksum
// over the payload, and EVERY table the app owns (jobs, templates, patterns
// + sequence, occurrences, overrides, pay rules + children, import sessions
// + candidates). ICS export is NOT a backup (F3) — this is the full-data path.
//
// Restore is FAIL-SAFE by construction:
//   1. validate format/schema version/checksum BEFORE touching the DB;
//   2. build the whole restore inside ONE transaction: drop + re-insert +
//     bump user_version — a failure anywhere ROLLS BACK to the intact old
//     database (F2: "restore fail → database cũ nguyên vẹn");
//   3. verify by row counts afterwards (cheap integrity probe).
//
// The format is deliberately plain JSON (no encryption here — the ENCRYPTED
// backup layer is §G and lands with the real SQLCipher integration; the
// schema reserves an `encryption` header field for it).
// =============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

/// Backup format version this build writes/understands.
const int backupFormatVersion = 1;

/// Tables copied by a full backup, in restore order (parents first).
const List<String> backupTables = [
  'jobs',
  'shift_templates',
  'shift_patterns',
  'pattern_sequence',
  'occurrences',
  'overrides',
  'pay_rules',
  'pay_differentials',
  'pay_overtime_rules',
  'import_sessions',
  'import_candidates',
];

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => 'BackupException: $message';
}

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

/// Build a full backup document of [db].
Map<String, dynamic> createBackup(Database db) {
  final payload = <String, dynamic>{
    'format': 'shiftease-backup',
    'schemaVersion': db.select('PRAGMA user_version').first.columnAt(0),
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'encryption': 'none', // §G upgrades this to the real cipher label
    'tables': {
      for (final t in backupTables)
        t: [
          for (final r in db.select('SELECT * FROM $t'))
            {for (final k in r.keys) k: r[k]},
        ],
    },
  };
  return {
    ...payload,
    'checksum': _checksum(jsonEncode(payload['tables'])),
  };
}

/// Canonical SHA-256-style checksum. crypto is not a dependency (project rule:
/// no extra deps in the RC batch), so this is a deterministic FNV-1a 64-bit
/// hash over the payload — enough to catch corruption/truncation/edits of a
/// hand-modified file, which is exactly what the checksum is FOR. It is NOT a
/// security primitive (that is §G's encrypted backup).
String _checksum(String input) {
  var hash = 0xcbf29ce484222325;
  for (final unit in utf8.encode(input)) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String checksumOfPayload(Map<String, dynamic> tables) =>
    _checksum(jsonEncode(tables));

/// Serialize to the on-disk / shareable string form.
String serializeBackup(Map<String, dynamic> backup) =>
    const JsonEncoder.withIndent('  ').convert(backup);

/// Parse + VALIDATE a backup document (format, schema version, checksum).
/// Throws [BackupException] with the specific reason — restore never proceeds
/// on an unvalidated file (F2).
Map<String, dynamic> parseAndValidateBackup(String raw) {
  Map<String, dynamic> doc;
  try {
    doc = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    throw const BackupException('Not a valid backup file (JSON parse failed).');
  }
  if (doc['format'] != 'shiftease-backup') {
    throw const BackupException(
        'Not a ShiftEase backup (missing format header).');
  }
  final version = doc['schemaVersion'];
  if (version is! int) {
    throw const BackupException('Backup has no schema version.');
  }
  if (version < 1 || version > 99) {
    throw BackupException('Unsupported backup schema version: $version.');
  }
  final tables = doc['tables'];
  if (tables is! Map<String, dynamic>) {
    throw const BackupException('Backup carries no table data.');
  }
  final checksum = doc['checksum'];
  if (checksum is! String ||
      checksum != checksumOfPayload(tables.cast<String, dynamic>())) {
    throw const BackupException(
        'Backup is corrupted (checksum mismatch) — refusing to restore.');
  }
  return doc;
}

/// Human preview for the confirm dialog (F2): what the restore will bring.
Map<String, int> backupPreviewCounts(Map<String, dynamic> backup) => {
      for (final t in backupTables)
        t: ((backup['tables'] as Map<String, dynamic>)[t] as List?)?.length ?? 0,
    };

// ---------------------------------------------------------------------------
// Restore
// ---------------------------------------------------------------------------

class RestoreResult {
  final bool success;
  final String? error;
  final Map<String, int> rowCounts; // post-restore verification probe

  const RestoreResult({required this.success, this.error, this.rowCounts = const {}});
}

/// Restore [raw] into [db] transactionally. The WHOLE restore — drop rows,
/// re-insert, bump user_version — happens inside ONE transaction; any failure
/// rolls back leaving the pre-restore database intact. The backup is validated
/// BEFORE the transaction opens. [currentSchemaVersion] is the schema the app
/// code understands; a backup of an older schema restores to that version and
/// [migrate] must be re-run by the caller (openDatabase does this naturally).
RestoreResult restoreBackup(
  Database db,
  String raw, {
  required int currentSchemaVersion,
}) {
  final Map<String, dynamic> backup;
  try {
    backup = parseAndValidateBackup(raw);
  } on BackupException catch (e) {
    // Validation failure is a RESULT, not a crash: the caller (UI) shows the
    // reason and the database is untouched — exactly F2's contract.
    return RestoreResult(success: false, error: e.message);
  }
  final tables = (backup['tables'] as Map<String, dynamic>)
      .cast<String, List<dynamic>?>();
  final backupSchema = backup['schemaVersion'] as int;
  if (backupSchema > currentSchemaVersion) {
    return RestoreResult(
      success: false,
      error:
          'Backup was created by a NEWER app version (schema $backupSchema > '
          '$currentSchemaVersion). Update the app first.',
    );
  }

  db.execute('BEGIN');
  try {
    // Order matters: children before parents (FK constraints are ON).
    for (final t in backupTables.reversed) {
      db.execute('DELETE FROM $t');
    }
    for (final t in backupTables) {
      final rows = tables[t] ?? const [];
      for (final row in rows) {
        final map = (row as Map).cast<String, dynamic>();
        final cols = map.keys.toList();
        final placeholders = List.filled(cols.length, '?').join(',');
        final colList = cols.join(', ');
        db.execute(
          'INSERT INTO $t ($colList) VALUES ($placeholders)',
          [for (final c in cols) map[c]],
        );
      }
    }
    // The restored DB is exactly the backup's schema.
    db.execute('PRAGMA user_version = $backupSchema');
    db.execute('COMMIT');
  } catch (e) {
    db.execute('ROLLBACK');
    return RestoreResult(
      success: false,
      // F2 — the old database is intact; surface why, never half-restore.
      error: 'Restore failed — your data was NOT changed. (${e.runtimeType})',
    );
  }

  // Post-restore verification probe (F2 "Verify" step): every backed-up table
  // must now carry exactly the backup's row count.
  final counts = <String, int>{};
  for (final t in backupTables) {
    final expected = tables[t]?.length ?? 0;
    final actual =
        db.select('SELECT COUNT(*) c FROM $t').first['c'] as int;
    if (actual != expected) {
      // Not expected to happen inside a committed transaction — but the
      // verify step exists to catch exactly the impossible-until-it-isn't.
      return RestoreResult(
        success: false,
        error: 'Restore verification failed for $t '
            '($actual rows, expected $expected).',
        rowCounts: counts,
      );
    }
    counts[t] = actual;
  }
  return RestoreResult(success: true, rowCounts: counts);
}

/// Byte-typed convenience for platform pickers (file_selector returns bytes).
RestoreResult restoreBackupBytes(
  Database db,
  Uint8List bytes, {
  required int currentSchemaVersion,
}) =>
    restoreBackup(
      db,
      utf8.decode(bytes, allowMalformed: false),
      currentSchemaVersion: currentSchemaVersion,
    );
