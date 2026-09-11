# ShiftEase — Plan4: Gate 3 (Persistence Layer) — DRAFT CHỜ DUYỆT

Ngày: 2026-09-05 · Trạng thái: **chờ human approve trước khi code schema**
Phạm vi nguồn: plan1_final_v2 §10 (INVARIANT-008), plan2 §2.1 ER + §2.2
VersionedEntity + §6.1 (SQLCipher), plan3_final §9 "Gate 2 (Persistence)".

## 1. Mục tiêu & phạm vi

Lưu trữ offline-first (INVARIANT-008) cho các ENTITY ĐÃ CÓ MODEL trong
`lib/core/` — không tạo table cho thứ chưa có domain model:

| Có | KHÔNG (gate sau) |
|---|---|
| Job, ShiftTemplate, ShiftPattern (+sequence), ShiftOccurrence, Override, PayRule (+differential/overtime child), ImportSession (+candidate), schema versioning | CalendarEvent + subtypes (chưa có model), materialized projection dạng view cache, backup/restore UI, cloud sync |

## 2. Quyết định storage (đã research + đối chiếu spec)

- **SQLite** — plan2.md:1097 ĐÃ LOCK: `Local storage = SQLite encryption (SQLCipher)`.
  Gravity Index gợi ý Turso/cloud DB → **bác bỏ** (vi phạm INVARIANT-008 offline-first).
- **Driver: package `sqlite3` (FFI)** + repository typed viết tay — thay vì Drift
  (codegen build_runner trong CI). Lý do: pure Dart hiện tại, pubspec tối thiểu
  (+1 dep), SQL đầy đủ quyền kiểm soát, migration bằng `PRAGMA user_version`.
- **SQLCipher seam**: `DatabaseOpener.open({required String path, String? key})`.
  Khi `key != null` → yêu cầu native SQLCipher (CI/test dùng plain SQLite;
  production inject opener có key). Không giả lập mã hóa.
- **Test**: `sqlite3` in-memory (`:memory:`) mỗi test — không cần file, chạy CI sạch.

## 3. Identity — UUID tách khỏi deterministic id (plan3_final §326)

Mỗi table: `uuid TEXT PRIMARY KEY` (sinh `Random.secure`, hex 32) + 
`id TEXT NOT NULL UNIQUE` (deterministic engine id: occurrence `pat-x_2026-09-03_st-x`,
override `{id}_ovr_{n}`, PayRule `rule-v1`, ImportSession `session-...`).
- Engine (pure) vẫn dùng deterministic id — DB layer ánh xạ 1-1.
- Không bao giờ tự sửa quá khứ: **không UPDATE/DELETE** lên occurrence đã commit
  (INVARIANT-006) — thay đổi quá khứ chỉ qua ghi Override (đã là audit trail).

## 4. Schema v1 (tables)

```
jobs(id, uuid, name, defaultTimezone)
shift_templates(id, uuid, jobId→jobs, name, code, color, startTime, endTime,
                breakDurationMinutes)
shift_patterns(id, uuid, jobId, name, type, cycleLengthDays, anchorDate,
               defaultTimezone, effectiveFrom, effectiveUntil?)
pattern_sequence(patternUuid→shift_patterns, positionIdx, templateId? NULL=OFF)
occurrences(id, uuid, patternId, shiftDate, templateId, startDateTimeUtc,
            endDateTimeUtc, timezone, source, sourceOverrideId?,
            actualPayEstimate?, payEstimateFrom?  ← INVARIANT-006 snapshot)
overrides(id, uuid, occurrenceId, operation, payloadJson, swapWithOccurrenceId?,
          createdAt, reason?)
pay_rules(id, uuid, jobId, baseHourlyRate, effectiveFrom, effectiveUntil?)
pay_differentials(uuid, payRuleUuid→pay_rules, type, mode, value, scope,
                  windowStartLocal?, windowEndLocal?)
pay_overtime_rules(uuid, payRuleUuid→pay_rules, thresholdHours, period, multiplier)
import_sessions(id, uuid, sourceType, state, referenceDate, timezone,
                createdAt, rawExtractionJson, committedIdsJson)
import_candidates(uuid, sessionUuid→import_sessions, id, date, templateId,
                  startTime, endTime, shiftType, kind, confidence,
                  reviewStatus, note?)
schema_meta(version INTEGER)  ← migration bằng PRAGMA user_version, v1
```

Lý do tách child rows (sequence/differentials/overtime) thay vì JSON: query
version active, edit 1 differential, pattern sequence mutable theo version.

## 5. Repository API (lib/core/db/...)

```
JobRepo.save/list/delete
PatternRepo.saveTemplate, savePattern(+sequence), patternsActiveOn(date),
            loadAll
OccurrenceRepo.saveOccurrences(batch), loadRange(patternId?, from, to),
            byId, saveOverride(append-only), overridesFor(patternId, range)
PayRuleRepo.save(+children), activeRule(jobId, date), allFor(jobId)
ImportRepo.saveSession(+candidates), sessionById (audit), committedShiftsOf
```

**Bất biến repo**: mọi thao tác ghi đi qua 1 transaction; ghi quá khứ chỉ qua
`saveOverride`; `actualPayEstimate` chỉ set 1 lần (immutable snapshot).

## 6. Materialized projection (kế hoạch, KHÔNG cache view ở Gate 3)

Renderer: `renderJobSchedule(jobId, from, to)` =
  load templates + patterns active → `projectOccurrences` (pure engine)
  → load overrides → `applyOverride` chain (atomic, 1 transaction) →
  persist occurrences row (cho UI query) VÀ override log. Tính incremental:
  chỉ render từ `max(committed mtime)` — ghi backlog nếu cần cache view.

## 7. Test (test/core/db/)

- Migration: open v1 → user_version=1; re-open không re-run.
- Round-trip từng repo (save → load → khớp core object, INVARIANT-001).
- Versioned active lookup theo date (PayRule v1/v2 = PAY-011 tái hiện qua DB).
- Import session persist → audit query candidateForOccurrenceId.
- INVARIANT-006: occurrence snapshot estimate không đổi sau khi rule bump v2.
- Engine↔DB parity: schedule render qua DB == kết quả pure engine (không DB).

## 8. Không làm ở Gate 3 (backlog rõ ràng)

CalendarEvent/TimeOff (model chưa code) · SQLCipher native build (seam sẵn) ·
backup/restore · soft-delete materialized view · drift ORM (nếu sau này UI cần
reactive, migration độc lập vì schema là SQLite chuẩn).

## 9. Định nghĩa xong (agent phải nộp)

1. Diff/summary từng file + migration v1 SQL.
2. `dart test test/core/` log trước/sau (không phá 135 hiện tại).
3. Bảng test mới → mapping INVARIANT/AC.
4. `features.md` cập nhật: Persistence ✅ kèm bằng chứng; CI job `persistence-tests`.
