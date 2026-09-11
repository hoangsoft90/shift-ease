phân tích solution plan3_final.md và review của các AI khác plan3_final_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Worked for 18s

**Phân tích tổng hợp plan3\_final.md + 3 review**

Tôi đã đọc kỹ toàn bộ plan3\_final.md (33777 bytes) cùng plan3\_final\_review1, review2 và review3. Đây là vòng review chất lượng cao nhất từ trước đến nay: plan đã chuyển từ “ý tưởng” sang **domain contract có bằng chứng thực nghiệm**, còn các review đã chỉ ra chính xác những chỗ còn mâu thuẫn semantics.

* * *

### 1\. Đánh giá tổng thể

| Hạng mục | Điểm | Nhận xét |
| --- | --- | --- |
| Evidence & probe thật | **9.5/10** | E1–E12 + Lord Howe 30′ rất thuyết phục |
| Phát hiện P0 | **9/10** | Gần như đầy đủ, có thêm M1–M4 giá trị |
| Scope control (Gate 0) | **9.5/10** | Rất tốt, giữ được boundary |
| Spec code chi tiết | **8.5/10** | Rõ ràng, nhưng còn mâu thuẫn nội bộ |
| Semantics Override | **6.5/10** | Còn 4–5 điểm critical chưa khóa chặt |
| Agent readiness | **7/10** | **Chưa nên giao nguyên xi** |

**Verdict của tôi:**  
plan3\_final.md đạt khoảng **8.3–8.5/10**. Đây là bản plan tốt nhất trong chuỗi, nhưng vẫn còn **4–6 điểm P0/Critical** khiến nếu agent code đúng từng chữ hiện tại thì sẽ tạo ra core “xanh test nhưng sai semantics”.

Trạng thái đúng phải là:

> **READY AFTER CONTRACT PATCH**  
> (không phải “CHỐT — sẵn sàng cho agent” ngay lúc này)

* * *

### 2\. Những điểm tôi nhất trí tuyệt đối với các review

Các review (đặc biệt review1) đã chỉ ra đúng các lỗ hổng nghiêm trọng. Tôi xác nhận và xếp theo mức độ nguy hiểm:

#### 🔴 Critical 1 — Signature applyOverride mâu thuẫn

Plan vừa ghi List<ShiftOccurrence> applyOverride(...) vừa ghi OverrideResult applyOverride(...).  
Với AI agent đây là lỗi chết người: agent sẽ chọn một trong hai đoạn và bỏ qua đoạn kia.  
**Phải xóa sạch snippet cũ**, chỉ còn một contract duy nhất:

Dart

CopyCopied

    OverrideResult applyOverride(
      List<ShiftOccurrence> occurrences,
      Override override, {
      required Map<String, ShiftTemplate> templates,
    })

#### 🔴 Critical 2 — UPDATE temporal semantics nguy hiểm

Plan yêu cầu re-resolve ngay cả khi chỉ đổi template (giữ giờ).  
Case thực tế: occurrence đã được resolve vào một trong hai candidate của ngày ambiguous (DST fall-back). User chỉ đổi template → engine re-resolve → phát hiện 2 candidates → báo AMBIGUOUS\_LOCAL\_TIME dù user **không hề đụng đến thời gian**.

**Quy tắc đúng phải là:**

text

CopyCopied

    if (civil time intent unchanged) {
      preserve existing UTC exactly;   // không gọi resolve lại
    } else {
      resolve new civil time;
    }

Đây là điểm quan trọng nhất mà plan hiện tại còn sai.

#### 🔴 Critical 3 — Resolved-only domain chưa airtight

Plan tuyên bố “Resolved-only”, nhưng §5.6 vẫn nói giữ nguyên error entries từ projectOccurrences.  
Nếu projectOccurrences vẫn tạo object có UTC rỗng thì D1 bị phá.

**Contract phải khóa:**

Dart

CopyCopied

    class ProjectionResult {
      final List<ShiftOccurrence> occurrences; // 100% resolved
      final List<RenderIssue> issues;
    }

Pipeline: Pattern → projectOccurrences() → ProjectionResult → applyOverrides() → ScheduleRenderResult.

#### 🔴 Critical 4 — Thiếu OCCURRENCE\_NOT\_FOUND

Nếu UPDATE / DELETE / REPLACE / SPLIT / SWAP trỏ tới id không tồn tại (do đã bị xóa, SPLIT, hoặc id sai), engine hiện không có mã lỗi rõ ràng → nguy cơ silent no-op.  
Phải thêm vào D7 và bắt buộc fail với issue này.

#### 🔴 Critical 5 — Provenance (D4) bị mâu thuẫn

CREATE bắt buộc gán sourceOverrideId = override.id → luôn bị phân loại thành 'override', làm nhánh 'created' gần như vô nghĩa.

Cần tách:

*   sourceOverrideId = audit trail (id của override cuối cùng chạm vào)
*   source (enum): baseline | created | modified

#### 🟠 High — Override chain + atomicity + ordering

Plan chưa định nghĩa rõ:

*   Command N fail có rollback các command trước không?
*   Sau SPLIT, id cũ còn tồn tại để UPDATE tiếp không?
*   Thứ tự đánh giá override có phải semantic không?

Tôi đồng ý với review: **command-level atomicity** (fail của N không rollback 1..N-1, cũng không chặn N+1), và phải có test chuỗi cụ thể.

#### 🟠 High — SPLIT invariants còn thiếu

Chưa siết:

*   Parts không được overlap
*   Phải chronological order
*   Phải nằm trong temporal envelope của occurrence gốc (trừ overnight hợp lệ)

Nếu không siết, sau này payroll và calendar sẽ bị double-count / chồng chéo.

* * *

### 3\. Những điểm tôi bổ sung / phản biện nhẹ

1.  **Error model**  
    Review muốn enum, plan giữ String vì JSON golden.  
    Giải pháp dung hòa tốt nhất (như review2):  
    abstract final class ErrorCodes { static const invalidDate = 'INVALID\_DATE'; ... }  
    Vừa chống typo, vừa không phá serialization.
2.  **RenderIssue.message**  
    Ở Gate 0 chấp nhận giữ message làm diagnostic fallback, nhưng phải ghi rõ trong docstring:
    
    > “Diagnostic only, not a localization / presentation contract.”
    
3.  **SWAP cross-timezone**  
    Tôi ủng hộ quyết định của plan: Gate 0 chỉ cho phép same jobId **và** same timezone. Cross-timezone → SWAP\_CROSS\_JOB. Đúng với INVARIANT-007.
4.  **DELETE soft-delete**  
    Plan bác bỏ soft-delete ở Gate 0 là đúng (override log đã là audit). Soft-delete thuộc Gate 2 khi có persistence.
5.  **Performance resolver**  
    Enumerate loc.zones không phải bottleneck thực tế. Có thể để backlog, không cần criterion cứng ở Gate 0.

* * *

### 4\. Acceptance Criteria bắt buộc phải bổ sung trước khi giao agent

Tôi đề xuất thêm vào §8 của plan:

*   **A1** Không tồn tại ShiftOccurrence unresolved trong domain; mọi lỗi chỉ nằm trong issues.
*   **A2** UPDATE chỉ đổi template/metadata (civil time không đổi) → **preserve UTC tuyệt đối**, không re-resolve.
*   **A3** Override target id không tồn tại → OCCURRENCE\_NOT\_FOUND, không silent no-op.
*   **A4** Mỗi override command fail là atomic ở phạm vi command (không mutate state trước đó).
*   **A5** Test chuỗi: UPDATE→DELETE, DELETE→UPDATE, SPLIT→UPDATE, CREATE→UPDATE đều pass.
*   **A6** Resolver round-trip: local → UTC → local khớp chính xác input.
*   **A7** renderEffectiveSchedule không mutate input và deterministic.
*   **A8** SPLIT: parts không overlap, chronological, nằm trong envelope gốc (trừ overnight hợp lệ); vi phạm → fail atomic.
*   **A9** Mọi error code được tham chiếu qua hằng số (ErrorCodes.xxx), không literal string rải rác.

* * *

### 5\. Thứ tự patch bắt buộc trước khi agent code

**Phải sửa trong plan trước khi bàn giao:**

1.  Xóa sạch signature cũ List<ShiftOccurrence>, chỉ còn OverrideResult.
2.  Sửa D4 provenance (tách source enum vs sourceOverrideId).
3.  Khóa UPDATE: temporal intent không đổi → preserve UTC.
4.  Khóa projectOccurrences → ProjectionResult (resolved-only).
5.  Thêm OCCURRENCE\_NOT\_FOUND vào D7 + spec từng operation.
6.  Định nghĩa rõ command-level atomicity + ordering semantics + test chuỗi.
7.  Siết SPLIT invariants (no overlap, order, envelope).
8.  Bổ sung 9 acceptance criteria ở trên.

Sau khi patch xong các điểm trên → trạng thái mới:

> **READY FOR AGENT EXECUTION**

* * *

### 6\. Kết luận

plan3\_final.md là bước tiến rất lớn. Nó đã biến Gate 0 từ “sửa vài bug” thành một **domain contract có evidence + invariant + golden test**.

Tuy nhiên, nếu giao nguyên bản hiện tại cho AI agent, nguy cơ lớn nhất không còn là DST ±1h nữa, mà là:

> Core engine xanh test nhưng semantics của UPDATE / CREATE provenance / override chain / SPLIT bị sai — và loại bug này sẽ rất khó sửa khi Money + SQLite + UI đã xây lên trên.

**Khuyến nghị hành động:**

1.  Patch 6–8 điểm critical ở trên vào plan3\_final.md.
2.  Cập nhật Acceptance Criteria.
3.  Sau đó mới mở prompt cho agent thực hiện Gate 0.

Bạn muốn tôi viết luôn bản **patch chi tiết** (các đoạn cần sửa/thay thế trong plan3\_final.md) để bạn áp dụng nhanh không?