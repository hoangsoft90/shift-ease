phân tích plan3.md và review của các AI khác plan3_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Worked for 26s

**Phân tích tổng hợp plan3.md + plan3\_review1 + plan3\_review2**

Tôi đã đọc kỹ cả ba tài liệu. Đây là vòng review chất lượng cao nhất từ trước đến nay vì đã chuyển từ “ý tưởng sản phẩm” sang **đối chiếu implementation thực tế**.

* * *

### 1\. Verdict tổng thể

**Tôi hoàn toàn nhất trí với quyết định chiến lược quan trọng nhất:**

> **TUYỆT ĐỐI DỪNG, KHÔNG CHUYỂN SANG core/money LÚC NÀY.**

features.md đang “đánh dấu ✅ hơi rộng”. Việc có skeleton + một số test pass **không đồng nghĩa** với domain contract đã production-safe. Các lỗi hiện tại (UTC rỗng, silent drop, UPDATE bỏ qua time, ±1h DST) là **lỗi nền móng**. Xây Money/UI lên trên sẽ tạo ra technical debt cực kỳ đắt.

Điểm hiện tại tôi đánh giá:

| Khu vực | Điểm | Ghi chú |
| --- | --- | --- |
| Time Engine | 6.5/10 | Có skeleton tốt, nhưng DST resolution còn assumption nguy hiểm |
| Pattern + Override | 5.5/10 | Kiến trúc đúng hướng, implementation còn nhiều lỗ hổng nghiêm trọng |
| Effective Schedule | 4/10 | Contradiction trực tiếp giữa comment và runtime |
| Test Strategy | 7.5/10 | Đã có golden tests, nhưng chưa đủ coverage cho negative cases |
| Production readiness | 3–4/10 | Core contract chưa khóa |

* * *

### 2\. Các lỗi domain tôi xác nhận là P0 (phải sửa trước mọi thứ)

Tôi đồng ý 100% với các phát hiện chính trong plan3.md và hai review:

#### Lỗi 1 — Temporal Identity bị phá hủy

*   CREATE và SPLIT đang tạo ShiftOccurrence với startDateTimeUtc = '', endDateTimeUtc = '', timezone = ''.
*   Đây là vi phạm trực tiếp Correctness Contract.
*   **Quy tắc mới phải khóa cứng:** Một ShiftOccurrence tồn tại trong domain **bắt buộc** phải có temporal identity đầy đủ. Nếu chưa resolve được UTC → chỉ tồn tại dưới dạng UnresolvedOccurrence / RenderIssue, không được đưa vào danh sách occurrence hợp lệ.

#### Lỗi 2 — Silent drop trong renderEffectiveSchedule

*   Comment nói “NEVER silently drop”, runtime lại .where((r) => r.isSuccess).
*   Đây là contradiction kiến trúc, không chỉ là bug.
*   **Chọn Option B** (như cả hai review đề xuất): Trả về ScheduleRenderResult { occurrences, issues }. UI phải có khả năng hiển thị cả ca hợp lệ lẫn cảnh báo.

#### Lỗi 3 — DST ±1 hour assumption

*   Tự suy ra alternative UTC bằng ±1 hour là sai với các timezone lệch 30/45 phút (Lord Howe, Nepal, v.v.).
*   Phải dùng timezone database để lấy **0 / 1 / 2 candidate UTC instants** thực sự.

#### Lỗi 4 — UPDATE / REPLACE chưa xử lý time đầy đủ

*   \_applyUpdate chỉ đổi templateId, bỏ qua startTime/endTime.
*   REPLACE cũng chưa áp dụng overrideTime.
*   Đây là bug “silent no-op” cực nguy hiểm vì UI có thể báo “Saved successfully”.

#### Lỗi 5 — SWAP semantics chưa rõ

*   Hiện tại đang copy cả UTC + timezone.
*   **Định nghĩa đúng:** SWAP = trao đổi **Local Civil Intent** (template + local time), sau đó **re-resolve UTC** theo timezone của từng occurrence.

* * *

### 3\. Những điểm tôi bổ sung / phản biện thêm

#### 3.1. Override phải trở thành Command Pipeline, không còn là “manipulate list”

Tôi đồng ý mạnh với pipeline do review1 đề xuất, và muốn khóa rõ hơn:

text

CopyCopied

    OverrideCommand
      → Validate payload (format, range, required fields)
      → Resolve Local Civil Time (từ Template hoặc payload)
      → TimeZoneResolver → 0/1/2 UTC candidates
      → Nếu 0 hoặc 2 candidates → trả về Issue (không tạo Occurrence)
      → Nếu 1 candidate → Apply invariants
      → Output: Immutable Valid ShiftOccurrence(s)

**Quy tắc bất biến mới:**  
Domain chỉ nhận **Resolved Occurrence**. Mọi thứ chưa resolve được phải ở lớp Issue hoặc Draft.

#### 3.2. Nguồn Local Time trong từng operation phải được định nghĩa rõ

Review2 đã chạm đến điểm này. Tôi chốt thêm:

| Operation | Local Time nguồn | Quy tắc |
| --- | --- | --- |
| CREATE | Từ ShiftTemplate hoặc user input | Bắt buộc có |
| UPDATE | Payload phải chứa đầy đủ startTime + endTime (không optional) | Nếu chỉ muốn đổi template mà giữ giờ → dùng template mới có cùng giờ, hoặc REPLACE |
| REPLACE | Có thể có overrideTime (optional) | Nếu không có → lấy giờ từ template mới |
| SPLIT | Tính từ thời điểm split | Mỗi phần phải resolve độc lập |
| SWAP | Lấy local time của đối phương | Re-resolve theo timezone của occurrence đích |

#### 3.3. Materialized vs On-the-fly

Tôi nghiêng về **Materialized View với Incremental Update** (như review2 đề xuất), nhưng có điều kiện:

*   Occurrence đã qua (past) **không bao giờ** bị regenerate tự động.
*   Chỉ regenerate từ effectiveFrom trở đi.
*   Cần có sourcePatternId + projectionVersion để truy vết.

#### 3.4. DELETE semantics

Nên soft-delete (deletedAt hoặc isActive = false) thay vì hard delete. Lý do:

*   Hỗ trợ Undo.
*   Hỗ trợ “What changed?” timeline.
*   Giữ được audit trail.

#### 3.5. Test Harness phải được xây trước khi AI sửa code

Tôi rất ủng hộ ý tưởng YAML/JSON test harness của review2. Gate 0 chỉ được coi là xanh khi:

*   Có ít nhất 20–30 golden cases bao gồm:
    *   DST spring-forward (nonexistent)
    *   DST fall-back (ambiguous)
    *   Timezone lệch 30/45 phút
    *   SWAP cross-timezone
    *   SPLIT overnight
    *   UPDATE time
    *   Invalid input vs DST error (phải phân biệt)
*   Tất cả test pass 100%.
*   Không còn bất kỳ ShiftOccurrence nào có UTC/timezone rỗng trong domain.

#### 3.6. Chuẩn bị nhẹ cho Money ngay từ Gate 0

Không implement Money, nhưng nên chừa chỗ:

Dart

CopyCopied

    class PayContext {
      final DayOfWeek workWeekStart;
      final PayPeriodType periodType;
      final int overtimeThresholdHours;
    }

Gắn vào Job. Khi sang Gate 1 chỉ việc truyền List<ShiftOccurrence> + PayContext vào calculator.

* * *

### 4\. Đánh giá các đề xuất UX/UI

Các đề xuất trong plan3.md và review1 đều rất tốt và hướng production. Tôi ưu tiên theo thứ tự:

**Nên làm sớm (sau Gate 0–1):**

*   Next Shift + Countdown trên Today (signature UX)
*   “Why this shift?” (cực hợp với Correctness Contract)
*   Pay Breakdown chi tiết
*   System-wide Undo
*   Conflict / Duplicate detection
*   Local encrypted backup

**Có thể để sau:**

*   Recovery indicator (rule-based, không medical)
*   Full “What changed?” timeline
*   Draft shift (chưa confirm)

**Lưu ý:** Tất cả UX chỉ nên bắt đầu sau khi Core Contract đã xanh. Không để AI agent xây UI dựa trên occurrence có UTC rỗng.

* * *

### 5\. Chiến lược Gate (tôi tinh chỉnh nhẹ)

Tôi đồng ý với hướng 6 Gate của review1, nhưng khóa rõ hơn cho giai đoạn hiện tại:

| Gate | Mục tiêu | Acceptance Criteria chính |
| --- | --- | --- |
| **Gate 0** (hiện tại) | Core Contract Hardening | Zero empty temporal fields · 6 operations resolve 100% · No silent drop · DST 0/1/2 candidates đúng · Phân biệt Invalid vs DST error · Golden tests pass |
| Gate 1 | Money Engine | PayRule versioned · Breakdown · Snapshot historical · Không double-count |
| Gate 2 | Persistence | SQLite + migrations + transaction + backup/restore |
| Gate 3 | Domain Model hoàn chỉnh | Job · CalendarEvent · TimeOff · Availability |
| Gate 4 | Calendar UX | Today · Week/Month · Quick Add · Pattern Builder |
| Gate 5 | Import + Production | Smart Paste/CSV/OCR Review · Notifications · Settings · Security |

**Hành động ngay:** Chỉ mở prompt cho **Gate 0**. Không cho agent đụng đến Money, UI, Persistence cho đến khi Gate 0 được verify xanh hoàn toàn (kể cả review thủ công).

* * *

### 6\. Kết luận & Hành động đề xuất

1.  **Dừng mọi việc liên quan đến core/money và UI.**
2.  **Khởi động ngay task “ShiftEase Core Contract Hardening — Gate 0”** với acceptance criteria chặt như đã liệt kê ở trên.
3.  Xây **Test Harness** (YAML/JSON) trước hoặc song song với việc sửa code.
4.  Khóa cứng các quyết định:
    *   Occurrence trong domain phải luôn Valid.
    *   Render trả về cả occurrences + issues.
    *   SWAP = civil-time swap + re-resolve.
    *   Soft-delete.
    *   Materialized + incremental từ effectiveFrom.
5.  Chỉ khi Gate 0 xanh → mới viết spec Gate 1 (Money).

**Tóm lại:**  
plan3.md đã làm đúng việc quan trọng nhất: **dừng lại đúng lúc**. Hai review đã nâng chất lượng phân tích lên mức kiến trúc production.

Bây giờ ưu tiên số 1 là biến Core Contract thành thứ **không thể bị phá** bởi AI agent. Chỉ khi nền móng Time + Pattern + Override + Effective Schedule thực sự vững, ShiftEase mới xứng với tên gọi “Ease” và positioning “đáng tin cậy”.

Bạn muốn tôi viết luôn bản **prompt chi tiết cho AI agent thực hiện Gate 0** (bao gồm acceptance criteria, NEVER list, và cấu trúc test harness) không?
--------------------
Dưới đây là **prompt chi tiết, sẵn sàng copy-paste** cho AI coding agent thực hiện **Gate 0**.

---

```markdown
# TASK: ShiftEase — Core Contract Hardening (Gate 0)

## 1. Mục tiêu tuyệt đối

Khóa cứng **Core Domain Contract** của ShiftEase trước khi được phép phát triển bất kỳ module nào khác (`core/money`, Persistence, UI, Import…).

Sau khi hoàn thành Gate 0:
- Mọi `ShiftOccurrence` tồn tại trong domain **bắt buộc** phải có temporal identity đầy đủ (UTC start/end + timezone hợp lệ).
- Không còn silent drop lỗi DST / unresolved.
- 6 operations Override (`CREATE`, `UPDATE`, `DELETE`, `REPLACE`, `SPLIT`, `SWAP`) hoạt động deterministic và production-safe.
- Time Engine không còn giả định ±1 hour.

**KHÔNG được** đụng vào:
- `core/money`
- UI / screens
- Persistence schema lớn
- Import / OCR
- Notifications

Chỉ sửa trong phạm vi: `core/time`, `core/pattern`, Override pipeline, Effective Schedule renderer, và test suite tương ứng.

---

## 2. Các lỗi bắt buộc phải sửa (P0)

### 2.1. Empty Temporal Identity (Critical)
Hiện tại `_applyCreate()` và SPLIT đang tạo:
```dart
startDateTimeUtc: '',
endDateTimeUtc: '',
timezone: '',
```
→ **Cấm tuyệt đối**. Không được tồn tại `ShiftOccurrence` hợp lệ với UTC/timezone rỗng.

### 2.2. Silent Drop trong render
`renderEffectiveSchedule()` đang `.where((r) => r.isSuccess)` → mâu thuẫn trực tiếp với comment “NEVER silently drop”.

### 2.3. UPDATE bỏ qua time
`_applyUpdate()` chỉ đổi `templateId`, bỏ qua `startTime`/`endTime` trong payload.

### 2.4. REPLACE chưa áp dụng overrideTime đầy đủ.

### 2.5. DST ±1 hour assumption
Không được suy ra alternative UTC bằng `± Duration(hours: 1)`. Phải dùng timezone database để lấy đúng 0 / 1 / 2 candidate instants (hỗ trợ offset 30/45 phút).

### 2.6. SWAP đang copy UTC + timezone
Phải đổi thành: swap **Local Civil Intent** → re-resolve UTC theo timezone của từng occurrence đích.

---

## 3. Quyết định kiến trúc đã khóa (KHÔNG được thay đổi)

### D1 — Temporal Identity
- Mọi `ShiftOccurrence` trong domain phải luôn **Resolved**.
- Nếu không resolve được → chỉ tồn tại dưới dạng `RenderIssue` / `UnresolvedOccurrence`, không được đưa vào list occurrence hợp lệ.

### D2 — Override = Command Pipeline
Mọi operation phải đi qua pipeline thống nhất:

```
OverrideCommand
  → Validate payload
  → Resolve Local Civil Time
  → TimeZoneResolver (0/1/2 candidates)
  → Nếu 0 hoặc 2 → trả Issue (không tạo Occurrence)
  → Nếu 1 → Apply invariants
  → Output: Immutable Valid ShiftOccurrence(s)
```

### D3 — Local Civil Time là source-of-truth của schedule
Recurrence và override chạy theo wall-clock local time, không phải UTC interval.

### D4 — Effective Schedule trả về Result
```dart
class ScheduleRenderResult {
  final List<ShiftOccurrence> occurrences; // chỉ các ca Resolved
  final List<RenderIssue> issues;          // DST_NONEXISTENT, AMBIGUOUS, MISSING_TEMPLATE, INVALID_*, ...
}
```

### D5 — SWAP semantics
SWAP = trao đổi template + local civil time → **re-resolve** UTC theo timezone của occurrence đích.  
**Không** copy cứng UTC từ A sang B.

### D6 — DELETE = Soft delete
Giữ bản ghi với `deletedAt` / `isActive = false` (phục vụ Undo + audit). Không hard-delete.

### D7 — Error Classification
Phải phân biệt rõ:
- `INVALID_DATE` / `INVALID_TIME` / `INVALID_TIMEZONE`
- `NONEXISTENT_LOCAL_TIME` (DST spring-forward)
- `AMBIGUOUS_LOCAL_TIME` (DST fall-back)
- `END_BEFORE_START`
- `MISSING_TEMPLATE`

---

## 4. Acceptance Criteria (Gate 0 chỉ xanh khi TẤT CẢ đạt)

- [ ] Không còn bất kỳ `ShiftOccurrence` nào trong domain có `startDateTimeUtc` / `endDateTimeUtc` / `timezone` rỗng hoặc null.
- [ ] `CREATE` luôn produce occurrence(s) đã resolve UTC đầy đủ (hoặc trả Issue rõ ràng).
- [ ] `UPDATE` xử lý được cả thay đổi template **và** thay đổi time.
- [ ] `REPLACE` hỗ trợ `overrideTime` (optional). Nếu có → resolve lại UTC.
- [ ] `SPLIT` tạo ra các phần đều có temporal identity hợp lệ.
- [ ] `SWAP` dùng civil-time semantics + re-resolve (không copy UTC).
- [ ] `DELETE` là soft-delete.
- [ ] `renderEffectiveSchedule` (hoặc tên mới `buildScheduleView`) trả về `ScheduleRenderResult` chứa cả `occurrences` và `issues`. Không silent drop.
- [ ] TimeZoneResolver trả về đúng 0 / 1 / 2 candidates từ timezone DB (không ±1h hard-code). Hỗ trợ offset 30/45 phút.
- [ ] Phân biệt rõ Invalid input vs DST Nonexistent / Ambiguous.
- [ ] Tất cả golden tests + property tests + integration tests hiện có **và** bộ test mới (xem mục 5) đều pass 100%.
- [ ] Không có regression trên các case DST đã có.

---

## 5. Test Harness bắt buộc

Tạo / mở rộng thư mục `test/golden/` (hoặc `test/harness/`) với các file mô tả kịch bản (JSON hoặc YAML).

Tối thiểu phải cover:

1. DST Spring-forward (nonexistent local time) — America/New_York 2026-03-08 02:30
2. DST Fall-back (ambiguous) — America/New_York 2026-11-01 01:30
3. Timezone lệch 30 phút (Australia/Lord_Howe hoặc tương đương)
4. Timezone lệch 45 phút (Asia/Kathmandu nếu có)
5. Overnight shift bình thường (không DST)
6. Overnight shift bắc qua DST
7. CREATE với template → UTC resolved đúng
8. UPDATE chỉ đổi time (giữ template)
9. UPDATE đổi cả template + time
10. REPLACE với và không có overrideTime
11. SPLIT một ca ngày và một ca đêm overnight
12. SWAP hai ca khác timezone → UTC được re-resolve, không bị copy
13. DELETE → soft-delete, vẫn truy xuất được trong history
14. Invalid date / invalid time / end-before-start → lỗi đúng loại
15. Missing template → RenderIssue
16. Pattern versioning edge (effectiveFrom) — occurrence sau ngày đổi không bị lệch sai

Mỗi test phải có:
- input rõ ràng
- expected `occurrences` (nếu có)
- expected `issues` (nếu có)
- expected UTC values cụ thể khi resolve thành công

**Yêu cầu:** Sau khi sửa code, chạy toàn bộ harness → 100% pass. Không được xóa hoặc skip test để “làm xanh”.

---

## 6. NEVER List (AI agent tuyệt đối không được làm)

- NEVER tạo `ShiftOccurrence` với UTC hoặc timezone rỗng/null.
- NEVER silent drop unresolved occurrence trong render.
- NEVER dùng `± Duration(hours: 1)` để suy ra alternative UTC.
- NEVER copy cứng UTC khi SWAP.
- NEVER hard-delete occurrence (phải soft-delete).
- NEVER để `UPDATE` bỏ qua trường time trong payload.
- NEVER trộn pay semantics vào ShiftTemplate / Occurrence trong Gate này.
- NEVER thay đổi public API của Money hoặc UI.
- NEVER đánh dấu feature ✅ nếu chưa có test + acceptance scenario tương ứng.

---

## 7. Hướng dẫn triển khai gợi ý (không bắt buộc cấu trúc file cụ thể)

1. Tạo / củng cố `TimeZoneResolver` (hoặc tương đương) trả về `List<UtcInstant>` (0, 1 hoặc 2 phần tử) + lý do.
2. Tạo `OverrideProcessor` / Command handlers cho 6 operations, tất cả đi qua pipeline resolve.
3. Đổi `ShiftOccurrence` (hoặc wrapper) để temporal fields trở thành non-nullable khi ở trạng thái Resolved.
4. Đổi renderer thành trả `ScheduleRenderResult`.
5. Viết / cập nhật golden tests trước hoặc song song.
6. Chạy full test suite → sửa cho đến khi xanh hoàn toàn.
7. Cập nhật `features.md`: đổi trạng thái các mục Override / Time Engine từ ✅ thành chính xác (🟡 Hardened / ✅ Verified only when criteria met).

---

## 8. Định nghĩa xong Gate 0

Khi tất cả Acceptance Criteria ở mục 4 đều ✅ và test harness 100% pass, hãy báo cáo:

- Tóm tắt các thay đổi chính
- Danh sách test cases đã thêm
- Xác nhận không còn empty temporal fields
- Xác nhận không còn silent drop
- Xác nhận SWAP / UPDATE / SPLIT / REPLACE đã đúng semantics

**Chỉ sau khi báo cáo này được review và chấp nhận thì mới được mở Gate 1 (`core/money`).**

Bắt đầu làm việc.
```

---

Prompt trên đã khóa chặt các quyết định kiến trúc, liệt kê rõ lỗi phải sửa, acceptance criteria, test harness và NEVER list. Bạn có thể copy nguyên khối và giao cho AI coding agent.

Bạn muốn tôi điều chỉnh thêm phần nào (ví dụ thêm chi tiết về cấu trúc file Dart hiện tại, hoặc siết chặt hơn nữa về soft-delete / projection identity) không?
