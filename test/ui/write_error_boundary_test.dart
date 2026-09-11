// =============================================================================
// RC plan §A1 — UI write error boundary tests.
//
//   1. write_guard unit: every exception type maps to a user-facing message;
//      runWrite/runWriteAsync return null on success.
//   2. QuickAdd CREATE: when the repository write throws ImmutableHistoryError
//      the sheet shows the message and stays open — the exception must never
//      escape the onTap handler as an unhandled crash.
//   3. Import commit: when commitRoster throws (DB/transaction failure) the
//      screen shows the reason and the exception does not crash the app.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/import/import_types.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/time/time_engine.dart' show initializeTimezoneDatabase;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/calendar/quick_add_sheet.dart';
import 'package:shiftease/features/common/write_guard.dart';
import 'package:shiftease/features/import/import_screen.dart';

const _tz = 'America/New_York';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _mondayIso() {
  final now = DateTime.now();
  final mon = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - DateTime.monday));
  return _iso(mon);
}

/// Service whose applyOverride ALWAYS fails — simulates a repository write
/// exception (e.g. append-only immutability violation) reaching the UI.
class _ThrowingOverrideService extends ScheduleService {
  _ThrowingOverrideService({required super.patterns, required super.schedule, required super.db});

  @override
  void applyOverride(Override override, {required String jobId, String? patternId}) {
    throw ImmutableHistoryError(
        'override ${override.id} is already committed with a different payload');
  }
}

/// Service whose commitRoster ALWAYS fails — simulates a DB/transaction
/// failure at the import commit seam.
class _ThrowingCommitService extends ScheduleService {
  _ThrowingCommitService({
    required super.patterns,
    required super.schedule,
    required super.db,
    super.imports,
  });

  @override
  CommitResult commitRoster({
    required ImportSession session,
    required String jobId,
  }) {
    throw StateError('database is locked — commit failed');
  }
}

void main() {
  setUpAll(initializeTimezoneDatabase);

  group('write_guard (A1 unit)', () {
    test('runWrite returns null on success and maps every exception type', () {
      expect(runWrite(() {}), isNull);
      expect(runWrite(() => throw StateError('db locked')),
          'db locked');
      expect(runWrite(() => throw ArgumentError('bad date')),
          'bad date');
      expect(
        runWrite(() => throw const ImmutableHistoryError('already committed')),
        contains('Cannot rewrite history'),
      );
      expect(runWrite(() => throw FormatException('HH:mm')),
          contains('Invalid format'));
      expect(runWrite(() => throw Exception('boom')), contains('boom'));
    });

    test('runWriteAsync maps async failures the same way', () async {
      expect(await runWriteAsync(() async {}), isNull);
      expect(await runWriteAsync(() async => throw StateError('x')), 'x');
      expect(
        await runWriteAsync(() async => throw const ImmutableHistoryError('y')),
        contains('Cannot rewrite history'),
      );
    });
  });

  group('A1 — QuickAdd CREATE write failure', () {
    testWidgets('ImmutableHistoryError shows on the sheet, never crashes',
        (tester) async {
      final db = dblib.openInMemory();
      final patterns = PatternRepository(db);
      final service = _ThrowingOverrideService(
        patterns: patterns,
        schedule: ScheduleRepository(db, patterns),
        db: db,
      );
      // Real job + template + pattern so createShiftOnDate reaches the write.
      final jobId = service.createJob(name: 'Hospital', timezone: _tz);
      service.saveTemplate(
        jobId: jobId,
        template: ShiftTemplate(
          id: slugId('tpl', ['Day', '07:00', '19:00']),
          jobId: jobId,
          name: 'Day',
          code: 'D',
          color: '#1565C0',
          startTime: '07:00',
          endTime: '19:00',
        ),
      );
      final tplId = service.templates(jobId).first.id;
      final monday = _mondayIso();
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: slugId('pat', ['Rota', jobId, monday]),
          jobId: jobId,
          name: 'Rota',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 8,
          sequence: [tplId, tplId, tplId, tplId, null, null, null, null],
          anchorDate: monday,
          defaultTimezone: _tz,
          effectiveFrom: monday,
        ),
        templates: service.templates(jobId),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QuickAddSheet(
            service: service,
            jobId: jobId,
            date: monday,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Tap the template tile → write throws → sheet must show the message
      // and stay open (no crash, no fabricated success).
      await tester.tap(find.textContaining('Day (07:00'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cannot rewrite history'), findsOneWidget);
      expect(find.text('Quick add on $monday'), findsOneWidget,
          reason: 'sheet stays open so the user can retry');
      expect(find.byType(QuickAddSheet), findsOneWidget);
      db.close();
    });
  });

  group('A1 — import commit write failure', () {
    testWidgets('commitRoster StateError shows on the screen, never crashes',
        (tester) async {
      final db = dblib.openInMemory();
      final patterns = PatternRepository(db);
      final service = _ThrowingCommitService(
        patterns: patterns,
        schedule: ScheduleRepository(db, patterns),
        db: db,
        imports: ImportRepository(db),
      );
      final jobId = service.createJob(name: 'Hospital', timezone: _tz);
      service.saveTemplate(
        jobId: jobId,
        template: ShiftTemplate(
          id: slugId('tpl', ['Day', '07:00', '19:00']),
          jobId: jobId,
          name: 'Day',
          code: 'D',
          color: '#1565C0',
          startTime: '07:00',
          endTime: '19:00',
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: ImportScreen(service: service, jobId: jobId),
      ));
      await tester.pumpAndSettle();

      // Parse a one-line roster → approve it → commit.
      await tester.enterText(
          find.byType(TextField), 'Sep 03 Day 07:00-19:00');
      await tester.tap(find.text('Parse & review'));
      await tester.pumpAndSettle();
      expect(find.textContaining('candidate(s)'), findsOneWidget);

      await tester.tap(find.byTooltip('Approve'));
      await tester.pumpAndSettle();
      expect(find.textContaining('approved 1'), findsOneWidget);

      await tester.tap(find.textContaining('Commit'));
      await tester.pumpAndSettle();

      // A1: the StateError surfaces as an error line, the app keeps running.
      expect(find.text('database is locked — commit failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      db.close();
    });
  });
}