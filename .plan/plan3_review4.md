plan3_review1.md

Markdown

plan3_review2.md

Markdown

plan3_review3.md

Markdown

See all
phân tích plan3.md và review của các AI khác plan3_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Tôi đã đọc kỹ **plan3.md** cùng ba bản review (plan3\_review1 → plan3\_review3). Đây là vòng phân tích sâu nhất từ trước đến nay, vì đã chuyển từ “ý tưởng sản phẩm” sang **đối chiếu implementation thực tế**. Tôi sẽ tổng hợp lại, phản biện và đưa ra hành động tiếp theo.

🔎 Điểm nhất trí tuyệt đối
--------------------------

*   **Quyết định dừng lại, không chuyển sang** `core/money` **lúc này** là cực kỳ đúng. Nếu xây Pay Engine trên nền tảng Time/Pattern/Override còn lỗi, sẽ tạo technical debt rất nặng.
    
*   Các lỗi domain nghiêm trọng đã được chỉ ra rõ:
    
    *   Empty UTC trong CREATE/SPLIT.
        
    *   UPDATE bỏ qua time.
        
    *   REPLACE chưa áp dụng overrideTime.
        
    *   SWAP copy UTC sai semantics.
        
    *   Silent drop DST error.
        
    *   ±1h DST assumption.
        

📌 Các bổ sung & phản biện mới
------------------------------

1.  **Nguồn Local Time trong Override** Phải định nghĩa rõ: CREATE lấy từ template hoặc input; UPDATE bắt buộc có start/end; REPLACE có thể overrideTime optional; SWAP trao đổi civil intent rồi re-resolve UTC.
    
2.  **DELETE semantics** Không hard-delete. Nên soft-delete với `deletedAt` hoặc `isActive=false` để hỗ trợ Undo và audit trail.
    
3.  **Materialized vs On-the-fly** Nên chọn **Materialized View với Incremental Update**: lưu occurrence vào DB, regenerate từ `effectiveFrom` khi override thay đổi, nhưng không sửa lịch sử đã qua.
    
4.  **Error classification** Phải phân biệt rõ: INVALID\_DATE, INVALID\_TIME, INVALID\_TIMEZONE, NONEXISTENT\_LOCAL\_TIME, AMBIGUOUS\_LOCAL\_TIME, END\_BEFORE\_START, MISSING\_TEMPLATE. Đây là critical cho UX.
    
5.  **ID strategy** Không dùng string deterministic ID từ pattern+date+template. Nên có `occurrenceId` (UUID) + `projectionHash` để truy vết nguồn gốc.
    
6.  **Test Harness** Trước khi AI agent sửa code, cần có bộ test JSON/YAML mô tả kịch bản DST, swap, split, invalid input. Gate 0 chỉ xanh khi toàn bộ test pass.
    

🎯 Hành động tiếp theo (Gate Strategy)
--------------------------------------

**Gate 0 — Core Contract Hardening** Acceptance criteria:

*   Không còn occurrence với UTC/timezone rỗng.
    
*   6 operations (CREATE, UPDATE, DELETE, REPLACE, SPLIT, SWAP) deterministic, resolve đầy đủ.
    
*   Render trả về cả occurrences + issues (không silent drop).
    
*   DST resolver dùng timezone DB, không ±1h.
    
*   Error classification rõ ràng.
    
*   Golden tests + negative tests pass 100%.
    

**Gate 1 — Money Engine** Chỉ mở khi Gate 0 xanh hoàn toàn. Khi đó mới thêm PayRule, Breakdown, Snapshot.

💡 Gợi ý bổ sung tính năng & UI cho production
----------------------------------------------

*   **Today screen signature UX:** Next Shift card + Countdown (“Working in 03h 24m” / “OFF for 1d 08h”).
    
*   **Recovery indicator:** sau ca đêm, hiển thị khung giờ nghỉ khuyến nghị.
    
*   **Shift detail:** “Why this shift?” (nguồn pattern, override, timezone).
    
*   **What changed?** timeline: lịch sử thay đổi của từng ca.
    
*   **Pay breakdown:** hiển thị chi tiết base + night diff + weekend + OT.
    
*   **Undo toàn cục:** cho phép hoàn tác ngay khi xóa/nhập nhầm.
    
*   **Conflict detection:** cảnh báo khi ca làm đè lên sự kiện cá nhân.
    
*   **Smart import UI:** hiển thị confidence, cho phép review từng ca trước khi commit.
    
*   **Backup/restore offline:** xuất file .json mã hóa trước khi có cloud.
    
*   **Duplicate detection:** cảnh báo khi import trùng ca.
    
*   **Settings production:** timezone, DST handling, notifications, jobs, pay rules, backup, privacy.
    

✅ Kết luận
----------

*   **Không được chuyển sang Money Engine ngay.**
    
*   Ưu tiên số 1: **ShiftEase Core Contract Hardening — Gate 0**.
    
*   Sau khi Gate 0 xanh (không còn UTC rỗng, không silent drop, DST resolver đúng, override pipeline deterministic, test harness pass), mới mở Gate 1.
    
*   UI/UX production nên được thiết kế song song nhưng không code trước khi contract domain ổn định.
    

Bạn có muốn tôi viết hẳn một **spec Gate 0 chi tiết** (bao gồm acceptance criteria, test harness, NEVER list) để giao cho AI coding agent không?
----------
Rất tốt, vậy tôi sẽ viết **spec Gate 0 chi tiết** cho dự án ShiftEase. Đây là tài liệu kỹ thuật để giao cho AI coding agent, đảm bảo nền móng domain được khóa chặt trước khi sang Money Engine.

---

# 📑 Spec Gate 0 — ShiftEase Core Contract Hardening

## 🎯 Mục tiêu
- Khóa cứng **Core Domain Contract**: Time + Pattern + Override + Effective Schedule.
- Không còn bất kỳ `ShiftOccurrence` hợp lệ nào có UTC/timezone rỗng.
- Không silent drop lỗi DST.
- 6 thao tác Override (`CREATE`, `UPDATE`, `DELETE`, `REPLACE`, `SPLIT`, `SWAP`) deterministic và production-safe.
- Time Engine không còn giả định ±1h, mà dùng dữ liệu từ TimeZone DB.

---

## 🔒 Quyết định kiến trúc đã khóa
1. **Occurrence Validity**  
   - Mọi `ShiftOccurrence` trong domain phải luôn có temporal identity đầy đủ (utcStart, utcEnd, timezone).  
   - Nếu không resolve được → chỉ tồn tại dưới dạng `RenderIssue` / `UnresolvedOccurrence`.

2. **Override Pipeline**  
   ```
   OverrideCommand
     → Validate payload
     → Resolve Local Civil Time
     → TimeZoneResolver (0/1/2 candidates)
     → Nếu 0 hoặc 2 → trả Issue
     → Nếu 1 → Apply invariants
     → Output: Immutable Valid ShiftOccurrence(s)
   ```

3. **Local Civil Time = Source of Truth**  
   Recurrence và override chạy theo wall-clock local time, không phải UTC interval.

4. **Effective Schedule Renderer**  
   Trả về:
   ```typescript
   interface ScheduleRenderResult {
     occurrences: ShiftOccurrence[]; // resolved
     issues: RenderIssue[];          // DST_NONEXISTENT, AMBIGUOUS, INVALID_DATE, ...
   }
   ```

5. **SWAP Semantics**  
   SWAP = trao đổi civil intent (template + local time) → re-resolve UTC theo timezone của occurrence đích.  
   Không copy UTC trực tiếp.

6. **DELETE = Soft Delete**  
   Giữ bản ghi với `deletedAt` hoặc `isActive=false`. Không hard-delete.

7. **Error Classification**  
   Phân biệt rõ:  
   - INVALID_DATE  
   - INVALID_TIME  
   - INVALID_TIMEZONE  
   - NONEXISTENT_LOCAL_TIME  
   - AMBIGUOUS_LOCAL_TIME  
   - END_BEFORE_START  
   - MISSING_TEMPLATE

---

## ✅ Acceptance Criteria
- Không còn occurrence với UTC/timezone rỗng.  
- CREATE luôn resolve UTC đầy đủ hoặc trả Issue.  
- UPDATE đổi được cả template và time.  
- REPLACE hỗ trợ overrideTime.  
- SPLIT tạo ra các phần đều valid UTC.  
- SWAP dùng civil-time semantics.  
- DELETE là soft-delete.  
- Renderer trả về cả occurrences + issues, không silent drop.  
- TimeZoneResolver trả về đúng 0/1/2 candidate instants từ DB (hỗ trợ offset 30/45 phút).  
- Error classification chính xác.  
- Golden tests + negative tests pass 100%.

---

## 🧪 Test Harness (bắt buộc)
Tạo thư mục `test/harness/` với các case JSON/YAML:

1. DST Spring-forward (nonexistent local time).  
2. DST Fall-back (ambiguous local time).  
3. Timezone lệch 30 phút (Lord Howe).  
4. Timezone lệch 45 phút (Nepal).  
5. Overnight shift bình thường.  
6. Overnight shift bắc qua DST.  
7. CREATE với template → UTC resolved đúng.  
8. UPDATE đổi giờ.  
9. UPDATE đổi template + giờ.  
10. REPLACE với overrideTime.  
11. SPLIT ca ngày và ca đêm.  
12. SWAP cross-timezone.  
13. DELETE → soft-delete.  
14. Invalid date/time/timezone → lỗi đúng loại.  
15. Missing template → RenderIssue.  
16. Pattern versioning → occurrence sau ngày đổi không lệch anchor.

---

## 🚫 NEVER List
- NEVER tạo occurrence với UTC/timezone rỗng.  
- NEVER silent drop unresolved occurrence.  
- NEVER dùng ±1h assumption cho DST.  
- NEVER copy UTC khi SWAP.  
- NEVER hard-delete occurrence.  
- NEVER để UPDATE bỏ qua time.  
- NEVER trộn pay semantics vào ShiftTemplate.  
- NEVER đánh dấu feature ✅ nếu chưa có test + acceptance scenario.

---

## 📌 Hành động ngay
- Sửa `ShiftOccurrence` để temporal fields non-nullable.  
- Implement OverrideProcessor cho 6 operations qua pipeline.  
- Đổi renderer thành `ScheduleRenderResult`.  
- Viết/hoàn thiện test harness.  
- Chạy toàn bộ test → xanh hoàn toàn.  
- Chỉ sau khi Gate 0 pass mới mở Gate 1 (Money Engine).

---

👉 Đây là spec Gate 0 đầy đủ để giao cho AI coding agent. Nó sẽ đảm bảo nền móng domain vững chắc, tránh technical debt. Bạn có muốn tôi viết thêm **bộ test case mẫu chi tiết (JSON/YAML)** để khởi động test harness ngay không?
