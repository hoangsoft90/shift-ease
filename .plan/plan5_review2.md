plan5_review1.md
MD 6.79KB
plan5.md
MD 28.41KB
phân tích solution plan5.md và review của các AI khác plan5_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Phân tích tổng hợp `plan5.md` và `plan5_review1.md` – Ý kiến đóng góp & phản biện
=================================================================================

Tôi đã đọc kỹ cả hai tài liệu. Nhìn chung, `plan5.md` là một bản review sắc sảo, phát hiện các lỗ hổng data integrity nghiêm trọng mà bộ test 179 cases đã bỏ lỡ. `plan5_review1.md` đã đồng tình và bổ sung các giải pháp kiến trúc cụ thể, đồng thời đưa ra prompt chỉ đạo agent.

Tôi hoàn toàn nhất trí với hướng xử lý các lỗi P1, nhưng tôi muốn bổ sung thêm một số chi tiết và phản biện để làm rõ hơn các giải pháp, đồng thời nhấn mạnh một số điểm cần lưu ý khi triển khai.

* * *

1\. Điểm đồng ý tuyệt đối với các phát hiện và giải pháp
--------------------------------------------------------

| Lỗ hổng | Giải pháp trong `plan5_review1.md` | Đánh giá của tôi |
| --- | --- | --- |
| `EXTRACTED → COMMITTED` bypass | Chặn state transition, chỉ cho phép `REVIEWING → COMMITTED` | ✅ Đúng, cần enforce ở core engine, không chỉ UI. |
| `changeRosterFrom()` không atomic | Bọc trong transaction; rollback nếu partial fail | ✅ Đúng, đây là lỗi data integrity nghiêm trọng. |
| `saveOverride()` silent-ignore conflict | Ném `ImmutableHistoryError` nếu payload khác | ✅ Đúng; tuy nhiên cần hỗ trợ idempotent nếu payload giống hệt. |
| Materialized cache stale | Xóa toàn bộ occurrences trong window trước khi insert mới, trong transaction | ✅ Đúng; cần lưu ý performance nếu window lớn. |
| Preset 2-2-3 sai | Sửa logic sinh pattern | ✅ Cần kiểm tra tất cả các presets. |

* * *

2\. Các bổ sung và phản biện chi tiết
-------------------------------------

### 🔴 P1 – Về `saveOverride()`: nên hỗ trợ idempotent khi payload giống hệt

`plan5.md` chỉ ra rằng `saveOverride()` đang silent-return nếu trùng ID. `plan5_review1.md` đề xuất ném `ImmutableHistoryError` nếu payload khác. Tôi đồng ý, nhưng tôi muốn bổ sung:

*   **Nếu cùng ID và cùng payload (so sánh deep equality):** nên cho phép và return success (idempotent). Điều này hỗ trợ retry logic từ client, tránh lỗi không cần thiết.
    
*   **Nếu cùng ID nhưng payload khác:** ném `ImmutableHistoryError` và không ghi đè.
    

**Cần implement deep equality cho `Override` payload**, bao gồm `templateId`, `startTime`, `endTime`, `shiftDate`, `operation`, v.v. Nếu có nested objects, cần so sánh đệ quy.

### 🟠 P1 – Về materialized cache: cần tối ưu performance cho window lớn

`plan5_review1.md` đề xuất:

sql

Copy

Download

DELETE FROM occurrences WHERE jobId \= ? AND shiftDate BETWEEN ? AND ?;
INSERT INTO occurrences ...;

Điều này đúng. Tuy nhiên, nếu window là cả năm (365 ngày) và số occurrence có thể lên tới vài trăm, việc delete + insert toàn bộ là chấp nhận được. Nhưng nếu user có nhiều job và lịch vài năm, performance có thể bị ảnh hưởng.

**Tôi đề xuất thêm:** Nếu window quá lớn (> 90 ngày), có thể thực hiện theo từng tháng để tránh lock lâu. Tuy nhiên, đây là optimization, không cần thiết ở giai đoạn này. Chỉ cần đảm bảo transaction là đủ.

### 🟠 P1 – Về `ImportSession` immutability: cần ngăn chặn update `COMMITTED` session

`plan5.md` chỉ ra rằng `ImportRepository.saveSession()` dùng `ON CONFLICT DO UPDATE`, cho phép ghi đè session đã commit. `plan5_review1.md` đề xuất ném `StateError` nếu cố gắng save session đã commit với nội dung khác.

Tôi đồng ý, nhưng cần làm rõ:

*   **Đối với session `EXTRACTED` và `REVIEWING`:** có thể cho phép update (ví dụ cập nhật candidates, review decisions).
    
*   **Đối với session `COMMITTED`:** KHÔNG cho phép update bất kỳ field nào (state, raw, committedIds, offDates, window, v.v.). Ném `ImmutableHistoryError`.
    
*   **Thêm `UNIQUE` constraint** trên `session.id` để đảm bảo không có duplicate.
    

Tuy nhiên, cần lưu ý: nếu session đã commit nhưng vì lý do nào đó (như migration) cần sửa, thì phải tạo session mới (với ID mới) và đánh dấu session cũ là `DEPRECATED` hoặc `VOID`. Điều này phức tạp và có thể để sau.

### 🟡 P2 – Về `changeRosterFrom()` atomicity: cần kiểm tra `effectiveFrom` không chồng lấn

`plan5.md` và `plan5_review1.md` đều nhấn mạnh cần transaction. Tôi bổ sung:

*   **Trong cùng transaction**, cần kiểm tra rằng pattern mới có `effectiveFrom` lớn hơn pattern cũ `effectiveFrom` và không chồng lấn. Nếu chồng lấn, transaction sẽ fail và rollback.
    
*   **Cần thêm test** cho trường hợp `effectiveFrom` của pattern mới nằm trong khoảng `effectiveFrom` - `effectiveUntil` của pattern cũ (gây chồng lấn).
    

### 🟡 P2 – Về adversarial tests: cần thêm test cho rollback và crash recovery

`plan5.md` đề xuất thêm "Boundary / Adversarial Tests". Tôi đồng ý và bổ sung thêm các scenario:

1.  **Transaction rollback:** Khi `changeRosterFrom()` fail ở bước insert new pattern, đảm bảo pattern cũ vẫn ở trạng thái `OPEN` (không bị đóng).
    
2.  **Crash giữa chừng:** Mô phỏng app crash ngay sau khi `saveSession()` commit nhưng trước khi `replaceImportedOccurrences()` được thực thi. Cần kiểm tra rằng sau khi restart, dữ liệu không bị inconsistent (session vẫn ở `REVIEWING` hoặc `PENDING`).
    
3.  **Duplicate override idempotent:** Gửi cùng override payload hai lần; lần thứ hai không ném lỗi, nhưng DB chỉ có một bản ghi.
    
4.  **Import session bị cố gắng update sau commit:** Gọi `saveSession()` với session đã commit nhưng thay đổi raw extraction; ném `ImmutableHistoryError`.
    

### 🟢 Điểm tôi đặc biệt ủng hộ: Tách Phase R5 (mobile/SQLCipher) khỏi logic code

`plan5_review1.md` đề xuất tách R5 thành phase riêng. Tôi hoàn toàn ủng hộ. Việc gộp code logic với native mobile configuration (Android/iOS, KeyChain, SQLCipher FFI) sẽ làm loãng focus và dễ sinh bug. Nên có hai phase riêng biệt:

*   **Phase 1 (Release Candidate):** Sửa data integrity, hoàn thiện M3 Pay, DST UI, Calendar UX (R0, R1, R2).
    
*   **Phase 2 (Production Packaging):** Mobile integration, SQLCipher, path\_provider, notifications, Settings.
    

* * *

3\. Những điểm tôi phản biện nhẹ với `plan5_review1.md`
-------------------------------------------------------

### Về `COMMITTED` session immutability

`plan5_review1.md` nói "không chỉ ngăn ON CONFLICT DO UPDATE, cần ném StateError ngay ở Domain Model". Tôi đồng ý, nhưng tôi nghĩ việc ném exception ở domain model có thể ảnh hưởng đến caller (ví dụ UI sẽ hiện lỗi). Có thể cân nhắc dùng `Result` pattern (success/failure) thay vì exception để caller xử lý rõ ràng hơn. Tuy nhiên, exception cũng được, miễn là có xử lý ở tầng UI.

### Về `2-2-3` preset và các presets khác

`plan5.md` chỉ phát hiện sai preset `2-2-3`. Tôi khuyến nghị kiểm tra tất cả các presets có sẵn (DuPont, 4-on/4-off, 2-2-3, 3-on/3-off, v.v.) bằng một bộ test riêng. Có thể dùng bảng mapping: preset name → expected sequence. Nếu có bất kỳ sai lệch nào, sửa tất cả.

* * *

4\. Đề xuất bổ sung cho lộ trình R0 – R5
----------------------------------------

Dựa trên các phân tích, tôi đề xuất lộ trình sửa đổi như sau:

### Phase R0 – Data Integrity Hardening (ưu tiên cao nhất)

*   □
    
    Chặn `EXTRACTED → COMMITTED` (chỉ cho `REVIEWING → COMMITTED`).
    
*   □
    
    Transaction cho `changeRosterFrom()` (rollback nếu fail).
    
*   □
    
    `saveOverride()`: idempotent nếu payload giống, ném error nếu khác.
    
*   □
    
    `ImportSession`: chỉ cho update nếu state != COMMITTED.
    
*   □
    
    Materialized cache: delete + insert trong transaction.
    
*   □
    
    Sửa `2-2-3` preset và kiểm tra các preset khác.
    
*   □
    
    Thêm adversarial tests cho các trường hợp trên.
    

### Phase R1 – Pay & Income UI (hoàn thiện M3)

*   □
    
    PayRule editor với versioning.
    
*   □
    
    Income breakdown dashboard (Weekly/Monthly).
    
*   □
    
    Tích hợp với `ScheduleService` để tính toán.
    
*   □
    
    Hiển thị "Estimated – not official payroll".
    

### Phase R2 – Calendar UX hoàn chỉnh

*   □
    
    Today screen: real-time countdown.
    
*   □
    
    DST dialog cho `AMBIGUOUS` và `NONEXISTENT`.
    
*   □
    
    Week/Month view: quick add, edit, delete.
    
*   □
    
    Shift Detail: show source, pay, timezone, "Why this shift?".
    
*   □
    
    Conflict detection (OFF + SHIFT cùng ngày, overlapping shifts).
    

### Phase R3 – Import UX nâng cao

*   □
    
    CSV Mapping UI.
    
*   □
    
    Re-import diff: hiển thị thay đổi trước khi commit.
    
*   □
    
    Xử lý conflict OFF + SHIFT (cho user chọn).
    

### Phase R4 – Reliability & Safety

*   □
    
    Backup / Restore (JSON export/import).
    
*   □
    
    Undo (append inverse override).
    
*   □
    
    Crash recovery tests.
    

### Phase R5 – Mobile Production

*   □
    
    `path_provider` (ApplicationSupportDirectory).
    
*   □
    
    SQLCipher native (Android/iOS).
    
*   □
    
    Secure Storage (KeyChain/Keystore) cho encryption key.
    
*   □
    
    Notifications (30/60 min before shift).
    
*   □
    
    Settings screen đầy đủ.
    
*   □
    
    Privacy Policy, Terms, Support.
    

* * *

5\. Các acceptance criteria bổ sung
-----------------------------------

Tôi đề xuất thêm các tiêu chí kiểm thử sau đây cho từng phase:

*   **R0-AC1:** Gọi `commitImport()` trên session `EXTRACTED` → trả về lỗi / ném exception. Chỉ `REVIEWING` mới được commit.
    
*   **R0-AC2:** `changeRosterFrom()` khi gặp lỗi ở bước insert pattern mới → pattern cũ vẫn giữ `effectiveUntil` cũ (không bị đóng).
    
*   **R0-AC3:** `saveOverride()` với ID trùng nhưng payload khác → ném `ImmutableHistoryError`; payload giống → success.
    
*   **R0-AC4:** Sau khi render và `saveOccurrences()`, query `occurrencesInRange()` trả về đúng effective occurrences, không có occurrence bị delete hoặc suppress còn sót.
    
*   **R0-AC5:** Preset `2-2-3` tạo đúng chuỗi `[W,W,O,O,W,W,W]` (hoặc tương đương tùy định nghĩa). Kiểm tra các preset khác.
    

* * *

6\. Kết luận
------------

`plan5.md` và `plan5_review1.md` đã chỉ ra chính xác các lỗ hổng data integrity và đề xuất giải pháp hợp lý. Tôi đồng tình với việc **không chuyển sang M3 Pay UI cho đến khi các lỗi P1 được sửa**. Tôi cũng ủng hộ việc tách mobile integration thành phase riêng.

**Bước tiếp theo:** Agent nên thực hiện các sửa chữa trong Phase R0 trước, sau đó chạy toàn bộ test suite và xuất báo cáo `result15_gate_r0.txt`. Khi các test pass và không còn stale cache, conflict, hay silent override, mới bắt đầu Phase R1 (Pay/Income). Điều này đảm bảo nền tảng vững chắc trước khi thêm tính năng mới.