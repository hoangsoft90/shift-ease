plan4_review1.md

Markdown

plan4_review2.md

Markdown

plan4_review3.md

Markdown

phân tích plan4.md và review của các AI khác plan4_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Tôi đã đọc kỹ **plan4.md** cùng ba bản review (review1 → review3). Đây là vòng phân tích tập trung vào **M2 Import** và các vấn đề wiring, transaction, re-import semantics, và integrity của báo cáo. Có thể tóm gọn thế này: core Time/Pattern đã khá vững, nhưng Import vẫn chưa production-ready. Nếu nhảy sang M3 Pay UI lúc này thì sẽ tạo ra technical debt rất nguy hiểm.

🔑 Điểm đồng thuận giữa các review
----------------------------------

*   **Unreachable Import:** `main.dart` chưa truyền `ImportRepository` vào `ScheduleService` → app thật không có nút Import, chỉ test mới pass.
    
*   **Commit không atomic:** Session được đánh dấu COMMITTED trước khi occurrences được ghi → crash giữa chừng làm DB bất nhất.
    
*   **Re-import OFF-date query sai:** Điều kiện `committedOffDatesJson != '[]'` bỏ qua session mới nếu roster không có OFF → dữ liệu OFF cũ treo vĩnh viễn.
    
*   **SWAP imported occurrence:** `templateId=''` làm SWAP báo MISSING\_TEMPLATE dù cùng job.
    
*   **Documentation integrity:** `checklist.md` báo có `result13_gate_m2.txt` nhưng file không tồn tại.
    
*   **Commit khi còn pending:** `_canCommit()` cho phép commit khi còn Pending → nguy cơ ghi thiếu ca.
    
*   **Version immutability:** `ON CONFLICT DO UPDATE` ghi đè version Pattern/PayRule → phá invariant.
    
*   **SQLCipher:** hiện chỉ có PRAGMA key giả, chưa có encryption thực sự.
    

📌 Các bổ sung & phản biện mới
------------------------------

1.  **Semantics re-import window**
    
    *   Mỗi `ImportSession` phải có `windowStart` và `windowEnd`.
        
    *   Commit mới ghi đè toàn bộ dữ liệu import cũ trong khoảng đó, kể cả OFF `[]`.
        
    *   Nếu window nhỏ hơn window cũ → chỉ thay thế trong window mới, ngoài window giữ nguyên.
        
    *   Nếu muốn thay toàn bộ lịch → user phải import file bao phủ toàn bộ.
        
2.  **Transaction boundary**
    
    *   Cần đảm bảo cả `_importRepo.saveSession` và `_scheduleRepo.replaceImportedOccurrences` dùng cùng connection SQLite.
        
    *   Nếu repository mở connection riêng thì transaction không hiệu lực → phải truyền `db` hoặc `Transaction` object.
        
3.  **Production composition test**
    
    *   Cần có integration test chạy theo `main.dart` để xác nhận `importEnabled==true`.
        
    *   Kiểm tra UI `JobDetailScreen` hiển thị nút Import.
        
4.  **Commit guard UX**
    
    *   Không cho commit khi còn Pending.
        
    *   Cần nút “Accept All Pending” hoặc “Accept All High Confidence” để user duyệt nhanh.
        
    *   Commit chỉ enabled khi PendingCount=0.
        
5.  **Verify script**
    
    *   Tạo script tự động so khớp số test, checklist, features, next, và sự tồn tại của file report.
        
    *   Fail nếu lệch → ngăn chặn “báo cáo ảo”.
        

🎯 Acceptance Criteria bổ sung cho Gate A/B
-------------------------------------------

*   \[ \] Import reachable từ production composition (`main.dart`).
    
*   \[ \] Commit atomic trong transaction, rollback nếu fail.
    
*   \[ \] Re-import semantics đúng: windowStart/End bắt buộc, OFF `[]` vẫn ghi đè.
    
*   \[ \] SWAP imported occurrence cùng job thành công.
    
*   \[ \] Commit guard: không commit khi còn Pending.
    
*   \[ \] Version immutability: không silent overwrite.
    
*   \[ \] Report Gate A tồn tại trên disk, checklist/features/next đồng bộ.
    
*   \[ \] Integration test xác nhận importEnabled==true.
    
*   \[ \] Toàn bộ test pass, không regression Gate 0–3.
    

✅ Kết luận
----------

*   **M2 Import chưa production-ready.**
    
*   Phải thực hiện **Gate A (Fix wiring, atomic commit, re-import semantics, SWAP imported, commit guard)** và **Gate B (Documentation integrity, version immutability, verify script)** trước khi mở M3 Pay UI.
    
*   Nếu không, Pay dashboard sẽ tính sai ngay từ dữ liệu lịch, mất trust của người dùng.
    

Bạn có muốn tôi viết luôn **patch chi tiết cho plan4\_final.md** (các đoạn cần sửa/thay thế) để áp dụng nhanh trước khi giao cho agent không?