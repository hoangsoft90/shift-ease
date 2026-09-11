# plan3_final_v2.md — ShiftEase Core Contract Hardening (Gate 0, CHỐT)

> **Trạng thái:** CHỐT — sẵn sàng cho agent code implement (thay thế hoàn toàn `plan3_final.md`).
> **Đầu vào:** `plan3_final.md` + 5 review (`plan3_final_review1` → `review5`, hội tụ rất mạnh — 5/5 đồng thuận trên gần như mọi điểm) + đọc trực tiếp code thật hiện tại (`lib/core/time/*`, `lib/core/pattern/*`) để xác nhận **chưa có sửa nào được áp dụng** — mọi lỗi P0 trong `plan3_final.md` vẫn nguyên trạng.
> **Phạm vi:** CHỈ `core/time`, `core/pattern`, override pipeline, effective-schedule renderer, golden/unit/property/integration tests, `.plan/features.md`.
> **NGHIÊM CẤM đụng:** `core/money`, UI, persistence/DB, import/OCR, notification, PayContext, ID-UUID layer.

---

## 0. Verdict tổng hợp

`plan3_final.md` là bản kế hoạch tốt nhất trong chuỗi — evidence thực nghiệm (probe `timezone 0.9.4` thật, phát hiện Lord Howe 30′, Dart silent rollover) và scope control (Gate 0 chặn money/UI/persistence) đều được cả 5 review đánh giá xuất sắc (9-9.5/10). Nhưng **5/5 review đồng thuận tuyệt đối**: nếu giao nguyên bản cho agent code, sẽ tạo ra core **"xanh test nhưng sai semantics domain"** — nguy hiểm hơn cả bug DST ban đầu, vì loại lỗi này rất khó phát hiện qua test thông thường và cực tốn kém để sửa sau khi Money/SQLite/UI đã xây trên nó.

**Điểm trung bình 5 review: 8.3–8.7/10.** Trạng thái đúng không phải "CHỐT — sẵn sàng cho agent" mà là **"READY AFTER CONTRACT PATCH"**. Văn bản này CHÍNH LÀ bản patch đó — sau khi áp dụng, trạng thái chính thức chuyển thành **READY FOR AGENT EXECUTION**.

---

## 1. Sáu lỗi P0/Critical — 5/5 review đồng thuận, PHẢI sửa trong spec trước khi giao agent

### P0-1 — Signature `applyOverride` tự mâu thuẫn trong chính `plan3_final.md`

§5.5 vừa viết `List<ShiftOccurrence> applyOverride(...)` ở đoạn giới thiệu, vừa chốt `OverrideResult applyOverride(...)` ở đoạn quyết định. Với AI coding agent đây là lỗi chết người — agent có thể chọn đoạn đầu và bỏ qua quyết định thật.

**CHỐT (xóa sạch signature cũ, chỉ còn duy nhất):**
```dart
OverrideResult applyOverride(
  List<ShiftOccurrence> occurrences,
  Override override, {
  required Map<String, ShiftTemplate> templates,
})

class OverrideResult {
  final List<ShiftOccurrence> occurrences; // list mới (thành công) hoặc list cũ nguyên vẹn (fail)
  final List<RenderIssue> issues;
}
```

### P0-2 — UPDATE semantics: re-resolve vô điều kiện là một regression nguy hiểm

`plan3_final.md` §5.5 yêu cầu UPDATE luôn re-resolve local time qua resolver mới, kể cả khi chỉ đổi `templateId`. Case thực tế: một occurrence đã được tạo hợp lệ vào lúc `01:30 America/New_York` ngày fall-back (được resolve thành 1 trong 2 candidate UTC tại thời điểm tạo). Sau đó user chỉ **đổi tên/màu ca** (không đụng giờ) → UPDATE → engine re-resolve `01:30` → resolver phát hiện 2 candidates → trả lỗi `AMBIGUOUS_LOCAL_TIME` **dù user không hề thay đổi thời gian**. Đây là bug UX nghiêm trọng bị chính spec tạo ra.

**CHỐT — quy tắc bảo toàn UTC (5/5 review nhất trí):**
```
if (startTime, endTime, timezone) trong UpdatePayload đều KHÔNG đổi
   so với occurrence hiện tại (so sánh với local time suy ra từ
   occ.startDateTimeUtc/occ.endDateTimeUtc qua occ.timezone):
     → preserve UTC tuyệt đối, KHÔNG gọi lại resolveShift()
else:
     → resolve lại theo local time mới (có thể trả AMBIGUOUS/NONEXISTENT)
```
Điều kiện "≥1 field, field vắng giữ nguyên" của `plan3_final.md` D3 vẫn đúng và giữ nguyên — chỉ bổ sung thêm: **"giữ nguyên" nghĩa là giữ nguyên UTC đã lưu, không phải giữ nguyên rồi resolve lại ra cùng kết quả** (hai việc này khác nhau khi rơi vào vùng DST ambiguous).

### P0-3 — "Resolved-only domain" (D1) chưa airtight ở `projectOccurrences`

`plan3_final.md` tuyên bố D1 "mọi ShiftOccurrence tồn tại trong domain bắt buộc có UTC/timezone hợp lệ", nhưng §5.6 lại nói `projectOccurrences` "giữ nguyên các error entries" — không rõ error entry đó có phải là một `ShiftOccurrence` với field rỗng hay không. Nếu có, D1 bị phá ngay tại nguồn.

**CHỐT contract:**
```dart
class ProjectionResult {
  final List<ShiftOccurrence> occurrences; // 100% resolved, KHÔNG một field UTC/timezone nào rỗng
  final List<RenderIssue> issues;          // DST gap, MISSING_TEMPLATE... — occurrence tương ứng KHÔNG tồn tại
}
ProjectionResult projectOccurrences({...}) // đổi return type, không còn List<ResolvedOccurrence>
```
Pipeline chuẩn: `Pattern → projectOccurrences() → ProjectionResult → applyOverride() nhiều lần → ScheduleRenderResult`. `ResolvedOccurrence` (kiểu cũ, dùng chung cho cả success/error trong 1 object) bị loại bỏ hoàn toàn khỏi contract công khai.

### P0-4 — Thiếu error code `OCCURRENCE_NOT_FOUND`

Không có case nào trong `plan3_final.md` xử lý khi override (UPDATE/DELETE/REPLACE/SPLIT/SWAP) trỏ tới `occurrenceId` không tồn tại — do đã bị DELETE trước đó, bị SPLIT đổi ID, hoặc do lỗi dữ liệu. Không có error code riêng → nguy cơ rất cao agent tự chọn cách xử lý là **silent no-op** (trả nguyên list cũ mà không báo gì) — đúng loại hành vi mà toàn bộ Gate 0 được lập ra để tiêu diệt.

**CHỐT:** Thêm `OCCURRENCE_NOT_FOUND` vào D7 (danh sách error code). Mọi operation trừ CREATE: nếu `occurrenceId`/`swapWithOccurrenceId` không tìm thấy trong list hiện tại → trả `OverrideResult(occurrences: list cũ nguyên vẹn, issues: [RenderIssue(code: 'OCCURRENCE_NOT_FOUND', ...)])`.

### P0-5 — D4 Provenance tự mâu thuẫn

D4 định nghĩa: `sourceOverrideId != null → source = 'override'`, `id nằm trong createdIds → source = 'created'`. Nhưng §5.5 lại bắt buộc CREATE gán `sourceOverrideId = override.id` — nghĩa là **mọi occurrence do CREATE tạo ra đều có `sourceOverrideId != null`**, rơi vào nhánh đầu tiên (`'override'`) trước khi kịp tới nhánh `'created'`. Nhánh `created` trở thành dead code, mất khả năng phân biệt "ca tôi tự thêm tay" với "ca gốc bị sửa".

**CHỐT — tách 2 khái niệm độc lập:**
```dart
enum OccurrenceSource { baseline, created, modified }

// source: phân loại nghiệp vụ, gán TRỰC TIẾP tại thời điểm operation chạy — không suy đoán ở renderer
//   projectOccurrences  → baseline
//   CREATE              → created
//   UPDATE/REPLACE/SPLIT/SWAP → modified

// sourceOverrideId: CHỈ làm audit trail (override nào chạm vào occurrence này lần cuối) — không dùng để quyết định source
```
Quy tắc chuỗi (làm rõ theo góp ý review3): nếu một occurrence `created` sau đó bị `UPDATE` bởi override khác, `source` chuyển thành `modified` (ghi đè), thông tin "từng được tạo thủ công" vẫn truy được qua override log nếu cần nhưng không phải trách nhiệm của engine hiển thị lại.

### P0-6 — Override chain: atomicity + ordering chưa được khóa

`plan3_final.md` có nói "SPLIT fail → atomic", "SWAP fail → nguyên list cũ" cho từng operation riêng lẻ, nhưng chưa khóa hành vi ở **cấp chuỗi nhiều override**: override #2 fail thì có rollback #1 không? Override sau có được đánh giá tiếp không? Target theo ID sau khi ID đã đổi (do SPLIT/SWAP) xử lý ra sao?

**CHỐT — Command-level atomicity (5/5 review nhất trí):**
```
Mỗi Override trong chuỗi được áp dụng ĐỘC LẬP, theo đúng thứ tự trong list overrides:
  - Override N thành công → state cập nhật, tiếp tục override N+1 trên state mới.
  - Override N thất bại (bất kỳ lỗi nào) → state GIỮ NGUYÊN như sau override N-1,
    lỗi được thêm vào issues tổng, và override N+1 VẪN được đánh giá tiếp
    (không bị chặn bởi lỗi của N, không rollback N-1 trở về trước).
  - Target occurrenceId của override N phải được tìm trong state SAU override N-1
    (không phải state gốc) — nghĩa là override nhắm vào occurrence do override
    trước đó tạo/sửa/đổi-tên là hợp lệ.
```

---

## 2. Bốn vấn đề High — 4-5/5 review đồng thuận, cũng bắt buộc patch

### H-1 — SPLIT thiếu invariant overlap/order/envelope

Chưa có ràng buộc: các part có được overlap không, có phải nằm trong khung giờ occurrence gốc không, có phải theo thứ tự thời gian không. Không siết → payroll double-count, calendar hiện ca chồng chéo.

**CHỐT:**
```
- Các part PHẢI theo thứ tự thời gian tăng dần (part[i].start < part[i].end <= part[i+1].start).
- Các part KHÔNG được overlap với nhau.
- Toàn bộ thời gian mỗi part PHẢI nằm trong [occ.startDateTimeUtc, occ.endDateTimeUtc] gốc
  (tính trên UTC đã resolve, không phải local) — ngoại trừ ranh giới nửa đêm hợp lệ
  giữa 2 part liên tiếp của ca overnight (part[i].end == part[i+1].start == 00:00 local).
- Vi phạm bất kỳ điều nào ở trên → toàn bộ SPLIT fail atomic (trả list cũ + issue),
  không tạo một phần nào.
```

### H-2 — Error code nên có type-safety mà không phá JSON compatibility

`plan3_final.md` dùng `String` thuần cho error code — dễ typo (`'INVALID_TIME'` vs `'INVALID_TIM'`), agent có thể tạo bug ngầm. Review1 đề xuất `enum`, nhưng sẽ phá tương thích với golden JSON hiện có (string).

**CHỐT — giải pháp dung hòa (review2/3/4/5 đồng thuận):**
```dart
abstract final class ErrorCodes {
  static const invalidDate = 'INVALID_DATE';
  static const invalidTime = 'INVALID_TIME';
  static const invalidTimezone = 'INVALID_TIMEZONE';
  static const invalidPayload = 'INVALID_PAYLOAD';
  static const nonexistentLocalTime = 'NONEXISTENT_LOCAL_TIME';
  static const ambiguousLocalTime = 'AMBIGUOUS_LOCAL_TIME';
  static const endBeforeStart = 'END_BEFORE_START';
  static const missingTemplate = 'MISSING_TEMPLATE';
  static const duplicateOccurrenceId = 'DUPLICATE_OCCURRENCE_ID';
  static const swapCrossJob = 'SWAP_CROSS_JOB';
  static const occurrenceNotFound = 'OCCURRENCE_NOT_FOUND'; // P0-4
}
```
Mọi nơi trong engine dùng `ErrorCodes.xxx`, cấm literal string rải rác. Golden JSON vẫn dùng string thuần (không đổi format file).

### H-3 — `RenderIssue.message` đang trộn domain với presentation

`plan3_final.md` yêu cầu message "đủ thân thiện để UI hiện trực tiếp" — điều này kéo trách nhiệm hiển thị (i18n, tone) vào tầng domain thuần, vi phạm ranh giới kiến trúc sạch, và khóa cứng UI copy vào code core quá sớm.

**CHỐT (theo hướng dung hòa của review2):** Giữ field `message` ở Gate 0 (không thêm tầng UI-mapping mới, tránh over-engineering khi UI còn chưa tồn tại), nhưng bắt buộc ghi rõ trong docstring:
```dart
/// [message] là fallback chẩn đoán kỹ thuật (diagnostic fallback) cho log/debug,
/// KHÔNG phải một UI localization contract cố định. Tầng UI (Gate 4+) có quyền
/// tự map [code] sang message hiển thị theo ngôn ngữ/tone riêng, không bắt buộc
/// dùng nguyên văn [message] này.
final String message;
```

### H-4 — Round-trip invariant cho DST resolver cần cụ thể hóa thành acceptance test, không chỉ nằm trong mô tả thuật toán

`plan3_final.md` §5.1 đã có ý tưởng round-trip nhưng chưa tách thành tiêu chí nghiệm thu độc lập, dễ bị agent bỏ qua khi implement vội.

**CHỐT bổ sung:** mọi candidate UTC được coi là RESOLVED phải thỏa đồng thời 2 điều kiện (không chỉ offset consistency như spec cũ):
```
1. offset consistency: loc.lookupTimeZone(candidate).timeZone.offset == zone.offset (đã có)
2. wall-clock round-trip: TZDateTime.from(candidate, location) → (year,month,day,hour,minute)
   PHẢI khớp chính xác input civil time ban đầu
```
Viết thành property test chạy qua 1 năm × mỗi giờ × ít nhất 3 zone (NY, Berlin, Lord Howe) — xem §5 mục test.

---

## 3. Phản biện lại review1 trên 3 điểm — giữ nguyên lập trường của `plan3_final.md` gốc

Không phải mọi đề xuất của review đều được chấp nhận nguyên văn — 3 điểm sau đây `plan3_final.md` gốc đã đúng, review1 nêu ra nhưng review2/3/4/5 tự phản biện lại và tôi đồng ý giữ nguyên:

1. **SWAP cross-timezone:** review1 gợi mở khả năng cho phép swap khác timezone. **Giữ nguyên quyết định gốc:** Gate 0 CHỈ cho phép SWAP khi `same jobId` AND `same timezone`; khác đi → `SWAP_CROSS_JOB`. Lý do: cho phép cross-timezone sẽ mở ra câu hỏi "giờ địa phương của ai" chưa có UI case nào cần, và phá INVARIANT-007.
2. **DELETE soft-delete:** review1 không phản đối trực tiếp nhưng có thể bị hiểu nhầm cần thêm field khi làm atomicity. **Giữ nguyên quyết định D6 gốc:** không thêm `deletedAt`/`isActive` ở Gate 0 — override log đã là audit trail đủ dùng; soft-delete (nếu cần) thuộc Gate 2 khi có persistence.
3. **Performance benchmark của resolver:** review1/3 đề xuất tiêu chí cứng (VD "<10ms"). **Hạ xuống backlog, không đưa vào acceptance criteria Gate 0** — enumerate `loc.zones` trên app offline không phải bottleneck thực tế ở quy mô 1 user/1 device; đưa 1 dòng ghi chú backlog cho Gate 2 là đủ, không cần chặn Gate 0 vì một rủi ro chưa có bằng chứng.

---

## 4. Toàn bộ nội dung khác của `plan3_final.md` — GIỮ NGUYÊN, không đổi

Các phần sau của `plan3_final.md` đã đúng và được cả 5 review xác nhận không cần sửa — áp dụng y nguyên, không lặp lại ở đây để tránh drift giữa 2 văn bản:

- **§1 Bằng chứng verify (E1–E12)** — toàn bộ evidence thực nghiệm (Lord Howe 30′, Dart silent rollover, `timezone` package API) giữ nguyên, đây là nền tảng đúng của toàn bộ Gate 0.
- **§3 M1–M4** (Dart rollover, END_BEFORE_START, duplicate ID, provenance sai cho SPLIT/SWAP) — giữ nguyên là các phát hiện đúng.
- **D3** (bảng nguồn local time/timezone cho từng operation), **D5** (SWAP semantics — cùng job), **D6** (DELETE không soft-delete), **D7** (error classification — bổ sung `OCCURRENCE_NOT_FOUND` theo §1 P0-4 ở trên), **D8** (ScheduleRenderResult — giữ, không đổi tên hàm), **D9** (anchorDate bất biến qua version), **D10** (projection on-the-fly, materialized thuộc Gate 2) — giữ nguyên toàn bộ.
- **§5.1, 5.2, 5.3** (spec resolver mới, bảng đối chiếu Lord Howe/NY/Berlin, thêm `errorCode` vào `ResolveResult`) — giữ nguyên.
- **§5.4** (thêm `sourceOverrideId`, `CreatePayload.timezone`, `SplitPart.dateOffsetDays`, `RenderIssue`/`ScheduleRenderResult`) — giữ nguyên, chỉ bổ sung `OccurrenceSource` enum theo P0-5 ở trên.
- **§5.7** (versioning giữ anchorDate) — giữ nguyên.
- **§6.1** golden JSON mới (DST-009 Lord Howe ambiguous, DST-010 Lord Howe nonexistent, VALID-001..004, LH-001) — giữ nguyên, bổ sung thêm case cho `OCCURRENCE_NOT_FOUND` và override-chain (xem §5 dưới).
- **§7 NEVER list** — giữ nguyên toàn bộ 11 điều, bổ sung thêm 3 điều mới ở §6 dưới.
- **§9 Out of scope / backlog Gate 1+** — giữ nguyên.
- **§10 Định nghĩa "xong"** — giữ nguyên, bổ sung 2 mục báo cáo mới (xem §7 dưới).

---

## 5. Bổ sung Golden Test & Test Dart (cộng thêm vào §6 của `plan3_final.md`)

### 5.1 Case mới cho `time_engine_cases.json`
Không thay đổi case đã có (DST-001..010, VALID-001..004, LH-001 giữ nguyên) — chỉ thêm:
- Case xác nhận round-trip property (không phải 1 case cụ thể mà là property test chạy vòng lặp — xem 5.2).

### 5.2 Test Dart bổ sung (`pattern_engine_test.dart`, `time_engine_test.dart`)
1. **UPDATE preserve UTC:** occurrence tạo tại giờ ambiguous (1 trong 2 candidate) → UPDATE chỉ đổi `templateId`, giữ nguyên `startTime/endTime` → assert `startDateTimeUtc`/`endDateTimeUtc` **không đổi bit nào**, không gọi resolver.
2. **UPDATE đổi giờ thật:** đổi `startTime` 07:00→09:00 → assert UTC mới đúng, khác UTC cũ.
3. **OCCURRENCE_NOT_FOUND:** UPDATE/DELETE/REPLACE/SPLIT/SWAP với `occurrenceId` không tồn tại trong list → assert `issues` chứa đúng code, `occurrences` y hệt list đầu vào (so sánh deep-equal, không chỉ độ dài).
4. **Override chain atomicity:** chuỗi `[UPDATE thành công, UPDATE thất bại (OCCURRENCE_NOT_FOUND), UPDATE thành công khác]` → assert override #1 và #3 đều được áp dụng, #2 chỉ sinh issue, không chặn #3.
5. **Override chain ordering:** `SPLIT A → UPDATE` nhắm vào 1 trong các ID mới sinh ra từ SPLIT (VD `A#p0`) → assert UPDATE áp dụng đúng lên part đó, không phải lên `A` gốc (đã không còn tồn tại).
6. **SPLIT invariant (H-1):** test overlap → fail atomic; test part ngoài envelope gốc → fail atomic; test part đúng thứ tự + trong envelope → thành công.
7. **Provenance (P0-5):** CREATE → `source == created`; CREATE rồi UPDATE → `source == modified`; occurrence baseline không bị chạm → `source == baseline`.
8. **Round-trip property (H-4):** vòng lặp 1 năm × mỗi giờ (hoặc sample đại diện đủ dày qua các mốc DST) × 3 zone (America/New_York, Europe/Berlin, Australia/Lord_Howe) → mọi candidate RESOLVED phải round-trip đúng wall-clock input.
9. **ProjectionResult resolved-only (P0-3):** `projectOccurrences` với pattern tham chiếu template thiếu / ngày rơi vào DST gap → assert **không có object `ShiftOccurrence` nào xuất hiện trong `.occurrences`** ứng với ngày lỗi đó, lỗi chỉ nằm trong `.issues`.
10. **Regression:** toàn bộ test hiện có (55 test) phải tiếp tục pass sau khi đổi signature — cập nhật 14 call site đã biết (E12 trong `plan3_final.md`) sang `OverrideResult`/`ProjectionResult`; nếu bất kỳ expected value nào lệch do resolver mới, DỪNG và báo cáo, không tự sửa expected.

---

## 6. NEVER list — bổ sung 3 điều mới (cộng vào 11 điều đã có trong `plan3_final.md` §7)

- NEVER để `source` (OccurrenceSource) được suy đoán từ `sourceOverrideId` tại renderer — phải gán trực tiếp tại nơi operation chạy (P0-5).
- NEVER re-resolve UTC khi civil time intent (start/end/timezone) không đổi trong UPDATE (P0-2) — resolve lại chỉ khi thực sự có thay đổi giờ/timezone.
- NEVER để một override trong chuỗi chặn việc đánh giá các override tiếp theo, và NEVER rollback các override đã thành công trước đó khi một override sau thất bại (P0-6).

---

## 7. Acceptance Criteria — bản đầy đủ thay thế §8 của `plan3_final.md`

Giữ nguyên toàn bộ các mục đã có trong `plan3_final.md` §8, cộng thêm các mục sau (đánh số nối tiếp):

- [ ] **AC-1** `applyOverride` chỉ có DUY NHẤT signature `OverrideResult applyOverride(...)` trong toàn bộ codebase — không còn tham chiếu `List<ShiftOccurrence> applyOverride`.
- [ ] **AC-2** UPDATE chỉ đổi metadata/template (civil time không đổi) → UTC giữ nguyên tuyệt đối, có test chứng minh không gọi `resolveUtcInstant`.
- [ ] **AC-3** `projectOccurrences` trả `ProjectionResult`; không còn kiểu `ResolvedOccurrence` chứa cả success/error trong công khai API.
- [ ] **AC-4** `OCCURRENCE_NOT_FOUND` tồn tại trong `ErrorCodes` và được trả đúng khi override target không tìm thấy, cho cả 5 operation (UPDATE/DELETE/REPLACE/SPLIT/SWAP).
- [ ] **AC-5** `OccurrenceSource` tách biệt khỏi `sourceOverrideId`; CREATE → `created`, mọi sửa sau đó → `modified`.
- [ ] **AC-6** Override chain: fail của override N không rollback 1..N-1, không chặn N+1; có test cụ thể cho ≥2 chuỗi khác nhau.
- [ ] **AC-7** SPLIT: parts không overlap, đúng thứ tự thời gian, nằm trong envelope gốc (trừ ranh giới nửa đêm hợp lệ); vi phạm → fail atomic.
- [ ] **AC-8** Mọi error code tham chiếu qua `ErrorCodes.xxx`, `grep` không còn literal string trùng các mã đã định nghĩa rải rác trong `pattern_engine.dart`/`time_engine.dart`.
- [ ] **AC-9** `RenderIssue.message` có docstring xác nhận là diagnostic fallback, không phải UI contract.
- [ ] **AC-10** Round-trip property test pass cho NY/Berlin/Lord Howe qua đủ các mốc DST trong 1 năm.
- [ ] **AC-11** `dart test test/core/` pass 100% sau toàn bộ thay đổi trên; số lượng test tăng so với 55 hiện tại (ghi rõ con số mới).

**Gate 0 chỉ đóng khi TẤT CẢ acceptance criteria (cả bản gốc `plan3_final.md` §8 lẫn 11 mục bổ sung trên) đạt và được human review chấp nhận.**

---

## 8. Định nghĩa "xong" — bổ sung 2 mục báo cáo (cộng vào §10 của `plan3_final.md`)

7. Bằng chứng cụ thể cho AC-2 (UPDATE preserve UTC): log/test output cho thấy occurrence tạo tại giờ ambiguous, sau UPDATE-chỉ-đổi-template, UTC bit-for-bit không đổi.
8. Bằng chứng cho AC-6 (override chain atomicity): log test chuỗi 3+ override với 1 override fail ở giữa, cho thấy state trước/sau đúng như quy tắc đã khóa.

---

## 9. Tóm tắt thay đổi so với `plan3_final.md`

| Hạng mục | plan3_final.md | plan3_final_v2.md |
|---|---|---|
| `applyOverride` signature | Mâu thuẫn (2 snippet) | 1 signature duy nhất, `OverrideResult` |
| UPDATE khi chỉ đổi metadata | Luôn re-resolve (bug) | Preserve UTC tuyệt đối nếu civil time không đổi |
| `projectOccurrences` return | Mơ hồ (giữ error entry kiểu gì?) | `ProjectionResult{occurrences, issues}` — resolved-only tuyệt đối |
| Target override không tồn tại | Không xử lý (rủi ro silent no-op) | `OCCURRENCE_NOT_FOUND` bắt buộc |
| Provenance (source vs sourceOverrideId) | Trộn lẫn, CREATE luôn thành 'override' | Tách bạch: `OccurrenceSource` enum riêng, gán tại nguồn |
| Override chain semantics | Chưa định nghĩa | Command-level atomicity, không rollback, không chặn override sau |
| SPLIT invariants | Chưa có | Overlap/order/envelope bắt buộc, fail atomic nếu vi phạm |
| Error code | String rải rác | `ErrorCodes` abstract class (type-safe, tương thích JSON) |
| `RenderIssue.message` | Yêu cầu UI-ready | Diagnostic fallback, docstring rõ ràng |
| Acceptance criteria | ~12 mục | +11 mục mới (AC-1 → AC-11) |

Sau khi patch theo văn bản này, `plan3_final_v2.md` (kết hợp cùng các phần giữ nguyên tham chiếu tới `plan3_final.md` §1, §3, D3/D5/D6/D7(gốc)/D8/D9/D10, §5.1-5.3/5.7, §6.1, §7(gốc), §9) là bộ spec đầy đủ, nhất quán nội bộ, sẵn sàng giao cho AI coding agent thực hiện Gate 0.
