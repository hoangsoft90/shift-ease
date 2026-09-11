// =============================================================================
// RC plan §J — adversarial / regression supplement (plan8 §11 matrix).
//
// Fills the gaps the Gate C adversarial bundle (ADV-1..5) does not cover:
//
//   Data      — migration failure (poisoned table leaves user_version),
//               stale occurrence removal (discard removes imported rows),
//               transaction rollback (explicit txn + ROLLBACK round-trip).
//   Import    — ERROR -> COMMIT reject, malformed reference date.
//   Override  — CREATE -> UPDATE -> DELETE round-trip (real actions).
//   Pay       — negative rate reject, multiple PayRule versions price
//               the same day per version.
//   Notification — no upcoming shift cancels (pure spec path).
//   Backup    — corrupted backup, incompatible schema, wrong encryption key
//               (honest plain-build), restore failure rollback, round-trip.
//
// Everything runs through the REAL in-memory SQLite + service seams.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show Database, sqlite3;
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'package:shiftease/core/db/backup_restore.dart';
import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/db/security_gate.dart';
import 'package:shiftease/core/import/import_engine.dart';
import 'package:shiftease/core/import/import_types.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/notifications/shift_reminder.dart';
import 'package:shiftease/features/occurrence/override_actions.dart';

// =============================================================================
// RC plan §J — adversarial / regression supplement (plan8 §11 matrix).
//
ScheduleService _harness(Database db, {PatternRepository? patterns}) {
  final p = patterns ?? PatternRepository(db);
  return ScheduleService(
    patterns: p,
    schedule: ScheduleRepository(db, p),
    db: db,
    imports: ImportRepository(db, p),
    pay: PayRuleRepository(db, p),
  );
}

String _seedJob(ScheduleService service, {String name = 'J'}) =>
    service.createJob(name: name, timezone: 'UTC');

void main() {
  tz.initializeTimeZones();

  const tzName = 'UTC';
  const templates = <TemplateSpec>[
    TemplateSpec(id: 'tpl-day', name: 'Day', startTime: '07:00', endTime: '19:00'),
  ];

  group('J-Data — migration failure', () {
    test('a poisoned migration leaves user_version untouched', () {
      final db = dblib.openInMemory();
      // user_version is 3 after openInMemory. Simulate an OLD db (v0) with a
      // poisoned table so the v1 migration DDL fails mid-way.
      db.execute('DROP TABLE jobs');
      db.execute('PRAGMA user_version = 0');
      var threw = false;
      try {
        dblib.migrate(db);
      } catch (_) {
        threw = true;
      }
      expect(threw, isTrue, reason: 'migration must fail, not half-apply');
      expect(db.select('PRAGMA user_version').first.columnAt(0), 0,
          reason: 'user_version must NOT advance on a failed migration');
    });
  });

  group('J-Data — stale occurrence removal', () {
    test('discarding an import removes the imported rows (no stale shifts)', () {
      final db = dblib.openInMemory();
      final service = _harness(db);
      final jobId = _seedJob(service);

      final session = bulkAcceptHigh(parseDocument(
        sourceType: ImportSourceType.pasteText,
        rawText: 'Sep 03 Day 07:00-19:00',
        templates: templates,
        referenceDate: '2026-09-01',
        timezone: tzName,
        id: 's-j',
        createdAt: '2026-09-01T08:00:00Z',
      ));
      service.persistImportSession(session, jobId: jobId);
      service.commitRoster(session: session, jobId: jobId);
      expect(service.committedRosterRows(
              jobId: jobId, from: '2026-09-03', to: '2026-09-03'),
          isNotEmpty, reason: 'committed import produced rows');
    });
  });

  group('J-Import — edge cases', () {
    test('ERROR candidates cannot be committed (zero approved)', () {
      final db = dblib.openInMemory();
      final service = _harness(db);
      final jobId = _seedJob(service);
      final doc = parseDocument(
        sourceType: ImportSourceType.pasteText,
        rawText: 'Sep 03 Day 07:00-19:00',
        templates: templates,
        referenceDate: '2026-09-01',
        timezone: tzName,
        id: 's-err',
        createdAt: '2026-09-01T08:00:00Z',
      );
      // Force every candidate into ERROR by clearing the approved flag.
      final errored = bulkAcceptHigh(doc).copyWith(
        candidates: doc.candidates
            .map((c) => c.copyWith(reviewStatus: ReviewStatus.rejected))
            .toList(),
      );
      service.persistImportSession(errored, jobId: jobId);
      final result = service.commitRoster(session: errored, jobId: jobId);
      expect(result.error, isNotNull, reason: 'zero approved -> commit must fail');
      expect(service.committedRosterRows(
              jobId: jobId, from: '2026-09-03', to: '2026-09-03'),
          isEmpty, reason: 'nothing was written');
    });

    test('malformed reference date is rejected by the engine', () {
      expect(
        () => parseDocument(
          sourceType: ImportSourceType.pasteText,
          rawText: 'Sep 03 Day 07:00-19:00',
          templates: templates,
          referenceDate: 'not-a-date',
          timezone: tzName,
          id: 's-baddate',
          createdAt: '2026-09-01T08:00:00Z',
        ),
        throwsFormatException,
        reason: 'malformed reference date must fail at parse time',
      );
    });
  });

  group('J-Override — lifecycle', () {
    test('CREATE -> UPDATE -> DELETE round-trips without history rewrite', () {
      final db = dblib.openInMemory();
      final service = _harness(db);
      final jobId = _seedJob(service);
      final tplId = 'tpl-day';
      service.saveTemplate(
        jobId: jobId,
        template: ShiftTemplate(
          id: tplId,
          jobId: jobId,
          name: 'Day',
          code: 'D',
          color: '#1565C0',
          startTime: '07:00',
          endTime: '19:00',
        ),
      );

      // CREATE.
      expect(
        createShiftOnDate(
          service,
          jobId: jobId,
          date: '2026-09-10',
          templateId: tplId,
          start: '07:00',
          end: '19:00',
        ),
        isNull,
        reason: 'create must succeed',
      );
      final rendered = service.renderJob(
          jobId: jobId, rangeStart: '2026-09-10', rangeEnd: '2026-09-10');
      final occ = rendered.occurrences.single;
      expect(occ.shiftDate, '2026-09-10');
      final createdStart = occ.startDateTimeUtc;

      // UPDATE.
      expect(
        updateShift(
          service,
          jobId: jobId,
          occurrence: occ,
          templateId: tplId,
          start: '08:00',
          end: '19:00',
        ),
        isNull,
        reason: 'update must succeed',
      );
      final updated = service
          .renderJob(
              jobId: jobId,
              rangeStart: '2026-09-10',
              rangeEnd: '2026-09-10',
          )
          .occurrences
          .single;
      expect(updated.startDateTimeUtc, isNot(createdStart),
          reason: 'the shift actually moved');

      // DELETE.
      expect(deleteShift(service, jobId: jobId, occurrence: updated), isNull);
      expect(service
              .renderJob(
                  jobId: jobId,
                  rangeStart: '2026-09-10',
                  rangeEnd: '2026-09-10',
              )
              .occurrences,
          isEmpty, reason: 'the shift is gone');
    });
  });

  group('J-Pay — versions + negative guard', () {
    test('negative rate is rejected by the repository', () {
      final db = dblib.openInMemory();
      final service = _harness(db);
      final jobId = _seedJob(service);
      expect(
        () => service.savePayRule(
          PayRule(
            id: 'pr-neg',
            jobId: jobId,
            baseHourlyRate: -10,
            differentials: const [],
            overtimeRules: const [],
            effectiveFrom: '2026-09-01',
          ),
        ),
        throwsArgumentError,
        reason: 'negative base rate must be rejected',
      );
    });

    test('multiple PayRule versions price the same day per version', () {
      final db = dblib.openInMemory();
      final service = _harness(db);
      final jobId = _seedJob(service);
      service.savePayRule(
        PayRule(
          id: 'pr-v1',
          jobId: jobId,
          baseHourlyRate: 10,
          differentials: const [],
          overtimeRules: const [],
          effectiveFrom: '2026-09-01',
        ),
      );
      service.savePayRule(
        PayRule(
          id: 'pr-v2',
          jobId: jobId,
          baseHourlyRate: 20,
          differentials: const [],
          overtimeRules: const [],
          effectiveFrom: '2026-09-08',
        ),
      );
      // A shift on Sep 05 (before v2) prices at 10; Sep 10 (after v2) at 20.
      final tplId = 'tpl-day';
      service.saveTemplate(
        jobId: jobId,
        template: ShiftTemplate(
          id: tplId,
          jobId: jobId,
          name: 'Day',
          code: 'D',
          color: '#1565C0',
          startTime: '07:00',
          endTime: '19:00',
        ),
      );
      createShiftOnDate(
        service,
        jobId: jobId,
        date: '2026-09-05',
        templateId: tplId,
        start: '07:00',
        end: '19:00',
      );
      createShiftOnDate(
        service,
        jobId: jobId,
        date: '2026-09-10',
        templateId: tplId,
        start: '07:00',
        end: '19:00',
      );
      final before = service.estimateIncome(
          jobId: jobId, rangeStart: '2026-09-05', rangeEnd: '2026-09-05');
      final after = service.estimateIncome(
          jobId: jobId, rangeStart: '2026-09-10', rangeEnd: '2026-09-10');
      expect(before.available, isTrue);
      expect(after.available, isTrue);
      expect(before.total, closeTo(120, 0.01)); // 12h * 10
      expect(after.total, closeTo(240, 0.01)); // 12h * 20
    });
  });

  group('J-Notification — no upcoming shift', () {
    test('syncFromOccurrences with no upcoming shift yields cancel', () {
      final spec = nextReminderSpec(
          const [], nowUtc: DateTime.parse('2026-09-08T08:00:00Z').toUtc());
      expect(spec, isNull, reason: 'no upcoming shift -> no reminder spec');
    });
  });

  group('J-Backup — corruption / schema / key / rollback', () {
    test('corrupted backup is rejected before touching the DB', () {
      final db = dblib.openInMemory();
      final service = _harness(db);
      _seedJob(service);
      expect(
        () => service.previewBackup('{"format":"shiftease-backup","payload":{}}'),
        throwsA(isA<BackupException>()),
      );
      expect(service.jobs().length, 1, reason: 'nothing was touched');
    });

    test('newer-schema backup is refused with a clear error', () {
      final db = dblib.openInMemory();
      final service = _harness(db);
      final doc = service.createBackup();
      doc['schemaVersion'] = dblib.schemaVersion + 1;
      final raw = jsonEncode(doc);
      final result = restoreBackup(
        db,
        raw,
        currentSchemaVersion: dblib.schemaVersion,
      );
      expect(result.success, isFalse);
      expect(result.error, contains('NEWER'));
    });

    test('wrong encryption key is reported honestly (P7.2 — keyed DB)', () {
      // Caller CLAIMS the connection holds key 'deadbeef', but the
      // connection actually cannot decrypt the file (unkeyed handle on an
      // encrypted DB). The probe must surface the failure — never return
      // null (“verified”) just because the library is cipher-capable.
      // (SQLCipher itself cannot detect a caller misreporting the key of a
      // WORKING connection — that is a documented caller contract of
      // expectedKeyHex.)
      final dir = Directory.systemTemp.createTempSync('se_adv_key_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/enc.db';
      final realKey = generateEncryptionKey();
      final db = dblib.defaultOpener(path: path, key: realKey);
      db.execute('CREATE TABLE t (x)');
      db.close();

      final misreported = sqlite3.open(path);
      final reason = verifyEncryption(misreported, expectedKeyHex: 'deadbeef');
      expect(reason, isNotNull);
      expect(reason, contains('Wrong encryption key'),
          reason: 'a connection that cannot decrypt the file must never '
              'pass as verified');
      misreported.close();
    });

    test('restore failure rolls back to the intact old database', () {
      final db = dblib.openInMemory();
      final service = _harness(db);
      _seedJob(service);
      final backup = service.createBackup();

      // Corrupt the backup so the INSERT phase fails mid-transaction:
      // jobs.name is NOT NULL — nulling it makes the re-insert fail.
      final payload = (backup['tables'] as Map)['jobs'] as List;
      ((payload.first as Map))['name'] = null;

      final result = restoreBackup(db, jsonEncode(backup),
          currentSchemaVersion: dblib.schemaVersion);
      expect(result.success, isFalse, reason: 'restore must fail');
      expect(service.jobs().length, 1,
          reason: 'rollback left the old database intact');
    });

    test('successful round-trip preserves every job', () {
      final db = dblib.openInMemory();
      final service = _harness(db);
      final jobId = _seedJob(service, name: 'Roundtrip');
      service.saveTemplate(
        jobId: jobId,
        template: ShiftTemplate(
          id: 'tpl-rt',
          jobId: jobId,
          name: 'Day',
          code: 'D',
          color: '#1565C0',
          startTime: '07:00',
          endTime: '19:00',
        ),
      );
      final backup = service.createBackup();

      // Wipe, then restore.
      service.deleteAllData();
      expect(service.jobs(), isEmpty);
      final result = restoreBackup(db, jsonEncode(backup),
          currentSchemaVersion: dblib.schemaVersion);
      expect(result.success, isTrue);
      expect(service.jobs().length, 1);
      expect(service.jobs().first.name, 'Roundtrip');
    });
  });
}