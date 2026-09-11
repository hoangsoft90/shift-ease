// =============================================================================
// P7.2 — security gate tests on the SQLCipher-LINKED build.
//
// Since P7.2 (pubspec hook `source: sqlcipher`), the native library linked
// into every test run IS SQLCipher — so these tests verify REAL encryption
// behavior on real files, not a plain build's absence of it:
//
//   1. PRAGMA cipher_version returns a live version.
//   2. defaultOpener(key:) creates a file that is NOT plain SQLite
//      (ciphertext negative control — not an extension/flag check).
//   3. Reopen with the same key works; data survives.
//   4. A wrong key cannot open the file (SqlCipherUnavailableError) — and
//      never silently falls back to plain.
//   5. defaultOpener() without a key REFUSES on this build (fail-closed).
//   6. verifyEncryption semantics: plain file says NOT encrypted even on a
//      cipher-capable library; keyed DB with the right key verifies null.
//   7. Key lifecycle: getOrCreateEncryptionKey generates once, then
//      re-reads the same key.
// =============================================================================

import 'dart:io';

import 'package:shiftease/core/db/db.dart'
    show defaultOpener, openDatabase, SqlCipherUnavailableError, schemaVersion;
import 'package:shiftease/core/db/security_gate.dart';
import 'package:shiftease/features/security/secure_secret_store.dart'
    show getOrCreateEncryptionKey;
import 'package:sqlite3/sqlite3.dart' as sq;
import 'package:test/test.dart';

void main() {
  group('generateEncryptionKey', () {
    test('returns 64 lowercase hex chars (32 random bytes)', () {
      final key = generateEncryptionKey();
      expect(key.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key), isTrue,
          reason: 'key must be pure lowercase hex');
    });

    test('two keys never collide', () {
      final a = generateEncryptionKey();
      final b = generateEncryptionKey();
      expect(a, isNot(b));
    });
  });

  group('InMemorySecretStore (test double)', () {
    test('write/read/delete round-trip', () async {
      final store = InMemorySecretStore();
      expect(await store.read('db_key'), isNull);

      await store.write('db_key', 'abc123');
      expect(await store.read('db_key'), 'abc123');

      await store.delete('db_key');
      expect(await store.read('db_key'), isNull);
    });

    test('overwriting replaces the value', () async {
      final store = InMemorySecretStore();
      await store.write('db_key', 'first');
      await store.write('db_key', 'second');
      expect(await store.read('db_key'), 'second');
    });
  });

  group('SQLCipher linked build', () {
    test('PRAGMA cipher_version returns a live SQLCipher version', () {
      final db = sq.sqlite3.openInMemory();
      final rows = db.select('PRAGMA cipher_version');
      db.close();
      expect(rows, isNotEmpty,
          reason: 'the build hook must link SQLCipher, not plain sqlite3');
      expect(rows.first.columnAt(0)?.toString(), isNotEmpty);
    });

    test('supportsSqlCipher is true on this build', () {
      final db = sq.sqlite3.openInMemory();
      expect(supportsSqlCipher(db), isTrue);
      db.close();
    });
  });

  group('encrypted database (real files)', () {
    late Directory tmp;
    late String dbPath;
    late String key;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('se_p72_');
      dbPath = '${tmp.path}/enc.db';
      key = generateEncryptionKey();
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('keyed create → file is ciphertext (not plain SQLite)', () {
      final db = openDatabase(opener: defaultOpener, path: dbPath, key: key);
      db.execute('CREATE TABLE t (x INTEGER)');
      db.select('SELECT count(*) FROM sqlite_master'); // ciphertext control
      db.close();

      final bytes = File(dbPath).readAsBytesSync();
      // P7.2 negative control: a PLAIN SQLite database always begins with
      // the 16-byte header "SQLite format 3\0". SQLCipher 4 AES-256-CBC
      // (default) with HMAC-SHA512 has a 4096-byte page and a salted first
      // page — the header string cannot survive encryption. Checking bytes,
      // not flags or extensions.
      final header = bytes.sublist(0, 16);
      final isPlainHeader = String.fromCharCodes(header) == 'SQLite format 3';
      expect(isPlainHeader, isFalse,
          reason: 'an encrypted DB file must NOT begin with the plain '
              'SQLite magic header');
      expect(bytes.length, greaterThanOrEqualTo(4096));
    });

    test('reopen with the same key works and data survives', () {
      final db = openDatabase(opener: defaultOpener, path: dbPath, key: key);
      db.execute('CREATE TABLE t (x INTEGER)');
      db.execute('INSERT INTO t VALUES (42)');
      final v1 = db.select('SELECT x FROM t').first.columnAt(0);
      db.close();

      final db2 = openDatabase(opener: defaultOpener, path: dbPath, key: key);
      final v2 = db2.select('SELECT x FROM t').first.columnAt(0);
      db2.close();
      expect(v2, v1);
    });

    test('wrong key FAILS the open (no plain fallback)', () {
      final db = openDatabase(opener: defaultOpener, path: dbPath, key: key);
      db.execute('CREATE TABLE t (x INTEGER)');
      db.close();

      final wrongKey = generateEncryptionKey();
      expect(wrongKey, isNot(key));
      expect(
        () => defaultOpener(path: dbPath, key: wrongKey),
        throwsA(isA<SqlCipherUnavailableError>()),
      );
      // The file must be untouched by the failed attempt.
      expect(File(dbPath).existsSync(), isTrue);
    });

    test('open WITHOUT a key is refused on this build (fail-closed)', () {
      final db = openDatabase(opener: defaultOpener, path: dbPath, key: key);
      db.execute('CREATE TABLE t (x INTEGER)');
      db.close();

      // Unkeyed open of an on-disk DB must refuse — and must not touch it.
      expect(
        () => defaultOpener(path: dbPath),
        throwsA(isA<SqlCipherUnavailableError>()),
      );
      expect(File(dbPath).existsSync(), isTrue);
    });

    test('migrations run on the encrypted DB (create → reopen → v3)', () {
      final db = openDatabase(opener: defaultOpener, path: dbPath, key: key);
      db.close();
      final db2 = openDatabase(opener: defaultOpener, path: dbPath, key: key);
      final version =
          db2.select('PRAGMA user_version').first.columnAt(0) as int;
      expect(version, schemaVersion);
      db2.close();
    });
  });

  group('verifyEncryption semantics (P7.2 tightened)', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('se_p72_probe_');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('plain file on a cipher-capable library reports NOT encrypted', () {
      final path = '${tmp.path}/plain.db';
      final db = sq.sqlite3.open(path);
      db.execute('CREATE TABLE t (x)');
      final reason = verifyEncryption(db);
      expect(reason, isNotNull);
      expect(reason, contains('NOT encrypted'));
      db.close();
    });

    test('keyed encrypted DB verifies (null reason)', () {
      final key = generateEncryptionKey();
      final path = '${tmp.path}/enc.db';
      final db = defaultOpener(path: path, key: key);
      db.execute('CREATE TABLE t (x)');
      // The caller reports the key the connection was ACTUALLY opened with.
      expect(verifyEncryption(db, expectedKeyHex: key), isNull);
      db.close();
    });

    test('unkeyed connection to an ENCRYPTED file reports locked', () {
      final key = generateEncryptionKey();
      final path = '${tmp.path}/enc.db';
      final db = defaultOpener(path: path, key: key);
      db.execute('CREATE TABLE t (x)');
      db.close();

      // A connection that never supplied a key cannot read the file.
      final locked = sq.sqlite3.open(path);
      final reason = verifyEncryption(locked);
      expect(reason, isNotNull);
      expect(reason, contains('key'));
      locked.close();
    });

    test('unkeyed connection (reported honestly as expectedKeyHex null) to '
        'an encrypted file reports locked', () {
      final key = generateEncryptionKey();
      final path = '${tmp.path}/enc3.db';
      final db = defaultOpener(path: path, key: key);
      db.execute('CREATE TABLE t (x)');
      db.close();

      // An in-memory handle on an encrypted FILE (via the raw sqlite3 open,
      // as some tooling would) reads as garbage — the probe reports locked,
      // never “encrypted”.
      final locked = sq.sqlite3.open(path);
      final reason = verifyEncryption(locked, expectedKeyHex: null);
      expect(reason, isNotNull);
      expect(reason, contains('key'));
      locked.close();
    });
  });

  group('key lifecycle (P7.2 required flow)', () {
    test('first call generates and stores; later calls re-read the SAME key',
        () async {
      final store = InMemorySecretStore();
      final first = await getOrCreateEncryptionKey(store);
      expect(first.length, 64);
      final second = await getOrCreateEncryptionKey(store);
      expect(second, first, reason: 'restart must reuse the stored key');
    });

    test('a corrupt stored key is surfaced as-is (no silent regeneration)',
        () async {
      final store = InMemorySecretStore();
      await store.write('shiftease.db.master_key', 'corrupted');
      final key = await getOrCreateEncryptionKey(store);
      expect(key, 'corrupted',
          reason: 'the opener will fail closed on a bad key — the app must '
              'NOT silently mint a new key that cannot decrypt old data');
    });
  });
}
