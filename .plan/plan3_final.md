# plan3_final.md — ShiftEase Core Contract Hardening (Gate 0)

> **Trạng thái:** CHỐT — sẵn sàng cho agent code implement.
> **Đầu vào:** `plan3.md` (review chiến lược) + `plan3_review1.md` … `plan3_review4.md` (4 phản biện của AI khác) + **verify trực tiếp trên source thật** (`lib/core/time/*`, `lib/core/pattern/*`) + probe thực nghiệm bằng `timezone 0.9.4` (evidence trong §1).
> **Phạm vi:** CHỈ `core/time`, `core/pattern`, override pipeline, effective-schedule renderer, golden/unit/property/integration tests, `.plan/features.md` (cập nhật trạng thái).
> **NGHIÊM CẤM đụng:** `core/money`, UI, persistence/DB, import/OCR, notification, PayContext, ID-UUID layer.
> **Quy ước dấu:** file này dùng tiếng Việt có dấu; mã/định danh giữ nguyên tiếng Anh.

---

## 0. Verdict tổng hợp (5/5 nguồn đồng thuận)

**DỪNG — KHÔNG chuyển sang `core/money` lúc này.** Toàn bộ `plan3.md` + 4 review đều hội tụ về một kết luận: Pattern/Time đang chứa lỗi domain nền móng (UTC rỗng, silent drop, UPDATE bỏ qua time, DST ±1h). Xây Money/UI trên nền này = technical debt đắt nhất có thể. Tôi (Buffy) đã verify từng claim trên code thật — **đa số đúng, một số cần đính chính, và có 3 phát hiện mới chưa nguồn nào nêu** (§2, §3).

**Verdict này KHÔNG thay đổi thứ tự milestone ở `plan1_final_v2.md`/`plan2.md`** (chúng vốn đã đặt core/time → core/pattern → core/money). Nó chỉ thêm một **gate chất lượng (Gate 0)** giữa Bước 3 (pattern) và Bước 4 (money): *không mở money cho tới khi contract dưới được khóa và có test phủ âm tính*.

---

## 1. Bằng chứng verify (đã chạy trong sandbox, không phải suy luận)

| # | Bằng chứng | Kết quả |
|---|---|---|
| E1 | `dart test test/core/` | `00:01 +55: All tests passed!` — 55 test hiện tại đều xanh, **nhưng không phủ các lỗi P0 dưới đây** (đúng như plan3.md cảnh báo: "test pass ≠ logic đúng") |
| E2 | Đọc `pattern_engine.dart` | `_applyCreate()` gán `startDateTimeUtc: ''`, `endDateTimeUtc: ''`, `timezone: ''` — **CONFIRMED** |
| E3 | Đọc `pattern_engine.dart` | `_applySplit()` tạo part với `startDateTimeUtc: ''`, `endDateTimeUtc: ''` — **CONFIRMED** (nhưng `timezone: occ.timezone` — review1/2/3 nói "timezone cũng rỗng" là **sai**, chỉ UTC rỗng) |
| E4 | Đọc `pattern_engine.dart` | `_applyUpdate()` chỉ `copyWith(templateId:)`, bỏ `startTime/endTime` — **CONFIRMED** |
| E5 | Đọc `pattern_engine.dart` | `_applyReplace()` chỉ `copyWith(templateId:)`; comment "UTC resolution handled by caller" nhưng **caller duy nhất (renderEffectiveSchedule) không resolve** — **CONFIRMED** |
| E6 | Đọc `pattern_engine.dart` | `renderEffectiveSchedule()` dùng `.where((r) => r.isSuccess)` → lỗi DST/MISSING_TEMPLATE **bị vứt im lặng** — **CONFIRMED**, mâu thuẫn trực tiếp NEVER list |
| E7 | Đọc `pattern_engine.dart` | `_applySwap()` **copy thẳng `startDateTimeUtc/endDateTimeUtc/timezone`** từ A sang B — **CONFIRMED**; và copy `timezone` vi phạm INVARIANT-007 (timezone cố định lúc tạo) |
| E8 | Đọc `time_engine.dart` | `resolveUtcInstant()`: `utc2 = utc1.add(Duration(hours: offset.inHours > alternativeOffset.inHours ? 1 : -1))` — **CONFIRMED ±1h + dùng `inHours` mất precision** |
| E9 | Probe Dart (chạy thật) | `DateTime.parse('2026-02-31')` → **`2026-03-03` (silent rollover, KHÔNG lỗi)**; `parse('...T10:90:00')` → `11:30` — **phát hiện mới M1** |
| E10 | Probe `timezone 0.9.4` (chạy thật) | Thuật toán enumerate candidate-offset (spec §5.1): NY 2026-11-01 01:30 → **2 candidates cách 60 phút**; NY 2026-03-08 02:30 → **0 candidates (gap)**; NY 10:00 ngày thường → **1 candidate**; Berlin 2026-10-25 02:30 → **2 candidates cách 60 phút**; **Lord Howe 2026-04-05 01:45 → 2 candidates cách ĐÚNG 30 phút** (`2026-04-04T14:45:00Z` và `2026-04-04T15:15:00Z`) — chứng minh code ±1h hiện tại **sai cho zone DST 30 phút** |
| E11 | Đọc `location.dart` (timezone pkg) | API công khai: `Location.zones` (`TimeZone.offset` — **milliseconds**), `Location.lookupTimeZone(ms)` → `TzInstant{timeZone, start, end}` — đủ để implement thuật toán E10 **không cần ±1h** |
| E12 | Grep toàn repo | `applyOverride()` được gọi ở `pattern_engine.dart:353` (internal) + **14 chỗ trong test** (`pattern_engine_test` ×10, `property` ×3, `integration` ×1) — đổi signature phải cập nhật đồng bộ |

---

## 2. Lỗi P0 đã xác nhận (bắt buộc sửa trong Gate 0)

> Thứ tự theo mức độ nguy hiểm với downstream. Mỗi lỗi ghi rõ nơi sửa — agent không được tự mở rộng phạm vi.

| ID | Lỗi | Vị trí | Hệ quả |
|---|---|---|---|
| P0-1 | **CREATE tạo occurrence với UTC/timezone rỗng** — object "temporal identity rỗng" tồn tại trong domain | `_applyCreate()` pattern_engine.dart | Money/Calendar nhận object rỗng → tự đoán/crash; vi phạm Correctness Contract |
| P0-2 | **SPLIT tạo part UTC rỗng** | `_applySplit()` | Part split không có temporal identity; duration 0 |
| P0-3 | **UPDATE bỏ qua `startTime/endTime`** — silent no-op, UI có thể báo "Saved" nhưng giờ không đổi | `_applyUpdate()` | Bug kiểu "im lặng đổi sai" nguy hiểm nhất cho production trust |
| P0-4 | **REPLACE bỏ qua `overrideTime`** | `_applyReplace()` | Day→Night có giờ mới không được áp dụng |
| P0-5 | **`renderEffectiveSchedule` silent-drop error** — `.where(isSuccess)` vứt DST/MISSING_TEMPLATE, mâu thuẫn NEVER list ngay trong cùng file | `renderEffectiveSchedule()` | Ngày nhảy giờ hiển thị trống trơn, không giải thích |
| P0-6 | **DST resolver dùng ±1h + `offset.inHours`** | `resolveUtcInstant()` time_engine.dart | Sai cho Lord Howe (30′); `inHours` bỏ precision (+10:30 → 10) |
| P0-7 | **SWAP copy cứng UTC + timezone** | `_applySwap()` | Sai semantics; copy timezone vi phạm INVARIANT-007 |
| P0-8 | **Không phân biệt invalid input vs DST error** | `resolveUtcInstant()` + `resolveShift()` | UX không thể phân biệt "nhập sai" với "giờ không tồn tại do DST" |

---

## 3. Phát hiện mới của vòng này (chưa nguồn review nào nêu — evidence E9–E11)

### M1 — Dart silent rollover ngày/giờ sai (NGHIÊM TRỌNG hơn plan3.md tưởng)
`DateTime.parse('2026-02-31')` trả về **2026-03-03**, không throw. `tz.TZDateTime` cũng roll (do `DateTime.utc` roll). Hệ quả trong code hiện tại:
- `projectOccurrences()` parse `pattern.anchorDate`/`rangeStart` → ngày sai **lệch lịch âm thầm** (không phải "bị đẩy vào NONEXISTENT" như plan3.md §10 đoán — tệ hơn: nó resolve thành **ngày khác đúng quy tắc**);
- `resolveUtcInstant` với minute=90 → roll thành giờ sau.
→ **Bắt buộc validate strict round-trip TRƯỚC mọi phép tính tz** (spec §5.1 step 0). Đây là lý do chính để error code `INVALID_DATE`/`INVALID_TIME` tồn tại như thực thể riêng, không phải cosmetic.

### M2 — END_BEFORE_START chưa được kiểm tra
`resolveShift()` không so sánh `utcEnd <= utcStart` sau khi resolve. Ca `07:00→07:00` (không có `+1`) hiện resolve thành duration 0 âm thầm. Thêm check trên **UTC đã resolve** (không phải local subtraction — INVARIANT-002).

### M3 — ID trùng lặp không được phát hiện
`_generateId = patternId_date_templateId` — nếu cùng ngày có 2 occurrence cùng template (SPLIT tạo `{id}_split_i` không trùng, nhưng CREATE dùng `override.id`; hoặc 2 occurrence baseline cùng ngày/cùng template khi pattern có template lặp trong cycle + offset ngày), id trùng → override `occurrenceId` trỏ nhầm. Cần: engine phát hiện id trùng trong một schedule view và trả `RenderIssue(code: DUPLICATE_OCCURRENCE_ID)` thay vì để silent.

### M4 — Provenance (source tagging) sai cho SPLIT/SWAP/chuỗi override (kế thừa P1 từ review vòng trước)
`renderEffectiveSchedule()` suy `source` bằng cách đoán membership qua `overrideIds`/`createdIds`. Part của SPLIT (`{id}_split_i`) và occurrence bị SWAP không nằm trong 2 set đó → bị gắn nhãn `baseline` dù thực chất do override tạo/sửa. Fix theo D4 (§4.4): tagging **tại thời điểm áp override**, không đoán lại ở renderer.

---

## 4. Quyết định thiết kế khóa (D-series — agent KHÔNG được tự đổi)

> Kế thừa D1–D8 của `plan1_final_v2.md` §10. Mục này chỉ **khóa thêm** những gì plan3/reviews để ngỏ hoặc đề xuất khác nhau. Nơi tôi phản biện review, ghi rõ lý do.

### D1 — Temporal Identity: "Resolved-only domain"
Mọi `ShiftOccurrence` tồn tại trong domain **bắt buộc** có `startDateTimeUtc`/`endDateTimeUtc`/`timezone` hợp lệ. Thứ không resolve được chỉ tồn tại dưới dạng `RenderIssue` — **không bao giờ** thành object occurrence rỗng.
→ Sửa tận gốc: `applyOverride` phải nhận đủ context để resolve (D3), vì root cause của UTC rỗng là **API thiếu context** chứ không phải agent quên gán.

### D2 — Override = Command Pipeline (nhất trí 5/5 nguồn)
```
OverrideCommand
  → Validate payload (format, range, required fields)        // INVALID_* trước
  → Xác định local civil time + timezone (bảng D3)
  → TimeZoneResolver → 0/1/2 candidate UTC instants (thuật toán §5.1, KHÔNG ±1h)
  → 0 candidate → Issue NONEXISTENT_LOCAL_TIME (không tạo occurrence)
  → 2 candidate → Issue AMBIGUOUS_LOCAL_TIME kèm 2 options (không tự chọn — D4 cũ)
  → 1 candidate → check END_BEFORE_START → tạo occurrence immutable + tag provenance
```

### D3 — Nguồn local time + timezone cho từng operation (chốt, đóng góp bổ sung cho review2 §2.1)
| Operation | Local time nguồn | Timezone nguồn |
|---|---|---|
| CREATE | `CreatePayload.startTime/endTime` (bắt buộc) | `CreatePayload.timezone` (**thêm field mới** — bắt buộc, vì CREATE không có occurrence gốc để suy) |
| UPDATE | `UpdatePayload.startTime/endTime` **optional nhưng ≥1 field trong {templateId, startTime, endTime} phải có** (validate); field vắng = giữ giá trị hiện tại — giờ hiện tại **suy từ UTC đã lưu của occurrence qua timezone của nó**, không đoán | timezone của occurrence đích (INVARIANT-007) |
| REPLACE | `overrideTime` có → dùng; không có → **giờ mặc định của template mới** (`templates[newTemplateId].startTime/endTime`) | timezone của occurrence đích |
| SPLIT | `SplitPart.startTime/endTime` + `SplitPart.dateOffsetDays` (0 hoặc 1) — **thêm field mới**; part ngày +1 (bắt đầu sau nửa đêm) tự resolve trên ngày offset | timezone của occurrence gốc |
| SWAP | local civil intent của occurrence kia (template + shiftDate + local time) | **timezone của từng occurrence đích — KHÔNG đổi timezone của ai cả** (INVARIANT-007) |
| DELETE | — | — |

**Phản biện review2 ("UPDATE phải bắt buộc có startTime+endTime"):** bác bỏ. Bắt buộc đầy đủ sẽ ép user "đổi tên ca nhưng giữ giờ" phải REPLACE sang template trùng giờ — tạo template mới vô nghĩa. Quy tắc "≥1 field, field vắng giữ nguyên (suy từ UTC)" vừa đủ chặt (không silent no-op: payload rỗng hoàn toàn bị reject `INVALID_PAYLOAD`) vừa linh hoạt đúng nhu cầu thật.

### D4 — Provenance tagging tại nguồn (fix M4)
Thêm field `sourceOverrideId` (String?, nullable) vào `ShiftOccurrence`:
- Baseline (projectOccurrences) → `null`.
- Mọi occurrence **được tạo hoặc sửa bởi override** → gán `sourceOverrideId = override.id` (SPLIT: gán cho từng part; SWAP: gán cho cả 2; UPDATE/REPLACE: gán lên bản mới). Override sau ghi đè override trước (chuỗi override: provenance = lần chạm cuối).
- `EffectiveOccurrence.source` suy từ: `sourceOverrideId != null` → `'override'`; id nằm trong `createdIds` của CREATE → `'created'`; còn lại → `'baseline'`. **Cấm suy bằng membership guessing như hiện tại.**

### D5 — SWAP semantics (nhất trí hướng "civil intent", tôi siết thêm 1 ràng buộc)
- SWAP = trao đổi **shiftDate + template (+ local time nếu khác)** giữa 2 occurrence → **re-resolve UTC cho từng bên theo timezone của chính nó**.
- **Ràng buộc mới (phản biện review1/3 bỏ ngỏ):** SWAP chỉ hợp lệ khi 2 occurrence **cùng job** (cùng timezone + cùng template pool). Cross-job/cross-timezone → engine trả Issue `SWAP_CROSS_JOB` và yêu cầu user dùng 2 thao tác (DELETE + CREATE). Lý do: cho phép swap cross-timezone sẽ mở hộp Pandora về ý nghĩa "giờ địa phương của ai", phá INVARIANT-007, và chưa có UI case thật nào cần nó.
- SWAP **không đổi id** của 2 occurrence (id theo occurrence, không theo nội dung).

### D6 — DELETE = giữ Override, KHÔNG thêm cờ soft-delete (phản biện review2 §2.4 / review3 §3.4 / review4)
Reviewers đề xuất `deletedAt`/`isActive=false`. **Bác bỏ ở tầng engine:** engine hiện là *render-time projection* — override log là source of truth; occurrence bị delete chỉ đơn giản không được áp vào view. Bản thân record `Override(delete)` đã là audit trail + nguồn cho Undo. Thêm `deletedAt` vào occurrence = nhân đôi nguồn sự thật trước khi có persistence. **Quyết định: soft-delete thuộc Gate 2 (SQLite) khi cần lưu occurrence materialized; Gate 0 không thêm field.** (Ghi vào backlog, không code.)

### D7 — Error classification (nhất trí; mở rộng bằng M1/M2/M4)
Bộ error code dạng String tập trung (const list trong `time_types.dart`, dùng chung cả engine lẫn JSON golden):
`INVALID_DATE`, `INVALID_TIME`, `INVALID_TIMEZONE`, `INVALID_PAYLOAD`, `NONEXISTENT_LOCAL_TIME`, `AMBIGUOUS_LOCAL_TIME`, `END_BEFORE_START`, `MISSING_TEMPLATE`, `DUPLICATE_OCCURRENCE_ID`, `SWAP_CROSS_JOB`.
Trong đó `INVALID_DATE` = **không parse được HOẶC rollover** (round-trip check); `INVALID_TIME` = hour>23 / minute>59 / rollover; `INVALID_TIMEZONE` = `tz.getLocation` throw (bắt riêng, không gộp vào nonexistent như hiện tại — code cũ catch-all đẩy mọi thứ vào nonexistent).

### D8 — Effective Schedule trả về Result (chốt Option B — 4/4 nguồn ủng hộ B)
```dart
class ScheduleRenderResult {
  final List<EffectiveOccurrence> occurrences; // CHỈ occurrence resolved hợp lệ
  final List<RenderIssue> issues;              // DST_NONEXISTENT, AMBIGUOUS, MISSING_TEMPLATE, INVALID_*, DUPLICATE_ID, SWAP_CROSS_JOB
}
class RenderIssue {
  final String code;        // 1 trong D7
  final String? shiftDate;  // ngày liên quan (nếu có)
  final String? occurrenceId;
  final String message;     // human-readable, UI hiển thị trực tiếp được
}
```
Đổi return type `renderEffectiveSchedule` → `ScheduleRenderResult` (**giữ nguyên tên hàm** — đổi tên thành `buildScheduleView` như review2 đề xuất là churn vô nghĩa, không thêm giá trị). RenderIssue.message phải đủ thân thiện để UI hiện "⚠️ 02:30 on Mar 8 doesn't exist because clocks jump forward" mà không cần map lại.

### D9 — Versioning: anchorDate BẤT BIẾN qua các version (chốt câu plan3.md §11 bỏ ngỏ)
`createNewVersion()` hiện đặt `anchorDate = newEffectiveFrom` → **reset phase của cycle**. User đổi roster giữa cycle 4-on/4-off đang ở vị trí ngày 3 sẽ bị nhảy phase. **Quyết định:** version mới **giữ nguyên anchorDate của version gốc** (phase continuity — occurrence ngay sau effectiveFrom tiếp tục đúng nhịp cũ). User muốn đổi phase thật sự → tạo pattern mới (id mới), không phải version mới. Sửa `createNewVersion` + test. Lưu ý: nếu `cycleLengthDays` đổi, pha ánh xạ ngày→vị trí đổi theo — chấp nhận, nhưng **không reset anchor**.

### D10 — Projection vẫn on-the-fly; Materialized thuộc Gate 2 (phản biện review2 §2.3 / review3 §3.3)
Reviewers đề xuất "Materialized view + incremental update từ effectiveFrom, không regenerate quá khứ". **Bác bỏ ở Gate 0:** engine chưa có DB; "regenerate từ effectiveFrom" là quyết định lưu trữ (Gate 2), không implement được ý nghĩa ở tầng thuần. Điều duy nhất cần khóa NGAY là invariant: *render không bao giờ mutate input và luôn tính lại sạch từ pattern+overrides* (đã đúng). Ghi backlog cho Gate 2 kèm 2 ràng buộc reviewers nêu (past occurrences không tự sửa; cần truy vết nguồn qua `sourcePatternId`+version).

---

## 5. Spec code chi tiết theo file

### 5.1 `lib/core/time/time_engine.dart` — viết lại `resolveUtcInstant`

**Nguyên tắc:** bỏ hoàn toàn prev/next-hour heuristic + `utc1 ± 1h`. Dùng dữ liệu transition có sẵn trong `Location` của package `timezone` (đã verify E11: `offset` tính bằng milliseconds, `lookupTimeZone` công khai).

Pseudo-code (bắt buộc implement đúng luồng này):
```dart
// (0) VALIDATE — trước mọi thứ (M1)
//   - date: split '-', ép int; round-trip: DateTime(y,m,d) rồi so lại y/m/d — lệch => INVALID_DATE
//   - time: split ':', hour 0..23, minute 0..59; "10:90" roll => INVALID_TIME
//   - timezone: try tz.getLocation(tzName) catch => INVALID_TIMEZONE (KHÔNG gộp nonexistent)

// (1) enumerate candidate UTC instants — DB-driven, không ±1h
List<int> candidatesMs = [];
final naiveMs = DateTime.utc(y, m, d, h, min).millisecondsSinceEpoch; // wall-clock carrier
final seen = <int>{};
for (final zone in loc.zones) {                    // loc.zones: TimeZone[], offset = ms
  final c = naiveMs - zone.offset;                 // candidate instant nếu offset này đang hiệu lực tại c
  if (seen.contains(c)) continue;
  if (loc.lookupTimeZone(c).timeZone.offset == zone.offset) { // tự nhất quán: offset đang hiệu lực đúng tại c
    seen.add(c);
    candidatesMs.add(c);
  }
}
candidatesMs.sort();

// (2) classify
//   0 candidate => NONEXISTENT_LOCAL_TIME (gap)
//   1 candidate => RESOLVED
//   >=2 candidate => AMBIGUOUS_LOCAL_TIME, options = candidates (dedupe; kỳ vọng đúng 2)
```
**Bằng chứng đối chiếu bắt buộc (đã chạy, agent phải tái lập trong test):**

| Input | Kỳ vọng |
|---|---|
| `America/New_York` 2026-11-01 01:30 | 2 candidates, cách 60′ |
| `America/New_York` 2026-03-08 02:30 | 0 candidates (gap) |
| `America/New_York` 2026-09-04 10:00 | 1 candidate |
| `Europe/Berlin` 2026-10-25 02:30 | 2 candidates, cách 60′ |
| `Australia/Lord_Howe` 2026-04-05 01:45 | **2 candidates, cách ĐÚNG 30′**: `2026-04-04T14:45:00Z` & `2026-04-04T15:15:00Z` (code ±1h cũ cho cách 60′ — SAI) |

Giữ nguyên signature/kiểu trả về hiện tại của `ResolveResult` + `DstAmbiguityType` (golden JSON + test đang phụ thuộc) — **chỉ đổi logic bên trong**. `ResolveResult` thêm trường `String? errorCode` cho INVALID_* (không tái dùng `ambiguity` cho invalid — D7).

### 5.2 `lib/core/time/time_engine.dart` — `resolveShift` (bổ sung)
- Truyền `errorCode` của start/end resolution lên `ShiftResolution.error` (đang mất: nonexistent vs invalid).
- Sau khi resolve cả 2 đầu: `if (utcEnd.ms <= utcStart.ms) return error END_BEFORE_START` (M2 — check trên UTC, không phải local).
- `INVALID_DATE` từ shiftDate cũng phải lọt ra (hiện `int.parse` throw ngoài try/catch ở resolveUtcInstant — bọc toàn bộ bằng validate step 0).
- **Giữ nguyên** toàn bộ logic end-date (`+1` suffix, `endHour < startHour`) — đã đúng, không đụng.

### 5.3 `lib/core/time/time_types.dart`
- Thêm **const list error codes** (D7) — single source of truth, dùng chung cho engine, JSON golden, RenderIssue.
- `ResolveResult` thêm `errorCode` (nullable). Không đổi gì khác.

### 5.4 `lib/core/pattern/pattern_types.dart`
- `ShiftOccurrence`: thêm `final String? sourceOverrideId;` (D4) + vào `copyWith`.
- `CreatePayload`: thêm `required String timezone` (D3).
- `SplitPart`: thêm `required int dateOffsetDays;` (0|1) (D3).
- `UpdatePayload`: giữ optional, thêm validate "≥1 field" ở engine (không đổi type).
- Thêm `class RenderIssue` và `class ScheduleRenderResult` (D8).
- `ShiftPattern.anchorDate`: thêm comment "BẤT BIẾN qua các version (D9)".
- **KHÔNG** thêm `deletedAt`/`isActive` (D6), **KHÔNG** thêm pay fields (INVARIANT-005).

### 5.5 `lib/core/pattern/pattern_engine.dart` — Override pipeline
Đổi signature (E12 — phải cập nhật 14 call sites test + 1 internal):
```dart
List<ShiftOccurrence> applyOverride(
  List<ShiftOccurrence> occurrences,
  Override override, {
  required Map<String, ShiftTemplate> templates, // để lấy giờ mặc định khi cần (REPLACE, CREATE nếu cần lookup)
})
```
Mỗi `_applyX` đi qua: **validate payload → xác định local time + timezone (bảng D3) → gọi `resolveShift` (5.2) → 0/2 candidate = trả về?** — vấn đề: hàm hiện trả `List<ShiftOccurrence>`, không có kênh báo lỗi. **Giải pháp khóa:** đổi trả về thành:
```dart
class OverrideResult {
  final List<ShiftOccurrence> occurrences; // immutable, đã resolve 100% hoặc giữ nguyên list cũ
  final List<RenderIssue> issues;           // lỗi của override này (nếu có, occurrences = list cũ không đổi)
}
OverrideResult applyOverride(...)
```
Khi một override fail (VD AMBIGUOUS) → trả `occurrences` = list cũ + issue; **không tạo occurrence rỗng, không silent**. (Agent: đây là breaking change lớn nhất — cập nhật toàn bộ test cho đúng contract mới, KHÔNG vì tiện mà giữ kiểu cũ.)

Chi tiết từng operation:
- **CREATE:** validate payload (date/time/timezone); resolve; thành công → occurrence mới `id: override.id`, `patternId: ''`, `sourceOverrideId: override.id`.
- **UPDATE:** ≥1 field; field vắng giữ nguyên — local time hiện tại suy từ `occ.startDateTimeUtc/endDateTimeUtc` qua `occ.timezone` (`TZDateTime.from`); đổi time → re-resolve trên `occ.shiftDate` (end-date tự xử lý trong resolveShift); thành công → `copyWith(...các field đổi, sourceOverrideId: override.id)`.
- **REPLACE:** `templateId = newTemplateId`; time = `overrideTime` nếu có, ngược lại lấy `templates[newTemplateId]` (thiếu template → Issue `MISSING_TEMPLATE`); re-resolve; `sourceOverrideId`.
- **SPLIT:** mỗi part resolve độc lập trên `shiftDate + dateOffsetDays` với timezone gốc; part nào fail → **toàn bộ SPLIT fail** (atomic — trả list cũ + issue), tránh nửa split nửa không; thành công → thay occurrence gốc bằng các part (`id: '${occ.id}#p$i'`, `sourceOverrideId: override.id`).
- **SWAP:** validate cùng job (so jobId qua template lookup + timezone bằng nhau) → `SWAP_CROSS_JOB` nếu khác; đổi shiftDate/template/local-time cho nhau, **giữ nguyên timezone + id mỗi bên**, re-resolve từng bên; fail → nguyên list cũ + issue.
- **DELETE:** giữ nguyên hành vi filter (D6 — không thêm cờ); vẫn trả `OverrideResult` (issues rỗng).
- Sau mọi operation: **duplicate-id check** trên list kết quả → Issue `DUPLICATE_OCCURRENCE_ID` (M3) nếu phát hiện (vẫn trả list — đây là cảnh báo view-level, không phải fail atomic).

### 5.6 `renderEffectiveSchedule` → `ScheduleRenderResult` (D8)
1. Gọi `projectOccurrences` — **KHÔNG còn `.where(isSuccess)`**; giữ nguyên các error entries.
2. Chạy `applyOverride` từng override theo thứ tự; gộp issues của từng override.
3. Provenance theo `sourceOverrideId` (D4); baseline id = id gốc từ projectOccurrences.
4. Duplicate-id check toàn view (M3).
5. Sort theo shiftDate.
6. Trả `ScheduleRenderResult{occurrences: [...], issues: [...]}` — issue message human-readable (D8).

### 5.7 Versioning (D9)
`createNewVersion()`: `anchorDate` của version mới = **anchorDate của version cũ** (bỏ `anchorDate: newEffectiveFrom`). Cập nhật docstring + test minh hoạ phase continuity: pattern 4-on/4-off anchor 2026-01-01, tạo version mới effectiveFrom 2026-06-15 với sequence khác → occurrence 2026-06-15 phải tiếp tục đúng vị trí cycle tính từ 2026-01-01.

---

## 6. Spec test (bắt buộc — viết trước hoặc song song code, không được code xong rồi mới nghĩ test)

### 6.1 Golden JSON (giữ convention JSON + Dart test đọc JSON — phản biện đề xuất YAML của review2/3: project đã chốt JSON từ Bước 1, không đổi công cụ)
Mở rộng `test/golden/time_engine_cases.json` — mỗi case có `utcStart/utcEnd/durationHours` (nếu resolve được) hoặc `expectedError` + `options` (nếu ambiguous), đúng cấu trúc case đang có:

| ID mới | Input | Kỳ vọng |
|---|---|---|
| DST-009 | `Australia/Lord_Howe` 2026-04-05 01:45→03:00 (fall-back 30′) | AMBIGUOUS start, 2 options cách 30′: `...T14:45:00Z` / `...T15:15:00Z` |
| DST-010 | `Australia/Lord_Howe` 2026-10-04 02:15→04:00 (spring-forward 30′: 02:00→02:30) | NONEXISTENT start |
| VALID-001 | `America/New_York` shiftDate `2026-02-31` (ngày không tồn tại) | INVALID_DATE (KHÔNG phải nonexistent, KHÔNG roll thành 03-03) |
| VALID-002 | time `25:90` | INVALID_TIME |
| VALID-003 | time `07:00`→`07:00` (không `+1`) | END_BEFORE_START |
| VALID-004 | timezone `Mars/Olympus` | INVALID_TIMEZONE |
| LH-001 | Lord Howe ca thường 2026-06-15 08:00→17:00 (offset +10:30) | resolve 1 candidate; utcStart `...T21:30:00Z`? — **agent tự verify bằng script** (như convention DST-001→008) và dán log |

> Agent: toàn bộ UTC mới phải tính bằng resolver mới + xác nhận bằng `node scripts/verify_all_cases.mjs` (hoặc script tương đương đọc JSON), KHÔNG tự tính tay — đúng convention đã lập ở Bước 1.

### 6.2 Test Dart mới (unit/property/integration)
1. **Resolver (time):** bảng §5.1 (NY gap/ambiguous/normal, Berlin, **Lord Howe 30′** — case quyết định chứng minh bỏ ±1h). Property: mọi RESOLVED instant, `TZDateTime.from(utc, loc)` phải cho lại đúng wall-clock (round-trip) — chạy qua 1 năm × mỗi giờ × 3 zone (NY, Berlin, Lord Howe).
2. **Validation:** 4 case VALID-001..004 ở trên + đảm bảo `INVALID_*` không bao giờ đi vào nhánh DST.
3. **Override pipeline (pattern_engine_test):** cập nhật 14 call sites cũ sang `OverrideResult`; thêm:
   - CREATE → occurrence có UTC/timezone đầy đủ (không rỗng) + `sourceOverrideId` = override.id;
   - UPDATE đổi giờ (07:00→09:00) → UTC được re-resolve đúng (tính trước bằng resolver);
   - UPDATE chỉ đổi template (giữ giờ) → UTC không đổi;
   - UPDATE payload rỗng → Issue `INVALID_PAYLOAD`, list không đổi;
   - UPDATE giờ rơi vào DST gap → Issue `NONEXISTENT_LOCAL_TIME`, list không đổi (không occurrence rỗng);
   - REPLACE có overrideTime / không overrideTime (lấy giờ template mới);
   - SPLIT 07:00–19:00 → 07:00–11:00 + 15:00–19:00 → cả 2 part UTC đầy đủ, sourceOverrideId đúng, occurrence gốc biến mất; SPLIT overnight 19:00→07:00 thành 19:00→00:00+1 & 00:00+1→07:00+1 (part 2 `dateOffsetDays: 1`) → đúng ngày; SPLIT part fail → atomic (list cũ + issue);
   - SWAP 2 ca cùng job → UTC mỗi bên re-resolve theo timezone của chính nó, id/timezone KHÔNG đổi; SWAP cross-job → Issue `SWAP_CROSS_JOB`;
   - DELETE → occurrence biến mất khỏi view nhưng vẫn có Override record (kiểm tra qua render với/không override);
   - Chain: UPDATE → SPLIT trên kết quả → provenance = override cuối (M4);
   - Duplicate id (2 baseline cùng ngày cùng template qua pattern cycle) → Issue `DUPLICATE_OCCURRENCE_ID`.
4. **Renderer:** `renderEffectiveSchedule` trả `ScheduleRenderResult`; ca DST gap trong range → occurrence KHÔNG có trong `.occurrences` nhưng **CÓ issue NONEXISTENT_LOCAL_TIME** trong `.issues` (test trực tiếp chống regression silent-drop); MISSING_TEMPLATE tương tự.
5. **Versioning:** phase continuity (5.7); version cũ không mutate.
6. **Regression:** toàn bộ case DST-001..008 + SH/BORDER/STANDARD/INVARIANT hiện có vẫn pass KHÔNG đổi expected (trừ khi resolver mới lộ lỗi expected cũ — nếu lệch, dừng và báo cáo, KHÔNG tự sửa expected).

---

## 7. NEVER list (bổ sung cho NEVER list của plan1/plan2)

- NEVER tạo `ShiftOccurrence` với UTC/timezone rỗng hoặc null — kể cả "tạm thời, caller resolve sau".
- NEVER silent-drop unresolved occurrence/error trong render (mọi lỗi phải vào `issues`).
- NEVER dùng `± Duration(hours: 1)` hoặc so sánh `offset.inHours` để suy candidate DST.
- NEVER copy `timezone`/UTC giữa 2 occurrence khi SWAP; timezone chỉ đến từ occurrence đích.
- NEVER để `UPDATE`/`REPLACE` đổi template mà không xử lý time (dù giữ nguyên cũng phải resolve lại theo luật D3).
- NEVER hard-delete ở tầng engine theo kiểu xóa record override (override log là audit trail).
- NEVER thêm field soft-delete / pay / UUID vào model ở Gate 0 (D6, INVARIANT-005, D10).
- NEVER tự sửa expected value của golden case cũ để "làm xanh" — lệch expected = báo cáo ngay.
- NEVER coi `INVALID_*` là DST error (D7).
- NEVER mở rộng phạm vi sang money/UI/persistence/import.
- NEVER đánh dấu ✅ trong `features.md` khi chưa có test + acceptance scenario tương ứng.

---

## 8. Acceptance criteria (Gate 0 xanh khi TẤT CẢ đạt)

- [ ] Không còn code path nào tạo `ShiftOccurrence` với UTC/timezone rỗng (grep `''` trong pattern_engine không còn ở temporal fields).
- [ ] `resolveUtcInstant` trả 0/1/2 candidate từ DB (không ±1h); pass bảng §5.1 gồm Lord Howe 30′.
- [ ] Phân biệt `INVALID_DATE`/`INVALID_TIME`/`INVALID_TIMEZONE`/`INVALID_PAYLOAD` với DST error; round-trip validation chặn rollover (VALID-001/002 pass).
- [ ] `END_BEFORE_START` được trả khi utcEnd ≤ utcStart (VALID-003).
- [ ] Cả 6 operations đi qua pipeline; CREATE/UPDATE(time)/REPLACE(time)/SPLIT tạo occurrence UTC đầy đủ; payload fail → Issue + list cũ, không occurrence rỗng.
- [ ] UPDATE giờ rơi vào gap/ambiguous → Issue, không silent.
- [ ] SWAP cùng job re-resolve đúng, giữ id/timezone; cross-job → `SWAP_CROSS_JOB`.
- [ ] `renderEffectiveSchedule` trả `ScheduleRenderResult{occurrences, issues}`; không còn `.where(isSuccess)` trong file.
- [ ] Provenance: occurrence do SPLIT/CREATE/chuỗi override gắn `sourceOverrideId` đúng; không còn SPLIT-part bị gắn `baseline`.
- [ ] `createNewVersion` giữ anchorDate cũ (phase continuity) + test.
- [ ] Toàn bộ: `dart test test/core/` pass 100%; golden JSON mới verify bằng script; regression case cũ không đổi expected.
- [ ] `features.md` cập nhật: Override → 🟡/✅ kèm trạng thái thật từng operation; Time Engine ghi rõ validation đã có; KHÔNG còn ✅ rộng.

---

## 9. Out of scope — ghi backlog, KHÔNG code ở Gate 0

Tổng hợp đề xuất product của plan3.md §18–27 + review2/3/4, xếp backlog cho các gate sau (features.md đã có khung trạng thái — thêm mục Backlog):
- **Gate 1 (Money):** PayRule versioned, breakdown, snapshot, golden money cases; `PayContext{workWeekStart, periodType, OT threshold}` gắn Job (chỉ spec khi mở Gate 1).
- **Gate 2 (Persistence):** SQLite, migration, materialized projection + incremental từ effectiveFrom (kèm ràng buộc "không tự sửa quá khứ"), soft-delete/audit, UUID identity tách khỏi deterministic id, backup/restore.
- **Gate 4+ (UI/UX):** Next Shift + countdown (signature), "Why this shift?", "What changed?" timeline, pay breakdown chi tiết + "Why OT?", conflict & duplicate detection, smart import review (không auto-commit), system-wide Undo, Shift Draft, Settings production (tz/DST/12-24h/week-start…), encrypted local backup trước cloud.
- **Lưu ý review4/plan3:** mọi UI nói trên chỉ code sau khi core contract xanh — đúng, giữ nguyên.

---

## 10. Định nghĩa "xong" — báo cáo agent phải nộp

1. Diff tóm tắt từng file (time_engine, time_types, pattern_types, pattern_engine) — ghi rõ breaking change + các call site test đã cập nhật.
2. Log đầy đủ `dart test test/core/` (con số test trước/sau).
3. Output script verify golden JSON mới (Lord Howe, VALID-001..004).
4. Danh sách test mới + ánh xạ tới từng acceptance criterion §8.
5. Xác nhận grep: không còn `startDateTimeUtc: ''` / `timezone: ''`; không còn `.where((r) => r.isSuccess)`; không còn `Duration(hours: 1 : -1)` trong resolver.
6. Trạng thái mới trong `features.md`.

**Gate 0 chỉ đóng khi báo cáo này được human review (user) chấp nhận. Sau đó mới mở prompt Gate 1 — `core/money`.**
