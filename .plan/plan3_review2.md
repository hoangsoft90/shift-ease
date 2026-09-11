plan3_review1.md
MD 8.82KB
plan3.md
MD 20.99KB
phân tích plan3.md và review của các AI khác plan3_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Phân tích tổng hợp `plan3.md` và `plan3_review1.md` – Ý kiến đóng góp & phản biện
=================================================================================

Trước hết, tôi đánh giá rất cao chất lượng của cả hai tài liệu. `plan3.md` đã có một bước "dừng lại" chiến lược vô cùng đúng đắn và minh bạch: phát hiện ra các lỗ hổng domain nghiêm trọng (UTC rỗng, silent drop, giả định ±1h DST) và quyết định **không chuyển sang `core/money`**. Trong khi đó, `plan3_review1.md` đã phản biện sắc bén, đề xuất các giải pháp kiến trúc mạnh mẽ (Pipeline, Gate Strategy, Identity tách biệt).

Tôi hoàn toàn nhất trí với hướng đi chung. Thay vì lặp lại những điểm đã thống nhất, tôi xin đóng góp thêm một số **góc nhìn bổ sung, các lỗ hổng tinh vi chưa được đề cập, và các quyết định kiến trúc cần chốt ngay** để việc "Core Contract Hardening" (Gate 0) thực sự đạt độ vững chắc production.

* * *

1\. Điểm nhất trí tuyệt đối: Mô hình Pipeline và Override Command
-----------------------------------------------------------------

Tôi đặc biệt nhất trí với pipeline do `plan3_review1.md` đề xuất:

> `Override Payload → Validation → Resolve Local Civil Time → TZ Engine → Invariants → Immutable Valid Occurrence`

Đây là một ràng buộc bất biến (invariant) cực kỳ quan trọng: **Sai sót không được phép "trôi dạt" vào domain**. Nếu một `ShiftOccurrence` tồn tại trong danh sách `occurrences`, nó phải là một thực thể "hợp lệ" về mặt thời gian (UTC, timezone đầy đủ). Nếu không, nó chỉ tồn tại dưới dạng `RenderIssue` hoặc `UnresolvedOccurrence`.

* * *

2\. Các bổ sung và phản biện chi tiết (chưa được khai thác triệt để)
--------------------------------------------------------------------

### 🔴 2.1. Nguồn gốc của "Local Time" trong Override – chưa định nghĩa rõ

`plan3.md` và review đều nói về việc "resolve UTC from local civil time", nhưng **không quy định rõ local time được lấy từ đâu** trong các thao tác khác nhau.

*   **Trong `CREATE`**: Local time có thể đến từ `ShiftTemplate` (mẫu ca) hoặc do user nhập thủ công.
    
*   **Trong `UPDATE` / `REPLACE`**: Local time có thể đến từ payload của override, nhưng nếu payload không có thời gian, thì có được giữ nguyên thời gian cũ không? (Trong `plan3.md` đã phát hiện bug rằng `UPDATE` bỏ qua time – vậy phải quyết định rõ: update time có là optional không?).
    

**Đề xuất chốt**:

*   `UPDATE` không bao giờ nên có `time` là optional. Nếu user muốn đổi _chỉ_ template nhưng giữ nguyên giờ, họ sẽ chọn `REPLACE` với `overrideTime: null` hoặc chính là `UPDATE` với `startTime` và `endTime` giữ nguyên từ template cũ.
    
*   Để tránh nhầm lẫn, hãy định nghĩa `UpdateShiftPayload` bắt buộc phải chứa `templateId`, `startTime` và `endTime` (đầy đủ). Việc user chỉ muốn đổi tên ca (mà không đổi giờ) sẽ thực hiện bằng cách chọn template mới có cùng giờ.
    

* * *

### 🟡 2.2. Khái niệm "Work Week" và "Pay Period" – tuyệt đối cần cho Money, nhưng phải chuẩn bị ngay

Cả hai tài liệu đều nói về `core/money` sau, nhưng **kiến trúc dữ liệu cho Money Engine cần được phác thảo ngay từ Gate 0** để tránh phá vỡ Domain Model sau.

*   **Work Week:** Overtime (OT) ở Mỹ thường tính theo tuần (40 giờ/tuần). Tuy nhiên, "tuần" bắt đầu từ Chủ nhật hay Thứ hai còn tùy thuộc vào tiểu bang / hợp đồng.
    
*   **Pay Period:** Có thể là tuần, hai tuần, nửa tháng, hoặc tháng.
    

**Đề xuất chốt**: Thêm một thực thể `PayContext` thuộc về `Job`:

dart

Copy

Download

class PayContext {
  final DayOfWeek workWeekStart; // Monday hoặc Sunday
  final PayPeriodType periodType; // WEEKLY, BIWEEKLY, SEMIMONTHLY, MONTHLY
  final int overtimeThresholdHours; // mặc định 40
  final Duration shiftBreakMinimum; // thời gian nghỉ tối thiểu giữa các ca để tính phụ cấp (nếu có)
}

Tham số này không dùng trong Gate 0, nhưng `ShiftOccurrence` và `ShiftTemplate` cần liên kết được với `Job` (đã có). Khi sang Gate 1 (Money), chỉ việc chạy `List<ShiftOccurrence>` qua `PayCalculator` với `PayContext` này.

* * *

### 🔴 2.3. Định nghĩa rõ "Projection" (Occurrence sinh ra) vs "Materialized View"

`plan3.md` đề cập đến `projectOccurrences()`, nhưng chưa quyết định kiến trúc lưu trữ:

*   **Cách 1 (On-the-fly):** Luôn generate từ Pattern + Overrides khi render. Đảm bảo source of truth là Pattern/Overrides, nhưng có thể chậm với 12 tháng.
    
*   **Cách 2 (Materialized):** Lưu các `ShiftOccurrence` đã resolve vào DB. Dễ query, nhưng khi Override thay đổi, phải tính toán và cập nhật lại chuỗi.
    

**Đề xuất chốt**:  
Sử dụng **Materialized View với Incremental Update**. Các occurrence được sinh ra và lưu vào bảng `occurrences` (với `sourcePatternId` và `version`). Khi Override thay đổi, hệ thống xóa các occurrence từ ngày áp dụng trở đi và regenerate. Tuy nhiên, nếu có occurrence cũ đã được user "đóng băng" (hoặc có các ca đã qua), cần tránh tự động sửa lịch sử. Điều này quay lại yêu cầu về `effectiveFrom` của Pattern/Override.

* * *

### 🟡 2.4. `DELETE` semantics cần rõ ràng hơn

`plan3.md` liệt kê DELETE là một operation. Nhưng trong mô hình `Override`, nếu một ngày bị delete, ta sẽ làm gì?

*   Xóa hẳn `ShiftOccurrence` khỏi danh sách?
    
*   Hay đánh dấu `isDeleted = true` để giữ lại dấu vết audit?
    

**Đề xuất chốt**:  
Giữ lại bản ghi `ShiftOccurrence` với trạng thái `deletedAt` hoặc `isActive = false`. Lý do:

*   User có thể undo.
    
*   Dễ dàng hiển thị "Lịch sử thay đổi" (What changed?).
    
*   Không phá vỡ logic ID tham chiếu nếu đã lưu vào DB.
    

* * *

### 🟢 2.5. Về ID strategy – tôi đồng ý và bổ sung thêm chi tiết

Review đề xuất `occurrenceId` (UUID) và `projectionHash`. Tôi muốn nhấn mạnh thêm:

*   **`projectionHash`** nên được tính dựa trên **`patternId + shiftDate + templateId`** tại thời điểm sinh ra. Khi một override thay đổi, hash của override sẽ khác.
    
*   **`parentOverrideId`** có thể được thêm vào `Override` để tạo thành một linked list (dùng cho Undo/Redo).
    

* * *

### 🔴 2.6. Kiểm thử (Testing) – cần một "Test Harness" được xây dựng trước khi AI sửa code

Cả hai tài liệu đều nhấn mạnh Golden Tests, nhưng tôi đề xuất một bước cụ thể hơn:

**Tạo một thư mục `/test_harness` chứa các file `.json` hoặc `.yaml` mô tả kịch bản.**

Ví dụ một file `test_dst_nonexistent.yaml`:

yaml

Copy

Download

input:
  timezone: America/New\_York
  date: 2026-03-08
  start\_time: 02:30
  end\_time: 06:00
expected:
  status: NONEXISTENT\_LOCAL\_TIME
  occurrences: \[\] 
  issues:
    \- type: DST\_NONEXISTENT
      local\_time: 02:30

Và file `test_swap_semantics.yaml`:

yaml

Copy

Download

setup:
  occ\_A: { date: 2026-09-01, template: NIGHT, tz: NY }
  occ\_B: { date: 2026-09-02, template: DAY, tz: LDN }
command: SWAP(occ\_A, occ\_B)
expected:
  occ\_A\_new: { date: 2026-09-01, template: DAY, tz: NY, start\_utc: ... } // note: template swapped, not timezone
  occ\_B\_new: { date: 2026-09-02, template: NIGHT, tz: LDN, start\_utc: ... }

**Yêu cầu Gate 0**: Toàn bộ AI agent sửa code đều phải chạy `test_harness` và pass 100%. Đây là "Hợp đồng bất biến" dạng thực thi, tránh việc AI chỉ nhìn comment mà hiểu sai.

* * *

3\. Bổ sung về UX/UI từ góc độ production (bên cạnh các gợi ý của review)
-------------------------------------------------------------------------

Tôi đề xuất bổ sung các tính năng sau vào danh sách xây dựng (sau Gate 0, 1):

*   **"Day Overview" khi nhấn vào một ngày:** Không chỉ hiển thị danh sách ca, mà hiển thị tổng số giờ làm trong ngày, số giờ nghỉ giữa các ca.
    
*   **"Shift Draft" (Nháp):** User có thể tạo một ca nhưng chưa có thời gian đầy đủ (ví dụ: đang chờ xác nhận lịch từ sếp). Các draft này được lưu riêng, không ảnh hưởng đến `Effective Schedule` cho đến khi được xác nhận. (Giúp tránh tạo ra các `Occurrence` rỗng).
    
*   **"Paste & Review" Flow chi tiết hơn:** Khi user paste text, hiển thị bảng xem trước có checkbox để chọn ca nào được import, ca nào bỏ qua. Điều này mạnh hơn chỉ review toàn bộ.
    

* * *

4\. Kết luận và Hành động tiếp theo (Prompt cho AI agent)
---------------------------------------------------------

Tôi đánh giá `plan3.md` và `plan3_review1.md` đã xác định chính xác điểm dừng và phương hướng. Để tránh cả hai bị "quên" trong quá trình code với AI agent, tôi đề xuất **prompt cụ thể cho bước tiếp theo** như sau:

> **Nhiệm vụ: ShiftEase Core Contract Hardening – Gate 0**
> 
> 1.  **Sửa `ShiftOccurrence`**:
>     
>     *   Bỏ các trường `startDateTimeUtc`, `endDateTimeUtc`, `timezone` khỏi `ShiftOccurrence` và thay thế bằng một object `TemporalInstant` chứa `utcStart`, `utcEnd`, `timezone` (bắt buộc phải có).
>         
>     *   Tạo một enum `ResolutionStatus` có thể là `RESOLVED` (có UTC) hoặc `UNRESOLVED` (chứa lý do lỗi). Đảm bảo domain chỉ nhận `RESOLVED` instances.
>         
> 2.  **Override Command Pipeline**:
>     
>     *   Implement `OverrideProcessor` nhận `CreateCommand`, `UpdateCommand`, `SplitCommand`, v.v.
>         
>     *   Mỗi Command đều chứa `localCivilTime` (dạng `TimeOfDay` + `DateTime` local).
>         
>     *   Sử dụng `TimeZoneResolver` để xử lý DST (loại bỏ ±1h hard-coded, thay vào đó dùng `localTime.inTimeZone(tz).possibleUtcInstants()` để trả về 0, 1, hoặc 2 giá trị).
>         
>     *   Nếu trả về 0 hoặc 2, _không_ tạo occurrence mà báo lỗi và yêu cầu user can thiệp (cho phép user chọn một trong 2 nếu ambiguous).
>         
> 3.  **Effective Schedule Renderer**:
>     
>     *   Đổi tên `renderEffectiveSchedule` thành `buildScheduleView`.
>         
>     *   Trả về `ScheduleViewResult` chứa `resolvedOccurrences` và `issues` (DST, missing template, etc.).
>         
>     *   Xóa bỏ `.where((r) => r.isSuccess)` – UI sẽ hiển thị danh sách ca và danh sách lỗi kèm icon cảnh báo.
>         
> 4.  **Test Harness**:
>     
>     *   Tạo ít nhất 20 test cases trong thư mục `test/golden` bao gồm:
>         
>         *   DST Spring forward (nonexistent).
>             
>         *   DST Fall back (ambiguous).
>             
>         *   Timezone lệch 30/45 phút.
>             
>         *   Swap với múi giờ khác nhau (không copy UTC).
>             
>         *   Split một ca đêm xuyên nửa đêm.
>             
>         *   Update một ca và kiểm tra UTC được tính lại.
>             
>     *   Tất cả test đều phải pass sau khi sửa code.
>         

Sau khi các tiêu chí trên được thỏa mãn và mọi test pass, chúng ta mới bắt đầu viết spec cho `core/money` (Gate 1).

* * *

**Tóm lại**: Dự án đang đi đúng hướng. Điểm cốt lõi cần nhấn mạnh lại là **"Không cho phép bất kỳ đối tượng thời gian không xác định (UTC rỗng) nào tồn tại trong domain"** và **"Không bao giờ ngầm nuốt lỗi DST trong render"**. Việc áp dụng Gate Strategy sẽ đảm bảo sản phẩm cuối cùng không chỉ chạy được mà còn **đáng tin cậy** – đúng với tên gọi **ShiftEase**.