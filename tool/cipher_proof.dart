// P7.2 — CI visibility proof that the linked native SQLite build IS SQLCipher.
//
// The suite itself already proves encryption (test/core/db/security_gate_test.dart
// opens real encrypted file DBs with PRAGMA key + asserts cipher_version), but a
// one-line version print in the CI log makes the native-encryption evidence
// explicit and greppable.
//
// Pure Dart on purpose: no flutter_test import, so CI can run it with plain
// `dart run` (build hooks fire there too). Exit code != 0 when cipher_version
// is absent — i.e. someone dropped the `source: sqlcipher` hook define.

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main() {
  final db = sqlite3.openInMemory();
  final rows = db.select('PRAGMA cipher_version;');
  db.close();

  if (rows.isEmpty) {
    stderr.writeln('P7.2 FAILURE: cipher_version is empty — '
        'the linked build is PLAIN sqlite3, not SQLCipher. '
        'Check pubspec.yaml hooks.user_defines.sqlite3.source.');
    exit(1);
  }
  final version = rows.first.values.first;
  stdout.writeln('P7.2 OK: linked native build is SQLCipher $version');
}
