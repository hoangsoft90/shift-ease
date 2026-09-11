phân tích solution plan5.md & suy nghĩ kỹ rồi đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Bản review `plan5.md` phân tích rất chuẩn xác và kịp thời. Reviewer đã chỉ ra đúng các lỗ hổng về **Data Integrity, Persistence State, và Invariant Enforcement** mà bộ test 179 cases hiện tại bỏ lỡ.

MD\+ 1

### Phân tích các lỗ hổng P1 nghiêm trọng từ `plan5.md`

| Hạng mục | Lỗ hổng kỹ thuật | Hậu quả dữ liệu / App Runtime |
| --- | --- | --- |
| 
**Import State Machine**

MD





 | 

`commitImport()` cho phép chuyển đổi trực tiếp `EXTRACTED → COMMITTED`.

MD





 | 

Vi phạm Invariant: Dữ liệu Import bị commit vào Lịch mà bỏ qua bước xác nhận (User Review).

MD





 |
| 

**Roster Re-versioning**

MD





 | 

`changeRosterFrom()` thực hiện 2 câu lệnh DB độc lập, không có Transaction.

MD





 | 

Nếu bước tạo Pattern mới fail, Pattern cũ đã bị đóng (`CLOSED`), khiến người dùng mất lịch làm việc.

MD





 |
| 

**Override Collision**

MD





 | 

`saveOverride()` âm thầm bỏ qua (`silent return`) khi bị trùng `overrideId`.

MD





 | 

Mất dấu vết audit log, ghi đè thao tác mà không bắn ngoại lệ hoặc cảnh báo.

MD





 |
| 

**Stale Materialized Cache**

MD





 | 

`saveOccurrences()` chỉ dùng `INSERT ON CONFLICT UPDATE`, không xóa ca đã bị DELETE/Suppress.

MD





 | 

Truy vấn `occurrencesInRange()` trực tiếp từ DB sẽ trả về các ca làm việc bị ma (đã xóa trên UI nhưng vẫn tồn tại trong DB).

MD





 |
| 

**Preset UI Logic Bug**

MD





 | 

Preset `2-2-3` trong Pattern Builder sinh ra cấu hình `WWWWOOO` (4-on/3-off).

MD





 | 

Sai lệch hoàn toàn logic xoay ca của người dùng ngay từ khâu tạo lịch.

MD





 |

### 3 Điểm Bổ sung & Phản biện Kiến trúc

1\. Chốt giải pháp cho Materialized Occurrence Cache (Mục 10) Nên chốt **Option A (Materialized Cache)**: Bảng `occurrences` trong SQLite thuần túy là Read-side Cache. Mỗi khi hàm `renderJobSchedule()` chạy, toàn bộ quá trình lưu cache phải nằm trong 1 Transaction:

MD\+ 2

SQL

    DELETE FROM occurrences WHERE jobId = ? AND shiftDate BETWEEN ? AND ?;
    -- Sau đó mới INSERT lại toàn bộ effective occurrences mới

2\. Khóa cứng Immutability của `ImportSession` (Mục 5) Không chỉ ngăn `ON CONFLICT DO UPDATE` ở `ImportRepository`, cần ném `StateError` ngay ở Domain Model nếu gọi `saveSession()` trên một Session đã ở trạng thái `COMMITTED` nhưng có nội dung khác với DB.

MD\+ 1

3\. Siết chặt Scope: Không đưa Phase R5 (Mobile/SQLCipher) vào chung Batch code logic `plan5.md` đề xuất từ R0 đến R5. Việc bắt Agent gộp cả UI/Engine với việc cấu hình Native Android/iOS (`path_provider`, KeyChain, SQLCipher Native FFI) sẽ gây loãng focus và dễ sinh bug. Cần chia làm **2 Phase phát hành**:

MD\+ 2

*   **Phase 1 (Release Candidate 1):** Sửa toàn bộ lỗi Data Integrity (R0) + M3 Pay/Income (R1) + DST UI & Calendar (R2).
    
    MD\+ 2
    
*   **Phase 2 (Production Packaging):** Mobile Platform Integration (`path_provider`, Android/iOS build targets, SQLCipher Key Storage).
    
    MD
    

### Directives gửi Agent (Prompt Chỉ đạo)

Copy toàn bộ nội dung bên dưới để giao việc trực tiếp cho Agent:

Plaintext

    YÊU CẦU SỬA LỖI DATA INTEGRITY VÀ HOÀN THIỆN RELEASE CANDIDATE (PHASE R0 + R1 + R2)
    
    Đã kiểm tra lại toàn bộ codebase. Agent cần ngưng mở rộng tính năng mới và tập trung giải quyết triệt để 5 lỗ hổng Data Integrity (R0) cùng gói UI Pay/Income (R1) theo đúng danh sách sau:
    
    -------------------------------------------------------------------
    🔴 1. FIX DATA INTEGRITY & CORE ENGINE (PHASE R0)
    -------------------------------------------------------------------
    - Import State Machine: Sửa `ImportEngine.commitImport()`. CHỈ cho phép transition `REVIEWING -> COMMITTED`. Nếu session ở trạng thái `EXTRACTED`, bắt buộc trả về lỗi/ném StateError.
    - Atomic Roster Re-versioning: Bọc toàn bộ logic trong `ScheduleService.changeRosterFrom()` vào 1 SQLite Transaction (`_db.transaction()`). Đóng pattern cũ và tạo pattern mới phải thành công cùng lúc hoặc ROLLBACK hoàn toàn.
    - Strict Override Identity: Sửa `ScheduleRepository.saveOverride()`. Nếu trùng `overrideId` nhưng payload khác nhau, BẮT BUỘC ném `ImmutableHistoryError`.
    - Materialized Cache Cleanup: Sửa `ScheduleRepository.saveOccurrences()`. Thực thi trong Transaction: Xóa toàn bộ occurrences thuộc scope `[jobId, windowStart, windowEnd]` trước khi ghi đè effective occurrences mới.
    - Fix UI Preset: Sửa logic sinh pattern preset `2-2-3` trong `pattern_builder_screen.dart` (đảm bảo đúng chuỗi xoay ca 2 làm - 2 nghỉ - 3 làm).
    - Add Adversarial Tests: Thêm test suite kiểm tra các trường hợp vi phạm (Forbidden transitions, DB rollback khi partial failure, duplicate override payload).
    
    -------------------------------------------------------------------
    🟡 2. HOÀN THIỆN M3 PAY & INCOME DASHBOARD (PHASE R1)
    -------------------------------------------------------------------
    - Triển khai Pay Rule Editor UI: Cho phép cấu hình Hourly Rate, Night Differential, Weekend Differential, Overtime Rules (>8h/nguoidung, >40h/tuan).
    - Pay Rule Versioning: Bảo đảm Pay Rule không bị sửa đổi lịch sử (versioned theo ngày hiệu lực).
    - Income Breakdown Dashboard: Hiển thị ước tính thu nhập theo Tuần/Tháng (Regular, OT, Differential) kèm nhãn "Estimated — not official payroll".
    
    -------------------------------------------------------------------
    🟡 3. DST UI & TODAY REAL-TIME HARDENING (PHASE R2)
    -------------------------------------------------------------------
    - DST Conflict Dialog: Hiển thị Dialog bắt buộc người dùng chọn khung giờ khi gặp AMBIGUOUS_LOCAL_TIME hoặc cảnh báo khi gặp NONEXISTENT_LOCAL_TIME.
    - Real-time Today Ticker: Thêm Periodic Ticker/Timer cho Today Screen để đếm ngược thời gian chuyển ca chính xác theo thời gian thực.
    
    -------------------------------------------------------------------
    📋 QUY CHUẨN KẾT QUẢ
    -------------------------------------------------------------------
    - Đồng bộ lại bộ hồ sơ: Cập nhật `.plan/features.md`, `checklist.md`, `next.md`. Xuất kết quả test thực tế ra file `result15_gate_r0_r1.txt`.
    - Chạy `flutter test` bảo đảm 100% test pass trước khi bàn giao.