// =============================================================================
// Gate A §A1 — production composition test (NOT a widget test).
//
// Proves the Import flow is reachable from the app's real wiring: the service
// built by composeService(db) — the exact function main() calls — has the
// import repositories attached. If main.dart ever drops `imports:` again this
// test fails, instead of Import working only inside widget tests.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:shiftease/core/db/db.dart';
import 'package:shiftease/main.dart' show composeService;

void main() {
  test('production composition enables the import flow (Gate A §A1)', () {
    final db = openInMemory();
    // Go through the SAME factory main() uses — never re-wire by hand here
    // (that is exactly the drift that hid the bug the first time).
    final service = composeService(db);
    expect(service.importEnabled, isTrue,
        reason: 'main.dart must pass ImportRepository into ScheduleService');
    db.close();
  });
}
