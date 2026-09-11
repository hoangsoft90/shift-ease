// P0 regression tests (issue1.md / prompt_fix1.md): the production DB path
// must never again be HOME/'.'-derived on mobile. Every branch of
// resolveDbPath is exercised through an injectable PlatformProbe — no
// platform channels, no real device needed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftease/core/db/db_path.dart';

class _FakeProbe implements PlatformProbe {
  @override
  final bool isAndroid;
  @override
  final bool isIOS;
  final Map<String, String?> environment;
  @override
  final String? homeDir;
  final Directory appSupport;

  _FakeProbe({
    this.isAndroid = false,
    this.isIOS = false,
    this.environment = const {},
    this.homeDir,
    required this.appSupport,
  });

  @override
  String? env(String key) => environment[key];

  @override
  Future<Directory> applicationSupportDirectory() async => appSupport;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('shiftease_dbpath_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('resolveDbPath — mobile branches (P0 errno-30 regression)', () {
    test('Android: app-support dir + shiftease.db, directory created', () async {
      final support = Directory('${tmp.path}/app_support');
      final path = await resolveDbPath(
        probe: _FakeProbe(isAndroid: true, appSupport: support),
      );
      expect(path, '${support.path}/shiftease.db');
      expect(support.existsSync(), isTrue,
          reason: 'directory must be created inside app-writable storage');
    });

    test('iOS: app-support dir + shiftease.db, directory created', () async {
      final support = Directory('${tmp.path}/ios_support');
      final path = await resolveDbPath(
        probe: _FakeProbe(isIOS: true, appSupport: support),
      );
      expect(path, '${support.path}/shiftease.db');
      expect(support.existsSync(), isTrue);
    });

    test(
        'INVARIANT (P0): mobile path is absolute and never the errno-30 shape',
        () async {
      final support = Directory('${tmp.path}/s');
      final path = await resolveDbPath(
        probe: _FakeProbe(isAndroid: true, appSupport: support),
      );
      expect(File(path).isAbsolute, isTrue);
      // The bug shape: './.shiftease' → a relative path or a '/./' segment.
      expect(path.contains('/./'), isFalse);
      expect(path.startsWith('./'), isFalse);
      expect(path, isNot(contains('.shiftease/.shiftease')));
    });

    test('SHIFTEASE_DB override wins even on mobile', () async {
      final path = await resolveDbPath(
        probe: _FakeProbe(
          isAndroid: true,
          appSupport: Directory('${tmp.path}/s'),
          environment: {'SHIFTEASE_DB': '/data/local/tmp/explicit.db'},
        ),
      );
      expect(path, '/data/local/tmp/explicit.db');
    });
  });

  group('resolveDbPath — desktop branches', () {
    test('HOME set: \$HOME/.shiftease/shiftease.db, directory created',
        () async {
      final home = Directory('${tmp.path}/home');
      home.createSync(recursive: true);
      final path = await resolveDbPath(
        probe: _FakeProbe(homeDir: home.path, appSupport: Directory('${tmp.path}/s')),
      );
      expect(path, '${home.path}/.shiftease/shiftease.db');
      expect(Directory('${home.path}/.shiftease').existsSync(), isTrue);
    });

    test('HOME unset on desktop: StateError — NEVER a "." CWD fallback',
        () async {
      await expectLater(
        resolveDbPath(
          probe: _FakeProbe(homeDir: null, appSupport: Directory('${tmp.path}/s')),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('empty SHIFTEASE_DB is treated as unset (falls through to HOME)',
        () async {
      final home = Directory('${tmp.path}/home2');
      home.createSync(recursive: true);
      final path = await resolveDbPath(
        probe: _FakeProbe(
          homeDir: home.path,
          appSupport: Directory('${tmp.path}/s'),
          environment: {'SHIFTEASE_DB': ''},
        ),
      );
      expect(path, '${home.path}/.shiftease/shiftease.db');
    });
  });
}
