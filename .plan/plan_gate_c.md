# plan_gate_c.md — ShiftEase Gate C: Data Integrity & Minimum Release Hardening

> **Trạng thái:** CHỐT — sẵn sàng cho agent code implement.
> **Đầu vào:** `result14_gate_a.txt` + `handoff_20260906_144500.md` + `plan5.md` + reviews + verify source (`import_engine.dart`, `schedule_service.dart`, repos).
> **Phạm vi:** Data integrity P1 còn sót + product minimum đủ internal/closed testing.
> **NGHIÊM CẤM:** OCR, Cloud, Widgets, Wellness, Partner sharing nâng cao, full payroll product, đổi kiến trúc Gate 0 Time/Pattern.
> **Báo cáo bắt buộc:** `result15_gate_c.txt` tồn tại trên đĩa + docs đồng bộ.

---

## 0. Verdict & mục tiêu

Gate A/B đã đạt wiring, atomic import commit, window OFF, SWAP `effectiveJobId`, version immutability cơ bản (179/179 pass). Review độc lập (`plan5.md`) vẫn phát hiện **P1 data integrity** mà test chưa bắt:

1. `EXTRACTED → COMMIT` vẫn được phép trong `commitImport`
2. `changeRosterFrom()` hai `savePattern` không chung transaction → rủi ro mất roster
3. Override / session history có đường silent ignore hoặc overwrite

**Mục tiêu Gate C:**

- Khóa integrity ở core boundary (không phụ thuộc UI)
- Bổ sung tối thiểu: DST dialog, Pay/Income usable, ICS offline, notification ca, platform baseline
- Adversarial tests + documentation truth
- **Sau Gate C mới** mở M3 polish / M2b / TestFlight

---

## 1. Phần A — Data Integrity (P1 bắt buộc)

### A1. Import state machine — chỉ REVIEWING → COMMIT

**File:** `lib/core/import/import_engine.dart` — `commitImport`

**Hiện trạng (đã xác nhận source):**

```dart
if (session.state != ImportState.reviewing &&
    session.state != ImportState.extracted) {
  // reject
}
```

→ Vẫn cho `EXTRACTED → COMMIT` (bypass Review / INVARIANT-004).

**Spec sửa:**

```dart
if (session.state != ImportState.reviewing) {
  return CommitResult(
    session: session.copyWith(
      state: ImportState.error,
      history: [...session.history, ImportState.error],
      error: ImportError(
        code: ImportErrorCodes.illegalState,
        message: 'Commit requires a REVIEWING session. '
            'Call applyReview before commit (EXTRACTED is not enough).',
        recoverable: true,
      ),
    ),
    error: /* same */,
  );
}
```

**Quy tắc:**

| From state   | commitImport |
|--------------|--------------|
| `extracted`  | **REJECT**   |
| `reviewing`  | allowed (nếu có approved/modified) |
| `committed`  | REJECT       |
| `error`/`idle` | REJECT     |

**Test bắt buộc:**

- `EXTRACTED` + candidates approved → `commitImport` → FAIL, không ghi occurrence, state không thành committed
- `REVIEWING` + approved → commit OK (regression)
- `REVIEWING` + zero approved → fail rõ (giữ hành vi hiện tại nếu đã có)

---

### A2. Atomic `changeRosterFrom`

**File:** `lib/domain/schedule_service.dart` (~338–356)

**Hiện trạng:**

```dart
_patterns.savePattern(jobId: closed.jobId, pattern: closed, templates: const []);
_patterns.savePattern(jobId: next.jobId, pattern: next, templates: templates);
```

Hai transaction riêng → fail bước 2 = old CLOSED, new không tồn tại → **mất roster**.

**Spec sửa:**

- Mở một `db.transaction()` (cùng connection production).
- Trong transaction:
  1. `savePattern(closed)` (D9 close: chỉ `effectiveUntil` null→date khi đúng case)
  2. `savePattern(next)` với templates
- Fail bất kỳ bước → ROLLBACK toàn bộ.
- Nếu repository `savePattern` tự BEGIN: thêm biến thể `savePatternInTransaction` (giống pattern Gate A với `replaceImportedOccurrencesInTransaction`) — **caller owns txn**, không nested BEGIN.

**Giữ nguyên:**

- `createNewVersion` pure (anchorDate bất biến, phase continuity D9)
- A6: same id + identical payload idempotent; different payload → StateError; close một lần null→date

**Test bắt buộc:**

- Happy path: old `effectiveUntil` set, new active, render sau `newEffectiveFrom` dùng sequence mới
- Simulate fail ở insert new (mock/throw sau close) → old **không** bị closed (hoặc rollback về trạng thái trước)
- D9 phase continuity regression vẫn pass

---

### A3. Override immutability (không silent-ignore)

**File:** `lib/core/db/schedule_repository.dart` — `saveOverride`

**Spec:**

```
same id + deep-equal payload  → idempotent OK (no-op success)
same id + different payload   → throw ImmutableHistoryError / StateError
  (KHÔNG return im lặng, KHÔNG overwrite)
id chưa tồn tại               → insert append-only
```

Deep equality tối thiểu: `id`, `operation`, target occurrence ids, `templateId`, times, `shiftDate`, `reason`, split parts nếu có.

**Test:**

- Insert override → save lại identical → OK, đúng 1 row
- Save lại same id, đổi startTime → exception, DB không đổi

---

### A4. ImportSession COMMITTED immutable

**File:** `lib/core/db/business_repository.dart` (hoặc ImportRepository) — `saveSession`

**Spec:**

| State hiện tại trong DB | saveSession mới |
|-------------------------|-----------------|
| `extracted` / `reviewing` | Cho phép update hợp lệ (candidates, review, history) |
| `committed` | **CẤM** mọi thay đổi field (state, raw, candidates, window, offDates, committedIds…) → throw |
| identical full payload committed | Idempotent OK (optional) |

Không dùng `ON CONFLICT DO UPDATE` vô điều kiện cho session đã committed.

**Test:**

- Commit session → saveSession lại với raw/candidates đổi → FAIL
- Reviewing → update review decisions → OK

---

### A5. Adversarial tests (bắt buộc)

| ID | Scenario | Kỳ vọng |
|----|----------|--------|
| ADV-1 | EXTRACTED → commit | FAIL |
| ADV-2 | changeRosterFrom fail bước 2 | old không CLOSED mồ côi |
| ADV-3 | override same id, different payload | exception |
| ADV-4 | override same id, same payload | idempotent |
| ADV-5 | session COMMITTED overwrite | exception |
| ADV-6 | Full suite Gate 0–A regression | 100% pass |

---

## 2. Phần B — Minimum product (làm cùng Gate C)

Chỉ mức **tối thiểu usable** — không phình M3/M4 đầy đủ.

### B1. DST dialog UI

**Engine sẵn:** `NONEXISTENT_LOCAL_TIME`, `AMBIGUOUS_LOCAL_TIME` (+ options).

**UI requirements:**

- Khi add/edit/import/render surface issue DST:
  - **Nonexistent:** message rõ (ví dụ clocks jump forward) + bắt user chọn giờ khác — **không** auto-round
  - **Ambiguous:** hiện 2 candidates (local + UTC/offset) → user chọn 1 → resolve với candidate đó
- Hủy dialog → không ghi occurrence sai; issue vẫn có trong `ScheduleRenderResult.issues` nếu liên quan render
- Copy tiếng Anh kỹ thuật OK; có thể thêm tiếng Việt sau

**Files gợi ý:** widget/dialog trong `features/` (occurrence sheet, import review, hoặc shared `features/common/dst_resolution_dialog.dart`)

---

### B2. Pay / Income tối thiểu

**Dùng** `core/money` đã có (Gate 1).

**Bắt buộc có:**

1. **Income view** (Today section hoặc màn riêng):
   - Range tuần hiện tại (hoặc tháng) theo job đang chọn
   - Breakdown: Regular + differentials (Night/Weekend/…) + OT
   - Tổng
   - Nhãn cố định mọi chỗ hiện tiền: **`Ước tính — không phải bảng lương chính thức`**

2. **Pay Rule editor cơ bản** gắn Job:
   - `baseHourlyRate`
   - Night differential (percent hoặc flat)
   - Weekend differential (percent hoặc flat)
   - Một OT rule đơn giản (ví dụ threshold 40h / week × 1.5)
   - Lưu versioned nếu engine/repo đã hỗ trợ `effectiveFrom`

3. **Thiếu config:** không đoán số → hiện “Unable to calculate accurately” + lý do (thiếu rate, thiếu work week, …)

**Không làm trong Gate C:** template library đa quốc gia đầy đủ, hazard/callback phức tạp, tax/net pay, full M3b polish.

---

### B3. ICS export offline

- Action: Export range (tuần/tháng/job) → file `.ics`
- Offline-only, không server, không Webcal dynamic
- Mỗi occurrence resolved → VEVENT (DTSTART/DTEND UTC hoặc local với TZID nếu làm được đúng)
- Share qua hệ thống (share sheet) hoặc lưu file (`path_provider`)

---

### B4. Notification ca sắp tới

- Local notification trước giờ bắt đầu ca (mặc định 60 phút; có thể hardcode hoặc setting tối thiểu)
- Schedule lại khi render/commit/override đổi ca sắp tới
- Không commute, không server
- Permission flow cơ bản (iOS/Android)

---

### B5. Platform baseline

- Đảm bảo project generate/build được `android/` và `ios/` (Flutter)
- `path_provider` (và dependency notification nếu cần) trong `pubspec.yaml`
- `flutter build apk` hoặc `flutter build ios --no-codesign` không fail vì thiếu folder (trong môi trường agent cho phép)
- **Không** bắt buộc SQLCipher + Keychain production trong Gate C (backlog). Nếu còn `PRAGMA key` giả trên plain SQLite: ghi chú rõ trong code/docs là **dev-only**, không claim “encrypted at rest”

---

## 3. Quyết định khóa (D-C)

| ID | Quyết định |
|----|------------|
| D-C1 | Chỉ `REVIEWING → COMMIT`; `EXTRACTED → COMMIT` = illegal |
| D-C2 | `changeRosterFrom` = đúng 1 DB transaction |
| D-C3 | Override: identical payload = idempotent; different = immutable error |
| D-C4 | Session `COMMITTED` = immutable |
| D-C5 | DST: user chọn candidate / đổi giờ — engine không auto-pick |
| D-C6 | Mọi số tiền có nhãn “Ước tính — không phải bảng lương chính thức” |
| D-C7 | ICS offline-only |
| D-C8 | Không OCR, Cloud, Widgets, B2B, full payroll trong Gate C |

---

## 4. NEVER list

- NEVER cho phép `EXTRACTED → COMMIT`
- NEVER close pattern cũ mà không insert pattern mới trong cùng transaction
- NEVER silent-return khi override id trùng nhưng payload khác
- NEVER `ON CONFLICT DO UPDATE` session đã COMMITTED
- NEVER auto-select DST ambiguous/nonexistent
- NEVER hiện tiền không có nhãn ước tính
- NEVER thêm OCR / Cloud / Widgets trong task này
- NEVER tuyên bố `result15_gate_c.txt` khi file không tồn tại trên đĩa
- NEVER tự sửa golden expected cũ chỉ để xanh
- NEVER nested BEGIN transaction (Gate A lesson)

---

## 5. Acceptance Criteria

### Integrity

- [ ] AC-C1: `commitImport` từ EXTRACTED fail; REVIEWING + approved thành công
- [ ] AC-C2: `changeRosterFrom` atomic; fail giữa chừng không để roster mồ côi
- [ ] AC-C3: override same-id different payload → error; identical → idempotent
- [ ] AC-C4: session COMMITTED overwrite → error
- [ ] AC-C5: ADV-1..ADV-6 pass; full suite 0 regression Gate 0–A

### Product minimum

- [ ] AC-C6: DST dialog NONEXISTENT + AMBIGUOUS
- [ ] AC-C7: Income breakdown + nhãn ước tính; Pay Rule cơ bản gắn job
- [ ] AC-C8: Export `.ics` offline OK
- [ ] AC-C9: Local notification trước ca (baseline)
- [ ] AC-C10: android/ios baseline + path_provider; analyze clean

### Docs

- [ ] AC-C11: `result15_gate_c.txt` tồn tại (`ls` xác nhận)
- [ ] AC-C12: `checklist.md` / `features.md` / `next.md` đồng bộ test count + trạng thái Gate C
- [ ] AC-C13: `flutter analyze` clean; `flutter test` 100% pass

---

## 6. Thứ tự triển khai bắt buộc

```
1. A1 commitImport state gate + test
2. A2 changeRosterFrom transaction (+ savePatternInTransaction nếu cần) + test rollback
3. A3 saveOverride immutability + tests
4. A4 session COMMITTED immutable + test
5. A5 adversarial bundle + full suite regression
6. B1 DST dialog UI + widget test tối thiểu
7. B2 Pay/Income UI tối thiểu + test
8. B3 ICS export + test/smoke
9. B4 notification baseline
10. B5 platform / pubspec
11. result15_gate_c.txt + đồng bộ checklist / features / next
12. Báo cáo Gate C
```

Mỗi bước integrity: chạy nhóm test liên quan ngay — không chờ cuối (bài học Gate A: 8 fail giữa chừng).

---

## 7. File / module chạm tới (gợi ý)

| Khu vực | File |
|---------|------|
| Import state | `lib/core/import/import_engine.dart`, `import_types.dart` |
| Roster version | `lib/domain/schedule_service.dart`, `lib/core/db/pattern_repository.dart` |
| Override | `lib/core/db/schedule_repository.dart` |
| Session | `lib/core/db/business_repository.dart` |
| DST UI | `lib/features/.../dst_resolution_dialog.dart` (+ occurrence/import) |
| Pay UI | `lib/features/pay/` hoặc `today/` + money engine |
| ICS | `lib/features/export/ics_export.dart` |
| Notification | `lib/features/notifications/` hoặc domain scheduler |
| Composition | `lib/main.dart` nếu cần wire pay/export |
| Tests | `test/core/import/`, `test/core/db/`, `test/domain/`, `test/ui/` |
| Docs | `checklist.md`, `features.md`, `next.md`, `result15_gate_c.txt` |

---

## 8. Báo cáo agent phải nộp (`result15_gate_c.txt`)

1. Diff tóm tắt theo file
2. Log `flutter analyze` + `flutter test` (số test trước/sau)
3. Bảng AC-C1..C13 → test file / bằng chứng
4. Xác nhận riêng:
   - EXTRACTED commit fail
   - changeRosterFrom atomic + rollback
   - Override + Session immutability
   - DST / Income / ICS / Notification
5. `ls -la result15_gate_c.txt`
6. Docs đã đồng bộ (số test khớp 3 file)

**Gate C chỉ đóng khi human review chấp nhận báo cáo.**

Sau Gate C được duyệt mới được mở:

- M3 Pay Rules library / polish
- M2b CSV mapping + re-import diff UI
- Closed TestFlight
- M4.5 OCR spike (khi có 20–30 roster thật)

---

## 9. Out of scope (backlog — KHÔNG code trong Gate C)

- OCR / IMAGE / PDF import
- Cloud backup, Webcal dynamic, E2E encryption production
- Home screen widgets
- Wellness / recovery AI
- Partner overlay nâng cao, Availability Finder đầy đủ
- SPLIT/SWAP UI đầy đủ (engine đã có; UI có thể tối thiểu sau)
- SQLCipher + Keychain/Keystore production
- Template library đa quốc gia (US-CA, UK NHS, DE…) đầy đủ
- State management migration (Riverpod/Bloc) toàn app

---

## 10. Định nghĩa xong

Gate C **DONE** khi và chỉ khi:

1. Mọi AC-C1..C13 ✅
2. `result15_gate_c.txt` trên đĩa với bằng chứng chạy thật
3. Human review accept

Bắt đầu implement theo §6.
