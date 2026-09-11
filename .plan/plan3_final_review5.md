plan3_final_review1.md

Markdown

plan3_final_review2.md

Markdown

plan3_final_review3.md

Markdown

See all
phân tích solution plan3_final.md và review của các AI khác plan3_final_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Tôi đã đọc kỹ **plan3\_final.md** cùng bốn bản review (review1 → review4). Đây là vòng tài liệu chi tiết nhất từ trước đến nay: không chỉ liệt kê bug, mà còn đưa ra bằng chứng probe code thật, test golden, invariant và NEVER list. Tuy nhiên, cả bốn review đều đồng thuận rằng nếu giao nguyên xi cho agent thì vẫn có nguy cơ **“xanh test nhưng sai semantics domain”**. Tôi sẽ tổng hợp và bổ sung.

🔎 Điểm mạnh của plan3\_final.md
--------------------------------

*   **Evidence thực nghiệm:** Probe trực tiếp `timezone 0.9.4`, test Lord Howe 30′, phát hiện rollover ngày/giờ của Dart. Đây là nền tảng vững chắc.
    
*   **Scope control:** Gate 0 khóa chặt, không cho đụng tới Money, UI, persistence.
    
*   **Spec code chi tiết:** Có pseudo-code cho từng file, acceptance criteria, golden tests.
    
*   **NEVER list rõ ràng:** Ngăn agent “sáng tạo” sai hướng.
    

📌 Các vấn đề còn tồn tại (Critical/High)
-----------------------------------------

1.  **Signature applyOverride mâu thuẫn** Có cả `List<ShiftOccurrence>` và `OverrideResult`. Agent có thể chọn sai. → Phải xóa sạch snippet cũ, chỉ giữ `OverrideResult`.
    
2.  **UPDATE semantics nguy hiểm** Nếu chỉ đổi template, plan yêu cầu re-resolve → có thể bắn lỗi AMBIGUOUS\_LOCAL\_TIME vô lý. → Quy tắc đúng: nếu civil time không đổi, giữ nguyên UTC tuyệt đối.
    
3.  **Resolved-only domain chưa airtight** `projectOccurrences` vẫn tạo occurrence lỗi với UTC rỗng. → Phải trả `ProjectionResult { occurrences, issues }`, không bao giờ tạo object rỗng.
    
4.  **Thiếu OCCURRENCE\_NOT\_FOUND** Override trỏ tới id không tồn tại hiện silent no-op. → Phải thêm error code này.
    
5.  **Provenance tagging mâu thuẫn** CREATE gán `sourceOverrideId = override.id` → luôn bị phân loại thành override, mất nhãn “created”. → Phải tách `sourceOverrideId` (audit trail) và `source` (enum baseline/created/modified).
    
6.  **Override chain + atomicity chưa rõ** Chưa định nghĩa khi command N fail thì có rollback không. → Phải khóa: command-level atomicity, fail N không rollback 1..N-1, không chặn N+1.
    
7.  **SPLIT invariants thiếu** Chưa siết overlap, chronological order, envelope. → Phải thêm ràng buộc: parts không overlap, theo thứ tự, nằm trong khung giờ gốc (trừ overnight hợp lệ).
    

🟠 Các bổ sung cần thiết
------------------------

*   **Error constants:** Nên dùng `abstract final class ErrorCodes` với `static const String` để tránh typo, vẫn tương thích JSON.
    
*   **RenderIssue.message:** Giữ diagnostic fallback, nhưng ghi rõ “không phải UI localization contract”.
    
*   **SWAP cross-timezone:** Giữ quyết định reject, chỉ cho phép same jobId + same timezone.
    
*   **Validation input:** Explicit reject `24:00`, `00`, `13` tháng, phút >59, whitespace, empty string.
    
*   **Round-trip invariant:** Mọi RESOLVED instant phải thỏa `local → UTC → local = original`.
    

✅ Acceptance Criteria bổ sung
-----------------------------

Thêm vào §8 của plan3\_final.md:

*   \[ \] Không tồn tại ShiftOccurrence unresolved trong domain; lỗi chỉ nằm ở issues.
    
*   \[ \] UPDATE chỉ đổi template/metadata → preserve UTC.
    
*   \[ \] Override target id không tồn tại → OCCURRENCE\_NOT\_FOUND.
    
*   \[ \] Override fail atomic, không mutate state trước đó.
    
*   \[ \] Test chuỗi override: UPDATE→DELETE, DELETE→UPDATE, SPLIT→UPDATE, CREATE→UPDATE.
    
*   \[ \] Resolver round-trip chính xác.
    
*   \[ \] Renderer deterministic, không mutate input.
    
*   \[ \] SPLIT parts không overlap, chronological, nằm trong envelope gốc.
    
*   \[ \] Error codes tham chiếu qua hằng số, không literal string.
    

🎯 Kết luận
-----------

*   **plan3\_final.md hiện ~8.5/10**: rất mạnh về evidence và scope, nhưng còn 6–7 điểm critical.
    
*   Trạng thái đúng: **READY AFTER CONTRACT PATCH**, không phải “CHỐT — sẵn sàng cho agent” ngay.
    
*   Hành động: Patch các điểm trên (signature, UPDATE semantics, resolved-only projection, OCCURRENCE\_NOT\_FOUND, provenance, atomicity, SPLIT invariants) → cập nhật acceptance criteria → sau đó mới giao cho agent thực hiện Gate 0.
    

Bạn có muốn tôi viết luôn **bản patch chi tiết** (các đoạn cần sửa/thay thế trong plan3\_final.md) để bạn áp dụng nhanh không?