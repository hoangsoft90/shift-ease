plan5_review1.md

Markdown

plan5_review2.md

Markdown

plan5_review3.md

Markdown

See all
phân tích solution plan5.md và review của các AI khác plan5_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Tôi đã đọc kỹ **plan5.md** cùng ba bản review (plan5\_review1 → review3). Đây là vòng đánh giá rất quan trọng vì nó chỉ ra rằng dù bộ test hiện tại có 179 case đều pass, vẫn còn nhiều **lỗ hổng data integrity** chưa được chặn. Nếu không xử lý triệt để, app có thể mất dữ liệu hoặc hiển thị sai lịch/lương ngay trong production.

🔎 Các phát hiện P1 nghiêm trọng (được cả plan5 và các review xác nhận)
-----------------------------------------------------------------------

*   **Import state machine**: `commitImport()` vẫn cho phép `EXTRACTED → COMMITTED`. Đây là bypass review, vi phạm invariant “không commit khi chưa user confirm”.
    
*   **Roster re-versioning không atomic**: `changeRosterFrom()` đóng pattern cũ và tạo pattern mới bằng 2 lệnh riêng. Nếu bước 2 fail → mất roster.
    
*   **Override collision**: `saveOverride()` silent-ignore khi trùng ID nhưng payload khác. Phải ném lỗi, không được ghi đè im lặng.
    
*   **ImportSession overwrite**: `ON CONFLICT DO UPDATE` cho phép ghi đè session đã COMMITTED. Audit log mất tính bất biến.
    
*   **Materialized cache stale**: `saveOccurrences()` chỉ insert/update, không xóa rows cũ → DB có ca “ma” đã bị delete/suppress.
    
*   **Preset 2-2-3 sai**: UI tạo ra `WWWWOOO` (4-on/3-off) thay vì 2-2-3. Đây là bug logic rõ ràng.
    
*   **OFF + SHIFT cùng ngày**: chưa có invariant chặn dữ liệu import mâu thuẫn (Sep 10 vừa OFF vừa có ca Day).
    

📌 Các bổ sung từ review2 & review3
-----------------------------------

*   **Idempotent override**: cùng ID + payload giống hệt → OK; cùng ID + payload khác → ImmutableHistoryError.
    
*   **ImportSession immutability theo state**: EXTRACTED/REVIEWING có thể update; COMMITTED thì immutable.
    
*   **Adversarial tests**: cần thêm test rollback, crash recovery, duplicate override, OFF+SHIFT conflict.
    
*   **PayRule repository**: không được auto-create Job khi jobId sai; phải reject.
    
*   **PayRule child comparison**: canonicalize order để tránh false diff.
    
*   **UI bug**: Pattern Builder tạo TextEditingController trong build → leak/mất cursor.
    
*   **Today screen**: countdown chưa real-time, chỉ tính lúc build.
    
*   **SQLCipher**: chưa production-ready, mới seam PRAGMA key.
    
*   **Mobile release**: chưa có android/ios folders, path\_provider, secure storage.
    
*   **Documentation drift**: `features.md` stale, `result13_gate_m2.txt` reference nhưng file không tồn tại.
    

🎯 Kết luận
-----------

*   **App chưa đủ để xuất bản.** Core Time/Pattern/Money khá vững, nhưng Import/Persistence còn lỗ hổng P1.
    
*   Trước khi release cần một batch cuối (**Gate C**) để:
    
    *   Chặn EXTRACTED→COMMIT.
        
    *   Làm `changeRosterFrom()` atomic.
        
    *   Override immutability.
        
    *   ImportSession COMMITTED immutable.
        
    *   Materialized cache consistency.
        
    *   Fix preset 2-2-3.
        
    *   Thêm adversarial tests.
        
    *   DST dialog UI.
        
    *   Pay/Income dashboard cơ bản.
        
    *   ICS export offline.
        
    *   Notification ca sắp tới.
        
    *   Platform baseline (android/ios, path\_provider).
        
    *   Documentation đồng bộ.
        

✅ Đề xuất hành động
-------------------

*   **Gate C — Data Integrity & Minimum Release Hardening**: làm một batch duy nhất, chặn toàn bộ lỗ hổng P1 và bổ sung các tính năng tối thiểu để app có thể đưa vào closed testing/TestFlight.
    
*   Sau Gate C mới mở rộng M3 Pay UI đầy đủ, CSV mapping, Re-import diff, Backup/Restore, Undo, SQLCipher production, Settings, Privacy/Terms.
    

Bạn có muốn tôi viết luôn **patch chi tiết cho Gate C** (các đoạn cần sửa/thay thế trong code + checklist/features/next) để agent áp dụng ngay không?