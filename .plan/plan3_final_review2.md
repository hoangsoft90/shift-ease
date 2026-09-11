phân tích solution plan3_final.md và review của các AI khác plan3_final_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
`plan3_final.md` đã thực hiện một bước tiến kiến trúc xuất sắc: chuyển đổi toàn bộ quy trình từ suy đoán định tính sang kiểm chứng bằng bằng chứng thực nghiệm (probe code thật trên package `timezone 0.9.4`, khóa biên độ Gate 0, chặn `core/money`).

MD\+ 1

Tuy nhiên, đánh giá từ `plan3_final_review1.md` là **hoàn toàn chính xác và đáng giá**: nếu bàn giao nguyên xi `plan3_final.md` cho AI coding agent, hệ thống sẽ gặp hiện tượng **"xanh test nhưng sai ngữ nghĩa domain"** do tồn tại 6 mâu thuẫn spec và điểm hở semantics nghiêm trọng.

MD\+ 1

1\. Ma trận Phân tích: `plan3_final.md` vs `plan3_final_review1.md`
-------------------------------------------------------------------

| Hạng mục Domain | 
Trạng thái trong `plan3_final.md`

MD





 | 

Phản biện trong `review1.md`

MD





 | Đánh giá & Chốt giải pháp Kiến trúc |
| --- | --- | --- | --- |
| **`applyOverride` Contract** | 

Đoạn trên ghi `List<ShiftOccurrence>`, đoạn dưới chốt `OverrideResult`.

MD





 | 

**P0 (Critical):** Mâu thuẫn trực tiếp làm agent chọn ngẫu nhiên code snippet.

MD





 | 

**Sửa ngay:** Xóa bỏ hoàn toàn snippet cũ. Bắt buộc dùng `OverrideResult applyOverride(...)`.

MD





 |
| **Provenance Tagging (D4)** | 

`sourceOverrideId = override.id`, nhưng `source` lại quy định `createdIds -> 'created'`.

MD





 | 

**P0 (Critical):** Phân loại sai mọi ca `CREATE` thành `override`, mất vết ca tạo thủ công.

MD





 | 

**Tách biệt:** Tách `OccurrenceSource` (`baseline`, `created`, `modified`) khỏi `sourceOverrideId` (audit trail).

MD





 |
| **UPDATE Temporal Semantics** | 

Bắt buộc re-resolve thời gian UTC kể cả khi chỉ cập nhật metadata/template.

MD





 | 

**P0 (Critical):** Gây lỗi `AMBIGUOUS_LOCAL_TIME` giả lập khi user chỉ sửa tên ca trong vùng DST.

MD





 | 

**Bảo toàn UTC:** Giữ nguyên tUTC​ tuyệt đối nếu civil time không đổi. Chỉ re-resolve khi tstart​,tend​ thay đổi.

MD





 |
| **Resolved-only Domain (D1)** | 

Tuyên bố "resolved-only", nhưng `projectOccurrences` trả occurrence lỗi rồi renderer giữ lại.

MD





 | 

**P0 (Critical):** Vi phạm D1, để lọt occurrence có UTC rỗng vào domain.

MD





 | 

**Chốt contract:** `projectOccurrences` trả `ProjectionResult` gồm `occurrences` (chỉ ca hợp lệ) + `issues`.

MD





 |
| **Target Identity Missing** | 

Chưa quy định xử lý khi override trỏ tới `occurrenceId` không tồn tại.

MD





 | 

**P0 (Critical):** Nguy cơ silent no-op khi ID bị trôi dạt qua chuỗi override.

MD





 | 

**Thêm Error:** Bổ sung mã lỗi `OCCURRENCE_NOT_FOUND`.

MD





 |
| **SPLIT Invariants** | 

Chưa siết quy tắc overlap, thứ tự thời gian giữa các part sau khi chia ca.

MD





 | 

**P1 (High):** Nguy cơ tính trùng lương (double-counting) hoặc ca chồng lấp.

MD





 | 

**Siết Invariant:** Parts không overlap, đúng thứ tự thời gian t1​<t2​, nằm trong khung giờ gốc.

MD





 |

2\. Phân tích Chi tiết & Giải pháp Tinh chỉnh 6 Điểm P0/Critical
----------------------------------------------------------------

### 🟢 P0-1: Chuẩn hóa Duy nhất Signature `applyOverride`

Xóa bỏ hoàn toàn mọi snippet trả về `List<ShiftOccurrence>`. Đóng khung signature bắt buộc cho agent:

MD\+ 1

Dart

    OverrideResult applyOverride(
      List<ShiftOccurrence> occurrences,
      Override override, {
      required Map<String, ShiftTemplate> templates,
    })

### 🟢 P0-2: Tách biệt Business Source Tagging và Audit Provenance

Phân định rõ hai khái niệm bị nhập nhằng ở D4:

MD\+ 1

*   `sourceOverrideId` (String?): Chỉ đóng vai trò truy vết ID của override command gần nhất can thiệp vào occurrence.
    
    MD\+ 1
    
*   `source` (`OccurrenceSource` Enum): Định danh bản chất kinh doanh:
    
    MD
    
    *   `baseline`: Sinh ra từ Pattern projection gốc.
        
        MD
        
    *   `created`: Sinh ra từ thao tác `CREATE` thủ công.
        
        MD
        
    *   `modified`: Sinh ra từ `UPDATE`, `REPLACE`, `SPLIT`, `SWAP`.
        
        MD
        

### 🟢 P0-3: Quy tắc Bảo toàn UTC khi UPDATE Metadata

Khi thực hiện `UPDATE`, Time Engine phải kiểm tra ý định thời gian (civil time intent):

MD

If (tstart\_new​\=tstart\_old​)∧(tend\_new​\=tend\_old​)∧(tznew​\=tzold​)⟹tUTC\_new​\=tUTC\_old​

Nếu civil time không đổi, **giữ nguyên tUTC​ tuyệt đối đã lưu**, tuyệt đối không chạy lại hàm `resolveUtcInstant`. Việc này triệt tiêu hoàn toàn rủi ro bắn lỗi `AMBIGUOUS_LOCAL_TIME` vô lý khi người dùng chỉ muốn đổi màu/tên ca làm việc trong các ngày đổi giờ DST.

MD\+ 1

### 🟢 P0-4: Khóa Airtight cho D1 "Resolved-Only Domain"

Sửa contract của `projectOccurrences` để đảm bảo không một `ShiftOccurrence` chứa UTC/timezone rỗng nào được instanciate:

MD\+ 1

Dart

    class ProjectionResult {
      final List<ShiftOccurrence> occurrences; // 100% Valid & Resolved
      final List<RenderIssue> issues;           // Lỗi DST gap, missing template...
    }

pipeline xử lý dữ liệu phải tuân theo sơ đồ tuyến tính: `Pattern` → `projectOccurrences()` → `ProjectionResult` → `applyOverrides()` → `ScheduleRenderResult`.

MD

### 🟢 P0-5: Bổ sung `OCCURRENCE_NOT_FOUND` và Định nghĩa Atomicity cho Override Chain

*   **Mã lỗi mới:** `OCCURRENCE_NOT_FOUND` được kích hoạt khi một Override Command (`UPDATE`, `DELETE`, `REPLACE`, `SPLIT`, `SWAP`) trỏ tới một `occurrenceId` không tồn tại trong danh sách hiện tại.
    
    MD
    
*   **Nguyên tắc Nguyên tử (Command-level Atomicity):** Mỗi command trong chuỗi Override Log được đánh giá độc lập. Nếu Command N thất bại (bắn lỗi `OCCURRENCE_NOT_FOUND` hoặc `AMBIGUOUS_LOCAL_TIME`), danh sách ca làm việc của Command N−1 được giữ nguyên, lỗi của Command N được ghi nhận vào `issues`, và Engine tiếp tục đánh giá Command N+1.
    
    MD\+ 1
    

### 🟢 P0-6: Thuật toán Tự kiểm tra Round-Trip cho DST Resolver

Để loại bỏ hoàn toàn các trường hợp Edge Case, thuật toán DST Resolver tại `time_engine.dart` phải thỏa mãn điều kiện Round-trip hoàn chỉnh:

MD

tUTC\_candidate​TZDateTime.from( candidate, location )![](<data:image/svg+xml;utf8,\<svg xmlns="http://www.w3.org/2000/svg" width="400em" height="0.522em" viewBox="0 0 400000 522" preserveAspectRatio="xMaxYMin slice"\>\<path d="M0 241v40h399891c-47.3 35.3-84 78-110 128
-16.7 32-27.7 63.7-33 95 0 1.3-.2 2.7-.5 4-.3 1.3-.5 2.3-.5 3 0 7.3 6.7 11 20
 11 8 0 13.2-.8 15.5-2.5 2.3-1.7 4.2-5.5 5.5-11.5 2-13.3 5.7-27 11-41 14.7-44.7
 39-84.5 73-119.5s73.7-60.2 119-75.5c6-2 9-5.7 9-11s-3-9-9-11c-45.3-15.3-85
-40.5-119-75.5s-58.3-74.8-73-119.5c-4.7-14-8.3-27.3-11-40-1.3-6.7-3.2-10.8-5.5
-12.5-2.3-1.7-7.5-2.5-15.5-2.5-14 0-21 3.7-21 11 0 2 2 10.3 6 25 20.7 83.3 67
 151.7 139 205zm0 0v40h399900v-40z"\>\</path\>\</svg\>>)​(y′,m′,d′,h′,min′)\=?(y,m,d,h,min)input​

Ứng viên tUTC​ chỉ được coi là hợp lệ khi chuyển ngược lại timezone địa phương trả về đúng chính xác ngày, giờ, phút ban đầu.

MD

3\. Phản biện Ngược `review1.md` (3 Tinh chỉnh Cần thiết)
---------------------------------------------------------

Dù `review1.md` phản biện rất sắc bén, có 3 điểm cần tinh chỉnh để giữ đúng định hướng thiết kế dự án:

1.  **Về Error Model (Enum vs Const String - Review1 §6):** `review1` muốn đổi sang Dart `enum`. Tuy nhiên, `plan3_final.md` chọn `const String` nhằm giữ tính tương thích với JSON Golden tests và mã hóa log serialization. **Giải pháp dung hòa:** Sử dụng `abstract final class ErrorCodes` chứa các `static const String`. Cách này vừa ngăn chặn typo trong code, vừa không phá vỡ cấu trúc Serialization.
    
    MD\+ 3
    
2.  **Về `RenderIssue.message` (Review1 §7):** `review1` e ngại việc đưa chuỗi thông báo tiếng Anh vào Domain Model sẽ vi phạm Clean Architecture. Tuy nhiên ở giai đoạn Gate 0, trường `message` đóng vai trò là _Diagnostic Fallback_ (hỗ trợ debug nhanh). Cần ghi rõ trong docstring: `"Trường message là fallback chẩn đoán kỹ thuật, không phải UI localization contract cố định."`.
    
    MD\+ 1
    
3.  **Về SWAP Cross-Timezone (Review1 §8):** `review1` thảo luận về khả năng SWAP giữa các location khác timezone. **Khẳng định lại lập trường của Plan3:** Ở Gate 0, SWAP bắt buộc yêu cầu `same jobId` AND `same timezone`. Bất kỳ thao tác SWAP nào khác múi giờ sẽ bị reject ngay với mã `SWAP_CROSS_JOB`. Điều này giữ đúng **INVARIANT-007** (múi giờ cố định lúc tạo ca).
    
    MD\+ 4
    

4\. Bổ sung Acceptance Criteria (Checklist Patch cho Gate 0)
------------------------------------------------------------

Bổ sung 7 tiêu chí kiểm thử bắt buộc vào §8 của `plan3_final.md` trước khi bàn giao cho Agent execution:

MD\+ 1

*   \[ \] **A1 (Resolved-only):** Không tồn tại bất kỳ thực thể `ShiftOccurrence` rỗng/lỗi nào trong domain; toàn bộ ca chưa resolve nằm ở `ScheduleRenderResult.issues`.
    
    MD
    
*   \[ \] **A2 (UPDATE Preservation):** `UPDATE` chỉ sửa metadata/template mà không đổi civil time phải bảo toàn 100% giá trị UTC cũ, không gọi re-resolve.
    
    MD
    
*   \[ \] **A3 (Override Target Validation):** Override trỏ tới ID không tồn tại phải trả mã lỗi `OCCURRENCE_NOT_FOUND`, tuyệt đối không silent no-op.
    
    MD
    
*   \[ \] **A4 (Command Atomicity):** Mọi Override command bị lỗi đều đảm bảo tính nguyên tử (không làm biến đổi state trước đó, ghi lỗi vào issues và cho phép command sau tiếp tục).
    
    MD
    
*   \[ \] **A5 (Order Chain Testing):** Đạt 100% pass trên các chuỗi thao tác phức tạp: `UPDATE -> DELETE`, `DELETE -> UPDATE`, `SPLIT -> UPDATE`, `CREATE -> UPDATE`.
    
    MD
    
*   \[ \] **A6 (Resolver Round-Trip):** Kiểm định tính chính xác của thuật toán Time Engine bằng quy trình round-trip (tcivil​→tUTC​→tcivil​) trên toàn bộ Golden Data.
    
    MD
    
*   \[ \] **A7 (Non-mutation & Determinism):** Hàm `renderEffectiveSchedule` không làm biến đổi (mutate) dữ liệu đầu vào và luôn trả về kết quả đồng nhất với cùng một bộ input.
    
    MD
    

5\. Kết luận & Trạng thái Phê duyệt
-----------------------------------

Trạng thái của `plan3_final.md` được nâng cấp thành: **`READY FOR AGENT EXECUTION (AFTER CONTRACT PATCH)`**.

MD

Agent lập trình được phép bắt đầu triển khai code ngay sau khi file `plan3_final.md` cập nhật 6 điểm chỉnh sửa P0 ở Mục 2 và bộ Acceptance Criteria ở Mục 4. Toàn bộ các công việc liên quan đến `core/money`, SQLite Persistence và Flutter UI tiếp tục khóa chặt ở trạng thái chờ cho tới khi Gate 0 vượt qua 100% test âm tính.

MD\+ 2