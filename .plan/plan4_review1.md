phân tích plan4.md & suy nghĩ kỹ rồi đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Đánh giá tổng quan: **`plan4.md` \[source: 8\] là một bản review xuất sắc, cực kỳ sắc bén và đi thẳng vào bản chất vấn đề.** Reviewer đã vạch ra đúng "gót chân Achilles" của AI agent: **Test xanh giả tạo do Dependency Injection bị lệch giữa Unit Test và Production App Entrypoint \[source: 8\].**

Nếu cho Agent nhảy ngay sang M3 (Pay UI), hệ thống sẽ tích tụ nợ kỹ thuật (technical debt) nghiêm trọng và dẫn đến việc tính toán lương dựa trên dữ liệu lịch bị sai lệch hoặc không nhất quán \[source: 8\].

Dưới đây là **Phân tích chi tiết, Phản biện kiến trúc, Bổ sung giải pháp cụ thể** để gửi phản hồi/giao nhiệm vụ cho Agent.

I. Phân tích & Đánh giá các Finding trong `plan4.md` \[source: 8\]
==================================================================

### 1\. Đồng ý tuyệt đối với các Bug P1 Critical \[source: 8\]

1.  **Unreachable M2 Import (Bug Entrypoint) \[source: 8\]:** `main.dart` không truyền `imports: ImportRepository(db)` vào `ScheduleService` \[source: 8\]. Widget test pass vì test tự inject repo, còn App thật thì ẩn nút Import \[source: 8\].
    
2.  **Import Commit không Atomic ở Persistence Boundary \[source: 8\]:** `commitImport()` đổi trạng thái Session thành `COMMITTED`, sau đó ghi `occurrences` \[source: 8\]. Nếu bước 2 crash, DB rơi vào trạng thái bất hợp lệ (Session báo đã commit nhưng Lịch không có dữ liệu mới) \[source: 8\].
    
3.  **Bug Query Re-import OFF Date \[source: 8\]:** Điều kiện `committedOffDatesJson != '[]'` bỏ qua session mới nếu roster mới phủ định toàn bộ ngày OFF (trả về danh sách rỗng `[]`) \[source: 8\]. Điều này làm dữ liệu OFF cũ bị treo vĩnh viễn \[source: 8\].
    
4.  **Vi phạm Quy trình Verify (Báo cáo ảo) \[source: 8\]:** `checklist.md` báo có `result13_gate_m2.txt` nhưng file hoàn toàn không tồn tại trên disk \[source: 8\]. Đây là lỗi nghiêm trọng về tính toàn vẹn dữ liệu/báo cáo.
    

II. Ý kiến Phản biện, Bổ sung & Giải pháp Kiến trúc Chi tiết
============================================================

Để chuẩn hóa lại spec trước khi đưa Agent thi công, cần chốt 5 điểm kiến trúc bổ sung sau:

### 🟢 1. Bổ sung Semantics cho Re-import Window Replacement (Lỗi 6 & 7 \[source: 8\])

**Vấn đề `plan4.md` nêu \[source: 8\]:** Re-import window nhỏ hơn (VD: Import A từ 1-30/09, Import B từ 10-20/09) hiện tại đang hoạt động theo cơ chế **Partial Window Replacement** \[source: 8\], để lại vết của Import A ở ngày 1-9 và 21-30 \[source: 8\].

**Chốt Semantics chính xác:**

*   Mỗi `ImportSession` **bắt buộc lưu trữ thuộc tính `windowStart` và `windowEnd`** đại diện cho khoảng thời gian của file Roster đó (ví dụ: Ngày đầu tháng đến Ngày cuối tháng).
    
*   Khi Commit một Roster mới (Session B), hệ thống phải **xóa toàn bộ Imported Occurrences cũ** thuộc về `jobId` đó trong khoảng `[SessionB.windowStart, SessionB.windowEnd]`.
    
*   **Cơ chế SUPPRESS Pattern:** Danh sách `committedOffDatesJson` của Session B sẽ ghi đè hoàn toàn (Override) lên hiệu lực của Session A trong khoảng `[windowStart, windowEnd]`.
    

**Truy vấn SQL cần sửa lại:**

SQL

    -- Lấy Session committed mới nhất phủ lên ngày targetDate, KỂ CẢ KHI committedOffDatesJson = '[]'
    SELECT committedOffDatesJson 
    FROM import_sessions 
    WHERE jobId = ? 
      AND state = 'committed'
      AND ? BETWEEN windowStart AND windowEnd
    ORDER BY createdAt DESC, id DESC 
    LIMIT 1;

### 🟢 2. Giải pháp triệt để cho SWAP trên Imported Occurrence (Lỗi 15 \[source: 8\])

**Vấn đề `plan4.md` nêu \[source: 8\]:** Ca import có `templateId = ''` làm SWAP báo lỗi `MISSING_TEMPLATE` dù 2 ca thuộc cùng Job \[source: 8\].

**Giải pháp Kiến trúc:**

*   `ShiftOccurrence` cần có trường `jobId` trực tiếp (hoặc getter fallback):
    
    Dart
    
        String get effectiveJobId => jobId ?? template?.jobId ?? '';
    
*   Trong `pattern_engine.dart`, logic kiểm tra điều kiện SWAP không được phụ thuộc vào `templateId`. Kiểm tra trực tiếp:
    
    Dart
    
        if (occA.effectiveJobId != occB.effectiveJobId) {
          return OverrideResult.error(ErrorCodes.SWAP_CROSS_JOB);
        }
    

### 🟢 3. Chuẩn hóa Transaction cho Import Commit (Lỗi 5 \[source: 8\])

Cung cấp code pattern bắt buộc cho Agent khi sửa `ScheduleService.commitRoster()` \[source: 8\]:

Dart

    Future<void> commitRoster(ImportSession session) async {
      final result = _importEngine.commitImport(session);
      
      // BẮT BUỘC bọc trong Database Transaction ở Persistence Layer
      await _db.transaction(() async {
        // 1. Lưu state session = COMMITTED
        await _importRepo.saveSession(result.session);
        
        // 2. Ghi đè occurrences trong khoảng window
        await _scheduleRepo.replaceImportedOccurrences(
          jobId: session.jobId,
          windowStart: session.windowStart,
          windowEnd: session.windowEnd,
          occurrences: result.occurrences,
        );
      });
    }

### 🟢 4. Chốt UI State Machine cho Pending Import Items (Lỗi 11 \[source: 8\])

**Quy tắc kiểm duyệt Roster (Review Flow):**

*   **KHÔNG cho phép Commit partial** khi vẫn còn dòng ở trạng thái `Pending`.
    
*   Nút **"Commit Roster"** chỉ sáng (`enabled`) khi:
    
    PendingCount\==0AND(ApprovedCount+ModifiedCount\>0)
    
*   Nếu user muốn commit nhanh các ca `High Confidence`, UI phải cung cấp nút **"Accept All Pending"** hoặc **"Reject All Pending"** trước khi mở khóa nút Commit. Điều này đảm bảo minh bạch UX, tránh việc ghi thiếu ca mà người dùng không hay biết \[source: 8\].
    

### 🟢 5. Chiến lược Encryption & DB Storage (Lỗi 13 & 14 \[source: 8\])

Tách biệt môi trường Development và Production để không làm tắc nghẽn tiến độ nhưng vẫn đảm bảo Security:

*   Tạo `DatabaseFactory` seam:
    
    *   `DevDatabaseProvider`: Dùng `sqlite3` thuần (FFI) cho phép chạy fast integration tests trên Desktop/CI.
        
    *   `ProdDatabaseProvider`: Dùng `SQLCipher` mã hóa AES-256 + Integration với Secure Storage (Keychain/Keystore) để lưu DB Key.
        
*   Agent không cần làm ngay `ProdDatabaseProvider` ở Gate này, nhưng **phải loại bỏ đoạn giả lập `PRAGMA key` vô tác dụng trên Plain SQLite** \[source: 8\].
    

III. Kế hoạch Hành động (Prompt chỉ đạo Agent)
==============================================

Dưới đây là câu lệnh phản hồi gửi trực tiếp cho Agent để yêu cầu khắc phục triệt để các vấn đề trên trước khi bước sang M3.

### 💬 Yêu cầu gửi Agent:

> **Đánh giá Plan 4 & Yêu cầu tạm dừng M3 để Fix M2 Correctness & Persistence Integrity**
> 
> Báo cáo M2 hiện tại **chưa đạt tiêu chuẩn Production-Ready** \[source: 8\]. Đã phát hiện bug P1 nghiêm trọng khiến tính năng Import bị ẩn hoàn toàn trên App thật và các lỗi vi phạm tính toàn vẹn dữ liệu \[source: 8\].
> 
> Yêu cầu thực hiện nghiêm túc **Gate A & Gate B** theo danh sách bên dưới. **Không tự ý chuyển sang M3 UI cho đến khi toàn bộ checklist này PASS \[source: 8\].**
> 
> ### 🔴 GATE A: Fix Production Wiring & Import Correctness Bugs \[source: 8\]
> 
> 1.  **Wire M2 vào App Entrypoint (`main.dart`) \[source: 8\]:**
>     
>     *   Truyền `ImportRepository(db)` vào `ScheduleService` trong `main.dart` \[source: 8\].
>         
>     *   Thêm Integration Test xác nhận `ScheduleService.importEnabled == true` khi khởi chạy từ `main.dart` \[source: 8\].
>         
> 2.  **Transaction-Atomic Import Commit \[source: 8\]:**
>     
>     *   Bọc `_importRepo.saveSession` và `_scheduleRepo.replaceImportedOccurrences` bên trong một SQLite `db.transaction()` duy nhất \[source: 8\].
>         
>     *   Đảm bảo ROLLBACK hoàn toàn nếu bất kỳ thao tác ghi nào gặp lỗi \[source: 8\].
>         
> 3.  **Fix Bug Re-import OFF Date Query \[source: 8\]:**
>     
>     *   Sửa `committedOffDatesInRange()` trong `ScheduleRepository` \[source: 8\]: Không dùng điều kiện `committedOffDatesJson != '[]'` \[source: 8\].
>         
>     *   Sửa truy vấn để lấy Session committed mới nhất phủ lên khoảng thời gian `[windowStart, windowEnd]`.
>         
>     *   Thêm test case: _Import A có Sep 10 = OFF → Import B có Sep 10 = Day → Kết quả Render ngày Sep 10 BẮT BUỘC là Day (Không bị Suppress)._ \[source: 8\]
>         
> 4.  **Chốt Replacement Window Semantics cho Re-import \[source: 8\]:**
>     
>     *   Thêm `windowStart` và `windowEnd` vào `ImportSession`.
>         
>     *   `replaceImportedOccurrences()` phải xóa sạch các `imported` occurrences cũ trong toàn bộ khoảng `[windowStart, windowEnd]` của session mới trước khi chèn ca mới.
>         
> 5.  **Fix SWAP cho Imported Occurrence \[source: 8\]:**
>     
>     *   Cập nhật `pattern_engine.dart`: Sử dụng `effectiveJobId` để so sánh khi SWAP, không phụ thuộc vào `templateId` \[source: 8\].
>         
> 
> ### 🔴 GATE B: Harden Immutability & Document Integrity \[source: 8\]
> 
> 6.  **Bảo vệ Version Immutability ở Persistence Boundary \[source: 8\]:**
>     
>     *   Cập nhật `PayRuleRepository` và `PatternRepository`: Ném ngoại lệ (Exception) nếu cố tình `save()` một record có `id` đã tồn tại nhưng nội dung thay đổi (không cho phép silent `ON CONFLICT DO UPDATE` ghi đè history) \[source: 8\].
>         
> 7.  **Đồng bộ Báo cáo & Filesystem \[source: 8\]:**
>     
>     *   Tạo và chạy lại test suite để xuất file `result13_gate_m2.txt` thật lên filesystem \[source: 8\].
>         
>     *   Cập nhật đồng bộ các file `checklist.md`, `features.md`, và `next.md` khớp 100% với số lượng test thực tế trên filesystem \[source: 8\].
>         
> 
> **Sau khi hoàn thành Gate A & B, hãy chạy `flutter test` toàn bộ project và xuất báo cáo `result13_gate_m2.txt` để mình review trước khi mở Gate M3 Pay UI \[source: 8\].**