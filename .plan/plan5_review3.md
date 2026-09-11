Agent đang code xong, bạn cần review đánh giá lại toàn bộ. Đọc những file sau để biết những gì đã thay đổi:

checklist.md
features.md
result*.txt (mới nhất)
next.md
/handoff*.md mới nhất

Xem tính năng đã code có lỗ hổng không như: sai logic, khi sử dụng có thể mất mát dữ liệu, crash bug...
Tính năng đã đầy đủ để xuất bản app chưa, nếu chưa gợi ý đầy đủ tính năng hữu ích một lần cuối để cho agent code một thể rồi review.

phân tích solution plan5.md và review của các AI khác plan5_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
Toàn bộ files+code của project tại /Users/hoang/htdocs_apps/ShiftEase .
--------------------
Worked for 1m 44s

**Review toàn bộ trạng thái ShiftEase (sau Gate A/B) + phân tích plan5.md & reviews**

Tôi đã đối chiếu source thật (lib/, test/), result14\_gate\_a.txt, handoff\_20260906\_144500.md, checklist.md, next.md, features.md, và các file plan5.

* * *

1\. Verdict tổng thể
--------------------

| Khối | Điểm | Nhận xét |
| --- | --- | --- |
| Core Time + Pattern (Gate 0) | **8.5–9/10** | Contract đã cứng, invariants tốt |
| Money engine | **~8/10** | Có test, nhưng UI chưa có |
| Import + DB (Gate 2–3 + A/B) | **7–7.5/10** | Wiring/atomic commit đã tốt hơn, vẫn còn lỗ hổng integrity |
| Domain + UI (M1/M1b/M2) | **6.5–7/10** | Luồng chính chạy được, còn thiếu production polish |
| Documentation integrity | **7/10** | Cải thiện sau Gate B, features.md vẫn lệch một số chỗ |
| **Production release readiness** | **~6.5–7/10** | **Chưa sẵn sàng xuất bản** |

**Kết luận:**  
Gate A/B đã sửa được nhiều lỗi wiring/transaction quan trọng và có bằng chứng 179/179 pass. Tuy nhiên **chưa đồng ý coi app production-ready**, và cũng **chưa đồng ý nhảy thẳng sang M3 Pay UI** trước khi đóng một batch data-integrity còn sót.

* * *

2\. Những gì Gate A/B đã làm đúng (xác nhận trên source)
--------------------------------------------------------

Từ result14 + code:

| AC | Trạng thái | Bằng chứng |
| --- | --- | --- |
| A1 Production composition (composeService) | ✅ | main.dart + composition test |
| A2 Import commit 1 transaction + rollback | ✅ | replaceImportedOccurrencesInTransaction |
| A3 Window + OFF \[\] không bị lọc | ✅ | per-day window semantics |
| A4 SWAP effectiveJobId | ✅ | pattern engine |
| A5 Pending warning + dialog | ✅ | import\_screen |
| A6 Version immutability Pattern/PayRule | ✅ | (có exception path) |
| Docs + result14 tồn tại | ✅ | filesystem xác nhận |

Đây là bước tiến thực sự so với lần review trước (M2 unreachable, nested transaction, query OFF sai).

* * *

3\. Lỗ hổng P1 còn lại (xác nhận trên code) — plan5.md đúng
-----------------------------------------------------------

### 🔴 P1-1 — EXTRACTED → COMMITTED vẫn được phép

Dart

CopyCopied

    // lib/core/import/import_engine.dart ~403
    if (session.state != ImportState.reviewing &&
        session.state != ImportState.extracted) {

Core vẫn cho commit từ EXTRACTED.  
UI có thể ép Review, nhưng **invariant phải được enforce ở engine**, không phụ thuộc UI.

**Cần:** chỉ cho REVIEWING → COMMIT.  
Thêm test: EXTRACTED + approved candidates → commit MUST FAIL.

### 🔴 P1-2 — changeRosterFrom() không atomic

Dart

CopyCopied

    // lib/domain/schedule_service.dart ~353-354
    _patterns.savePattern(... closed ...);
    _patterns.savePattern(... next ...);

Hai lệnh riêng. Nếu bước 2 fail → pattern cũ đã CLOSED, pattern mới không tồn tại → **mất roster**.

**Cần:** một transaction bao quanh close old + insert new; fail → rollback cả hai.

### 🔴 P1-3 — saveOverride() silent-ignore conflict ID

Theo plan5.md (và pattern tương tự các repo khác): cùng ID nhưng payload khác có thể bị return im lặng thay vì reject.

**Cần:**

*   same ID + identical payload → idempotent OK
*   same ID + different payload → ImmutableHistoryError (không silent)

### 🔴 P1-4 — ImportSession / history overwrite rủi ro

ON CONFLICT DO UPDATE trên session đã COMMITTED vẫn là rủi ro ghi đè lịch sử.  
Session committed phải **immutable**.

### 🟠 P1/P2 khác (từ plan5 + reviews)

*   Materialized occurrence cache có thể stale nếu không delete-before-insert trong window đúng cách.
*   Preset pattern (2-2-3…) cần audit lại toàn bộ.
*   features.md vẫn ghi một số trạng thái cũ (money “chưa code”, pattern UPDATE còn P3…) → documentation drift tiếp tục.

* * *

4\. Phân tích plan5.md + reviews
--------------------------------

| Nguồn | Đánh giá |
| --- | --- |
| **plan5.md** | Rất tốt — phát hiện đúng data-integrity bugs mà 179 test bỏ lỡ |
| **plan5\_review1** | Đồng thuận + giải pháp cụ thể, prompt hướng agent |
| **plan5\_review2** | Bổ sung idempotent override, session immutability theo state, adversarial tests |

**Tôi nhất trí gần như toàn bộ hướng plan5.**

Đặc biệt quan trọng:

1.  Chặn EXTRACTED → COMMIT ở core.
2.  Atomic changeRosterFrom.
3.  Override ID conflict → exception (idempotent nếu payload giống).
4.  Session COMMITTED immutable.
5.  Thêm adversarial / rollback tests.

**Phản biện nhẹ:**

*   Partial-commit (A5) đã có dialog — chấp nhận được nếu user explicit confirm. Không cần cấm tuyệt đối, nhưng core state machine vẫn phải qua REVIEWING.
*   Tách mobile/SQLCipher (R5) ra phase riêng là đúng — không gộp vào batch integrity này.
*   Không nên mở M3 Pay trước khi đóng batch integrity trên.

* * *

5\. App đã đủ để xuất bản chưa?
-------------------------------

**Chưa.**

### Đã có (đủ cho internal / TestFlight hẹp)

*   Time/Pattern/Money engines
*   Jobs, Templates, Pattern Builder
*   Calendar Week / Month / Today
*   Quick Add
*   Smart Paste Import + Review + Commit (sau Gate A)
*   Persistence SQLite + override log
*   Multi-job foundation

### Còn thiếu / còn rủi ro trước release công khai

| Hạng mục | Mức độ |
| --- | --- |
| Data integrity bugs (P1 trên) | **Chặn release** |
| Pay / Income UI | Quan trọng (trụ Money) |
| DST dialog UI | Quan trọng (engine sẵn, UI chưa) |
| SPLIT / SWAP UI | Nên có |
| ICS export offline | Nên có (offline-first story) |
| Notifications ca sắp tới | Nên có |
| Platform android/ios folders + path\_provider | Bắt buộc để build store |
| SQLCipher / encryption thật | Production security |
| CSV mapping UI + Re-import diff | Nice-to-have gần |
| OCR | Đúng là để sau (spike) |

* * *

6\. Đề xuất batch cuối trước khi mở M3 / hướng release
------------------------------------------------------

Tôi khuyên **một gate duy nhất** (gọi là **Gate C — Data Integrity & Release Hardening**), làm một thể rồi review, **không** nhảy M3 ngay.

### Gate C — bắt buộc (P1)

1.  **Import state machine**
    *   Chỉ REVIEWING → COMMIT
    *   Test: EXTRACTED → commit phải fail
2.  **Atomic changeRosterFrom**
    *   Một transaction: close old + insert new
    *   Test rollback khi bước 2 fail
3.  **Override immutability**
    *   same id + different payload → error
    *   same id + same payload → idempotent
4.  **ImportSession COMMITTED immutable**
    *   Không cho ON CONFLICT DO UPDATE ghi đè session đã commit
5.  **Adversarial tests**
    *   Rollback roster version
    *   Duplicate override
    *   Commit bypass
    *   Session overwrite attempt

### Gate C — nên làm cùng (product completeness tối thiểu)

6.  **DST dialog UI** (engine đã sẵn NONEXISTENT / AMBIGUOUS)
7.  **Pay / Income dashboard tối thiểu** (breakdown + nhãn “Ước tính…”) + Pay Rule editor cơ bản
8.  **ICS export offline** (1 file, không server)
9.  **Notification** ca sắp tới (local)
10.  **Platform folders** android/ios + path\_provider để build được

### Để sau (không chặn internal release)

*   CSV mapping UI, Re-import diff UI
*   OCR spike → OCR full
*   Widgets, Wellness, Cloud, Partner sharing nâng cao
*   SQLCipher production keychain (có thể song song)

* * *

7\. Thứ tự hành động đề xuất
----------------------------

text

CopyCopied

    1. Human accept Gate A/B (result14) — gần như OK, ghi nhận còn P1 integrity
    2. Gate C — Data Integrity + minimum product (prompt một lần)
    3. Review Gate C
    4. M3b polish Pay Rules / template library (nếu chưa đủ trong C)
    5. Internal TestFlight / closed testing
    6. M2b / M4 / OCR theo nhu cầu thật

**Không** mở M3 Pay UI lớn trước khi chặn được EXTRACTED→COMMIT và atomic roster versioning — vì đây là đường gây mất dữ liệu user.

* * *

8\. Kết luận
------------

*   **Gate A/B:** đạt mục tiêu wiring/atomic commit/window/SWAP/docs — chấp nhận được với điều kiện còn follow-up integrity.
*   **plan5.md:** đánh giá đúng, phát hiện P1 thực sự trên code.
*   **App:** core mạnh, UI đã có luồng chính, **chưa release-ready**.
*   **Bước tiếp theo tối ưu:** một **Gate C** gói data-integrity + vài tính năng tối thiểu (DST dialog, Pay dashboard cơ bản, ICS, notification, platform) → review một lần → rồi mới quyết định TestFlight / M3 mở rộng.

Bạn muốn tôi viết luôn **prompt chi tiết cho Gate C** (Data Integrity + minimum release features) để giao agent làm một thể không?
------
có
---
Dưới đây là **prompt chi tiết, sẵn sàng copy-paste** cho AI coding agent thực hiện **Gate C — Data Integrity & Minimum Release Hardening**.

---

```markdown
# TASK: ShiftEase — Gate C: Data Integrity & Minimum Release Hardening

## 1. Mục tiêu tuyệt đối

Đóng các lỗ hổng **data integrity** còn sót sau Gate A/B, đồng thời bổ sung **tối thiểu** các tính năng cần thiết để app có thể đưa vào internal / closed testing — **trước khi** mở rộng M3 Pay UI lớn hoặc OCR.

Sau Gate C:
- Không còn đường commit import bypass Review.
- `changeRosterFrom` atomic (không mất roster khi fail giữa chừng).
- Override / ImportSession history không bị silent overwrite.
- Có DST dialog UI, Pay/Income tối thiểu, ICS export offline, notification ca sắp tới, platform folders đủ build.
- Test adversarial phủ các failure scenario trên.
- Documentation (`checklist.md`, `features.md`, `next.md`, result report) khớp filesystem + test count.

**NGHIÊM CẤM:**
- OCR / Cloud / Widgets / Wellness / Partner sharing nâng cao
- Tự mở rộng Pay thành “full payroll product”
- Đổi kiến trúc core Time/Pattern đã khóa ở Gate 0
- Silent “fix” bằng cách nới invariant

---

## 2. Phần A — Data Integrity (P1 bắt buộc)

### A1. Import state machine — chặn EXTRACTED → COMMIT

**Hiện trạng (xác nhận code):**
```dart
if (session.state != ImportState.reviewing &&
    session.state != ImportState.extracted) { ... }
```
→ Vẫn cho `EXTRACTED → COMMIT` (bypass Review).

**Yêu cầu:**
- Chỉ cho phép `REVIEWING → COMMIT`.
- `EXTRACTED → COMMIT` → fail rõ ràng (`illegalState` hoặc mã tương đương), không ghi occurrence.
- UI vẫn phải đi qua Review; core **enforce** invariant, không phụ thuộc UI.

**Test bắt buộc:**
```
EXTRACTED + có candidate approved → commitImport → MUST FAIL
REVIEWING + approved → commit OK (regression)
```

### A2. Atomic `changeRosterFrom`

**Hiện trạng:**
```dart
_patterns.savePattern(... closed ...);
_patterns.savePattern(... next ...);
```
Hai lệnh riêng → fail bước 2 = pattern cũ CLOSED, pattern mới không tồn tại → mất roster.

**Yêu cầu:**
- Một transaction duy nhất: close old + insert new.
- Fail bất kỳ bước nào → ROLLBACK cả hai.
- Giữ nguyên semantics D9 (anchorDate bất biến, phase continuity).

**Test bắt buộc:**
- Happy path: old closed + new active.
- Simulate fail ở insert new → old vẫn OPEN (hoặc trạng thái trước đó), không để roster “mồ côi”.

### A3. Override immutability (không silent-ignore)

**Yêu cầu:**
- `saveOverride`:
  - same `id` + **identical payload** → idempotent OK (return success, không nhân bản).
  - same `id` + **different payload** → ném lỗi rõ (`ImmutableHistoryError` / `StateError`), **không** ghi đè, **không** silent return.
- Deep equality đủ field semantics (operation, target ids, times, template, reason…).

**Test bắt buộc:**
- Duplicate identical → OK, 1 record.
- Duplicate different payload → exception, data không đổi.

### A4. ImportSession COMMITTED immutable

**Yêu cầu:**
- Session đã `COMMITTED` không được `ON CONFLICT DO UPDATE` ghi đè state/raw/candidates/window/offDates/…
- Attempt update session committed + payload khác → exception.
- Session `EXTRACTED` / `REVIEWING` vẫn cho phép update hợp lệ (review decisions, candidates).

**Test bắt buộc:**
- saveSession lại session COMMITTED với thay đổi → FAIL.
- Reviewing update candidates → OK.

### A5. Adversarial / integrity tests (bắt buộc thêm)

1. `EXTRACTED → commit` fail.
2. `changeRosterFrom` rollback khi bước 2 fail.
3. Override same-id different payload → error.
4. Override same-id same payload → idempotent.
5. Session COMMITTED overwrite attempt → error.
6. Regression: Gate 0 Time/Pattern + Gate A window/SWAP/atomic import commit vẫn pass.

---

## 3. Phần B — Minimum product completeness (làm cùng Gate C)

Chỉ làm **mức tối thiểu** đủ dùng, không phình scope.

### B1. DST dialog UI (A10)

Engine đã trả `NONEXISTENT_LOCAL_TIME` / `AMBIGUOUS_LOCAL_TIME`.

**Yêu cầu UI:**
- Khi render/add/edit gặp issue loại này → dialog rõ ràng.
- Ambiguous: hiện 2 options (kèm offset/UTC) → user chọn 1.
- Nonexistent: giải thích + yêu cầu chọn giờ khác (không tự làm tròn).
- Không silent drop; issue vẫn vào `ScheduleRenderResult.issues` nếu user hủy.

### B2. Pay / Income tối thiểu (M3 skeleton usable)

Không làm full editor phức tạp ngay, nhưng phải có:

- **Income dashboard** (Today hoặc tab riêng):
  - Tổng ước tính theo tuần/tháng đang xem
  - Breakdown: Regular + Night/Weekend/… + OT
  - Nhãn bắt buộc: **“Ước tính — không phải bảng lương chính thức”**
- **Pay Rule gắn Job** (create/edit cơ bản):
  - base hourly rate
  - ít nhất Night + Weekend differential (percent hoặc flat)
  - 1 overtime rule đơn giản (ví dụ sau 40h/tuần × 1.5)
- Dùng engine Gate 1 đã có; versioned theo `effectiveFrom` nếu đã hỗ trợ.
- Thiếu config → hiện lý do cụ thể (“Unable to calculate…”), không đoán số.

### B3. ICS export offline

- Export lịch job (hoặc range) ra file `.ics`.
- Hoạt động offline, không server.
- Đủ để user share/subscribe thủ công qua Files / Calendar app.

### B4. Notification ca sắp tới

- Local notification trước giờ bắt đầu ca (ví dụ 1h / 30m — cấu hình tối thiểu OK).
- Không cần commute intelligence, không cần server.

### B5. Platform build baseline

- Đảm bảo có cấu trúc android/ / ios/ (hoặc generate đúng) + `path_provider` (hoặc tương đương) đủ để build debug/release nội bộ.
- Không bắt buộc SQLCipher production keychain trong Gate C (có thể backlog), nhưng **không** để `PRAGMA key` giả tạo cảm giác đã mã hóa nếu thực tế chưa.

---

## 4. Quyết định đã khóa

| ID | Quyết định |
|----|------------|
| D-C1 | Chỉ `REVIEWING → COMMIT`; `EXTRACTED → COMMIT` = illegal |
| D-C2 | `changeRosterFrom` = 1 transaction |
| D-C3 | Override: identical = idempotent; different = immutable error |
| D-C4 | Session `COMMITTED` = immutable |
| D-C5 | DST: user chọn / sửa giờ — engine không auto-pick |
| D-C6 | Mọi số tiền có nhãn “Ước tính — không phải bảng lương chính thức” |
| D-C7 | ICS offline-only trong Gate C |
| D-C8 | Không OCR, không Cloud, không B2B trong Gate C |

---

## 5. Acceptance Criteria (Gate C xanh khi TẤT CẢ đạt)

**Integrity**
- [ ] `commitImport` từ `EXTRACTED` fail; chỉ `REVIEWING` thành công.
- [ ] `changeRosterFrom` atomic; fail giữa chừng không để pattern CLOSED mồ côi.
- [ ] Override same-id different payload → error; identical → idempotent.
- [ ] Session COMMITTED không bị overwrite.
- [ ] Có adversarial tests cho các case trên; full suite pass; 0 regression Gate 0–A.

**Product minimum**
- [ ] DST dialog UI hoạt động cho NONEXISTENT + AMBIGUOUS.
- [ ] Income view + breakdown + nhãn ước tính; Pay Rule cơ bản gắn job.
- [ ] Export `.ics` offline thành công.
- [ ] Local notification trước ca (cấu hình tối thiểu).
- [ ] Project build được trên target mobile (android/ios baseline).

**Docs**
- [ ] `result15_gate_c.txt` (hoặc tên tương ứng) tồn tại trên disk.
- [ ] `checklist.md` / `features.md` / `next.md` đồng bộ test count + trạng thái thật.
- [ ] `flutter analyze` clean; `flutter test` 100% pass.

---

## 6. NEVER List

- NEVER cho `EXTRACTED → COMMIT`.
- NEVER close pattern cũ mà không insert pattern mới trong cùng transaction.
- NEVER silent-ignore override ID conflict.
- NEVER update session đã COMMITTED.
- NEVER auto-select DST ambiguous candidate.
- NEVER hiện số tiền không có nhãn “Ước tính…”.
- NEVER thêm OCR/Cloud/Widgets trong task này.
- NEVER tuyên bố report tồn tại khi filesystem không có file.
- NEVER tự sửa golden expected cũ chỉ để xanh.

---

## 7. Thứ tự triển khai gợi ý

1. A1–A4 integrity (core/domain/db) + tests adversarial  
2. Chạy full suite — sửa regression  
3. B1 DST dialog  
4. B2 Pay/Income tối thiểu  
5. B3 ICS + B4 Notification  
6. B5 platform baseline  
7. Cập nhật docs + `result15_gate_c.txt`  
8. Báo cáo Gate C

---

## 8. Định nghĩa “xong” — Báo cáo agent phải nộp

1. Diff tóm tắt theo file (import_engine, schedule_service, schedule_repository, business_repository, UI DST/Pay/ICS/notification, main/platform…).
2. Log `flutter analyze` + `flutter test` (số test trước/sau).
3. Bảng ánh xạ từng AC → test file / bằng chứng.
4. Xác nhận:
   - EXTRACTED commit fail
   - changeRosterFrom atomic + rollback
   - Override + Session immutability
   - DST dialog / Income / ICS / Notification hoạt động
5. `ls` xác nhận result report trên disk.
6. Docs đã đồng bộ.

**Gate C chỉ đóng khi human review chấp nhận báo cáo này.**  
Sau Gate C mới được mở: M3 Pay polish mở rộng, M2b CSV/diff, hoặc closed TestFlight.

Bắt đầu làm việc.
```

---

Prompt đã khóa integrity P1 + product minimum, có acceptance criteria, adversarial tests và NEVER list. Bạn có thể copy giao agent.

Cần siết thêm (ví dụ bắt buộc SQLCipher, hoặc bỏ notification khỏi Gate C để scope nhỏ hơn) thì nói rõ để chỉnh.