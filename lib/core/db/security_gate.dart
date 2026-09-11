// =============================================================================
// RC plan §G — local security gate (SQLCipher + secure key storage).
//
// Honesty contract (the plan is explicit): `sqlite3.open() + PRAGMA key` on a
// PLAIN sqlite3 build is NOT SQLCipher encryption. This module therefore
// exposes:
//
//   1. [generateEncryptionKey] — a fresh 64-char hex key from a secure RNG
//      (32 random bytes). Never hardcoded, generated once per install.
//   2. [SecretStore] — the key-storage seam. Production must use platform
//      secure storage (Android Keystore / iOS Keychain); the bound
//      implementation here is the in-memory test double. Wiring the real
//      platform stores is a DEVICE-verified step (Android/iOS) — this batch
//      ships the structure + the honest status report, not a fake encryption.
//   3. [verifyEncryption] — the probe the Settings screen calls: it checks
//      for a live SQLCipher `cipher_version` PRAGMA. On the plain-sqlite3
//      build (this sandbox / tests) it reports NOT encrypted loudly — never a
//      silent "yes I am secure".
//
// Everything in this file is deterministic and UI-free (core/).
// =============================================================================

import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

/// 32 random bytes → 64-char lowercase hex. This is the DB master key; it is
/// generated ONCE and stored via [SecretStore] — never hardcoded, never
/// logged, never written into the backup JSON (encrypted backups reuse it
/// through the store, plan §G encrypted backup).
String generateEncryptionKey() {
  final rng = Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Where the master key lives. Production binds
/// [SecureSecretStore] (features/security/) — Android Keystore / iOS
/// Keychain via flutter_secure_storage. [InMemorySecretStore] is the test
/// double ONLY.
abstract class SecretStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

/// Test double. NOT for production: a plain in-memory map never protects
/// anything after the process dies. Production uses
/// [SecureSecretStore] (P7.3/P7.4).
class InMemorySecretStore implements SecretStore {
  final Map<String, String> _map = {};
  @override
  Future<void> write(String key, String value) async => _map[key] = value;
  @override
  Future<String?> read(String key) async => _map[key];
  @override
  Future<void> delete(String key) async => _map.remove(key);
}

/// True when the linked sqlite3 native library is a real SQLCipher build
/// (a `cipher_version` pragma that returns a NON-EMPTY row). A plain sqlite3
/// build answers unknown pragmas with an empty result set — no error, no
/// version — so the check is on the returned value, not on throwing.
///
/// NOTE: cipher-capable library ≠ encrypted database. This is a capability
/// check only; use [verifyEncryption] for the honest status of a LIVE
/// connection.
bool supportsSqlCipher(Database db) {
  try {
    final rows = db.select('PRAGMA cipher_version');
    return rows.isNotEmpty &&
        rows.first.columnAt(0)?.toString().isNotEmpty == true;
  } catch (_) {
    return false;
  }
}

/// Whether a connection can read the database schema WITHOUT a key having
/// been applied. On a SQLCipher build an unkeyed connection to an encrypted
/// file fails its first real read with SQLITE_NOTADB — so if this probe
/// reads `sqlite_master` cleanly, the file is PLAIN SQLite on disk.
bool readableWithoutKey(Database db) {
  try {
    db.select('SELECT count(*) FROM sqlite_master');
    return true;
  } catch (_) {
    return false;
  }
}

/// The Settings "encryption status" probe (RC plan §G honesty contract,
/// P7.2 tightened). Returns:
///   - null ONLY when the library is SQLCipher-capable AND the live
///     connection was opened with a key AND that key actually decrypts the
///     file (a real read succeeds);
///   - a human reason otherwise (library not SQLCipher / opened WITHOUT a
///     key — i.e. a plain file / wrong key / empty key).
/// [expectedKeyHex] must be the key the connection was ACTUALLY opened with
/// (or null when it was opened without one) — SQLCipher exposes no pragma
/// to ask a connection whether a key was applied, so the caller reports it.
/// Nothing here ever claims success on a plain database, even when the
/// LIBRARY itself is cipher-capable — that distinction is the P7.2 honesty
/// contract.
String? verifyEncryption(Database db, {String? expectedKeyHex}) {
  final cipherVersion = supportsSqlCipher(db) ? _sqlCipherVersion(db) : null;
  if (cipherVersion == null) {
    return 'SQLCipher native library is NOT linked — the local database is '
        'currently NOT encrypted. (Encrypted storage is a device-verified '
        'step: link SQLCipher and store the key in platform secure storage.)';
  }
  // Cipher-capable library. Now the DATABASE must prove it is ciphertext:
  if (expectedKeyHex == null || expectedKeyHex.isEmpty) {
    if (readableWithoutKey(db)) {
      // An unkeyed connection that can read the schema = plain SQLite file.
      return 'The database is NOT encrypted: the connection was opened '
          'without a key and the file reads as plain SQLite (SQLCipher '
          'library version $cipherVersion is linked).';
    }
    return 'No encryption key available — the database could not be '
        'decrypted (locked).';
  }
  // Keyed connection: a real read failing here means the key does not
  // decrypt this file (wrong key or corrupt file).
  if (!readableWithoutKey(db)) {
    return 'Wrong encryption key (database could not be decrypted).';
  }
  return null; // cipher-capable + keyed + real read succeeds.
}

/// The SQLCipher version string of the linked library, or null.
String? _sqlCipherVersion(Database db) {
  try {
    final rows = db.select('PRAGMA cipher_version');
    if (rows.isEmpty) return null;
    final v = rows.first.columnAt(0)?.toString();
    return (v == null || v.isEmpty) ? null : v;
  } catch (_) {
    return null;
  }
}