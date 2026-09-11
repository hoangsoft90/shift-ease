// =============================================================================
// Gate C A5 — Adversarial test bundle (plan_gate_c §1 A5 / §5 AC-C5).
//
// Every scenario the P1 integrity fixes exist for, exercised end-to-end
// through the real persistence + service seams (in-memory SQLite, no fakes
// except one fault-injection repository subclass whose SECOND transaction
// write throws — used to prove changeRosterFrom rolls back atomically):
//
//   ADV-1  EXTRACTED -> commitImport       → FAIL, zero rows, never COMMITTED
//   ADV-2  changeRosterFrom fails mid-way  → old version NOT left CLOSED
//   ADV-3  override same id, DIFFERENT payload → ImmutableHistoryError
//   ADV-4  override same id, SAME payload  → idempotent (1 row)
//   ADV-5  session COMMITTED overwrite     → StateError, row untouched
//
// ADV-6 (full-suite regression Gate 0–A) is the whole `flutter test test/`
// run itself — its log is recorded in result15_gate_c.txt, not nested here.
// =============================================================================

import 'package:sqlite3/sqlite3.dart' show Database;
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/import/import_engine.dart';
import 'package:shiftease/core/import/import_types.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/domain/schedule_service.dart';

/// PatternRepository whose second savePatternInTransaction throws — injects a
/// failure exactly at the “insert the new version” step of changeRosterFrom.
class _FailOnSecondInsert extends PatternRepository {
  _FailOnSecondInsert(Database db) : super(db);
  int _txnSaves = 0;
  @override
  void savePatternInTransaction({
    required String jobId,
    required ShiftPattern pattern,
    List<ShiftTemplate> templates = const [],
  }) {
    _txnSaves++;
    if (_txnSaves == 2) {
      throw StateError('ADV-2 injected failure on the second write');
    }
    super.savePatternInTransaction(
        jobId: jobId, pattern: pattern, templates: templates);
  }
}

void main() {
  tz.initializeTimeZones();

  const tzName = 'UTC';
  const templates = <TemplateSpec>[
    TemplateSpec(id: 'tpl-day', name: 'Day', startTime: '07:00', endTime: '19:00'),
  ];

  ScheduleService harness(Database db) {
    final patterns = PatternRepository(db);
    return ScheduleService(
      patterns: patterns,
      schedule: ScheduleRepository(db, patterns),
      db: db,
      imports: ImportRepository(db, patterns),
    );
  }

  String seedJob(ScheduleService service) =>
      service.createJob(name: 'Adv Job', timezone: tzName);

  /// One approved+reviewing 2-shift session (Sep 03/04) via the real engine.
  ImportSession reviewingSession() => bulkAcceptHigh(parseDocument(
        sourceType: ImportSourceType.pasteText,
        rawText: 'Sep 03 Day 07:00-19:00\nSep 04 Day 07:00-19:00',
        templates: templates,
        referenceDate: '2026-09-01',
        timezone: tzName,
        id: 's-adv',
        createdAt: '2026-09-01T08:00:00Z',
      ));

  group('ADV-1 — EXTRACTED -> COMMIT', () {
    test('rejected at the engine boundary; nothing written, never COMMITTED',
        () {
      final db = dblib.openInMemory();
      final service = harness(db);
      final jobId = seedJob(service);

      // A session that was parsed but NEVER reviewed (state EXTRACTED).
      final extracted = parseDocument(
        sourceType: ImportSourceType.pasteText,
        rawText: 'Sep 03 Day 07:00-19:00',
        templates: templates,
        referenceDate: '2026-09-01',
        timezone: tzName,
        id: 's-adv1',
        createdAt: '2026-09-01T08:00:00Z',
      );
      final result =
          service.commitRoster(session: extracted, jobId: jobId);

      expect(result.error, isNotNull);
      expect(result.error?.code, ImportErrorCodes.illegalState);
      expect(result.session.state, ImportState.error);
      expect(db.select('SELECT COUNT(*) AS c FROM occurrences').first['c'], 0,
          reason: 'no occurrence may be written from EXTRACTED');
      final stored = ImportRepository(db).sessionById('s-adv1')!;
      expect(stored.state, isNot(ImportState.committed));
      expect(stored.committedOccurrenceIds, isEmpty);
      db.close();
    });
  });

  group('ADV-2 — changeRosterFrom fails mid-write', () {
    test('old version rolls back: never left CLOSED without a successor', () {
      final db = dblib.openInMemory();
      final patterns = _FailOnSecondInsert(db);
      final service = ScheduleService(
        patterns: patterns,
        schedule: ScheduleRepository(db, patterns),
        db: db,
      );
      final jobId = seedJob(service);
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
      final templateId = service.templates(jobId).single.id;
      expect(templateId, isNotEmpty);

      final from = '2026-09-01';
      final pattern = ShiftPattern(
        id: slugId('pat', ['Rota', jobId, from]),
        jobId: jobId,
        name: 'Rota',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 1,
        sequence: [templateId],
        anchorDate: from,
        defaultTimezone: tzName,
        effectiveFrom: from,
      );
      service.saveNewPattern(pattern: pattern, templates: service.templates(jobId));
      final current = service.patterns(jobId).single;

      expect(
        () => service.changeRosterFrom(
          current: current,
          newEffectiveFrom: '2026-09-10',
          newName: 'Rota v2',
          newCycleLengthDays: 1,
          newSequence: [templateId],
          templates: service.templates(jobId),
        ),
        throwsStateError,
      );

      final after = service.patterns(jobId);
      expect(after.length, 1);
      expect(after.single.effectiveUntil, isNull,
          reason: 'close rolled back with the failed insert (atomic)');
      db.close();
    });
  });

  group('ADV-3/ADV-4 — override immutability', () {
    test('same id + different payload throws; same payload is idempotent', () {
      final db = dblib.openInMemory();
      final service = harness(db);
      final jobId = seedJob(service);
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
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: slugId('pat', ['Daily', jobId, '2026-09-07']),
          jobId: jobId,
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: [service.templates(jobId).single.id],
          anchorDate: '2026-09-07',
          defaultTimezone: tzName,
          effectiveFrom: '2026-09-07',
        ),
        templates: service.templates(jobId),
      );
      service.renderJob(
          jobId: jobId, rangeStart: '2026-09-07', rangeEnd: '2026-09-07');
      service.renderJob(
          jobId: jobId, rangeStart: '2026-09-07', rangeEnd: '2026-09-07');
      final baseId = service
          .renderJob(jobId: jobId, rangeStart: '2026-09-07', rangeEnd: '2026-09-07')
          .occurrences
          .single
          .id;

      final ovr = Override(
        id: 'adv-ovr',
        occurrenceId: baseId,
        operation: OverrideOperation.update,
        updatePayload: const UpdatePayload(startTime: '09:00', endTime: '17:00'),
        createdAt: '2026-09-01T08:00:00Z',
      );
      service.applyOverride(ovr, jobId: jobId);

      // ADV-4: identical payload (fresh timestamp allowed) -> idempotent.
      service.applyOverride(
        Override(
          id: ovr.id,
          occurrenceId: baseId,
          operation: OverrideOperation.update,
          updatePayload: const UpdatePayload(startTime: '09:00', endTime: '17:00'),
          createdAt: '2026-09-01T09:00:00Z',
        ),
        jobId: jobId,
      );
      expect(
          db.select('SELECT COUNT(*) AS c FROM overrides').first['c'], 1);

      // ADV-3: same id + different payload -> exception.
      expect(
        () => service.applyOverride(
          Override(
            id: ovr.id,
            occurrenceId: baseId,
            operation: OverrideOperation.update,
            updatePayload:
                const UpdatePayload(startTime: '10:00', endTime: '18:00'),
            createdAt: '2026-09-01T10:00:00Z',
          ),
          jobId: jobId,
        ),
        throwsA(isA<ImmutableHistoryError>()),
      );
      expect(
          db.select('SELECT COUNT(*) AS c FROM overrides').first['c'], 1);
      db.close();
    });
  });

  group('ADV-5 — COMMITTED session overwrite', () {
    test('saveSession with a changed payload after commit throws', () {
      final db = dblib.openInMemory();
      final service = harness(db);
      final jobId = seedJob(service);
      final session = reviewingSession();
      final result =
          service.commitRoster(session: session, jobId: jobId);
      expect(result.error, isNull);

      // Tamper: same id, different raw extraction.
      final repo = ImportRepository(db);
      final tampered = result.session.copyWith(
        rawExtraction: const RawExtraction(
            sourceType: ImportSourceType.pasteText,
            entries: [
              RawEntry(lineNumber: 1, original: 'Sep 30 OFF', shiftTypeLabel: 'Off'),
            ]),
      );
      expect(() => repo.saveSession(tampered, jobId: jobId), throwsStateError);

      final reloaded = repo.sessionById(result.session.id)!;
      expect(reloaded.state, ImportState.committed);
      expect(reloaded.rawExtraction.entries.length, 2,
          reason: 'stored audit trail untouched by the refused overwrite');
      db.close();
    });
  });
}
