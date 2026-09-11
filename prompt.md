# Prompt gửi cho AI Coding Agent — ShiftEase

## Bối cảnh

Tôi đang xây dựng một app mobile tên **ShiftEase** — "Personal Operating System for Shift Workers" (Work – Life – Money) cho nurse/healthcare worker làm ca xoay tại Mỹ/Anh/Đức.

Tài liệu đính kèm `plan1_final_v2.md` là kết quả sau nhiều vòng phân tích + phản biện (product vision, cạnh tranh, domain architecture). Đây là **nguồn sự thật (source of truth)** cho toàn bộ quyết định sản phẩm và kiến trúc domain tính đến thời điểm này. Đọc kỹ toàn bộ trước khi làm bất cứ việc gì.

## Việc cần làm — theo đúng thứ tự, KHÔNG được nhảy bước

### Bước 1: Viết `plan2.md`

Dựa trên khung đã có ở mục 16 của `plan1_final_v2.md`, viết một bản đặc tả kỹ thuật chi tiết (`plan2.md`) gồm đủ 8 phần:

1. Kiến trúc tổng thể + Architectural Invariants (copy nguyên mục 10 của plan1_final_v2, không được sửa/nới lỏng bất kỳ invariant nào)
2. Data model chi tiết dạng ER diagram, mở rộng từ schema ở mục 11 — giải thích rõ quan hệ giữa các entity, đặc biệt `ImportSession`, `Override`, các entity dùng `VersionedEntity` pattern
3. Quy trình xử lý Import: state machine đầy đủ từ parse → confidence → review UI → commit, cách lưu `ImportSession` để audit và hỗ trợ "What changed?"
4. Quy trình Pattern/Override: chi tiết hóa từng `OverrideOperation` (CREATE/UPDATE/DELETE/REPLACE/SPLIT/SWAP), cách version hóa Pattern khi user đổi roster
5. Pay Engine chi tiết: cấu trúc `PayDifferential` pluggable, thuật toán tính breakdown, cơ chế snapshot khi PayRule thay đổi
6. Security & Privacy Model: mã hóa dữ liệu khi sync, quản lý token cho Dynamic Webcal (bao gồm revoke/expiration), granular sharing (Busy/Free/Recovery)
7. Testing Strategy: liệt kê cụ thể các golden test case cho Time Engine (tối thiểu các case DST đã nêu ở mục 3), property test cho Pattern Engine, cách tích hợp vào CI
8. Milestones & metrics: mốc phát triển cụ thể + cách đo retention, conversion, số lượt import thành công

**Dừng lại sau bước này và đưa `plan2.md` cho tôi review trước khi sang bước 2.**

### Bước 2 (chỉ làm sau khi tôi duyệt plan2.md): Golden Test Suite

Viết file `time_engine_cases.json` chứa các test case theo đúng danh sách ở mục 3 của `plan1_final_v2.md` (DST spring-forward, fall-back, ca bắc qua ranh giới ngày/tháng/năm, đổi timezone thiết bị giữa chừng...). Đây phải hoàn thành và tôi duyệt **trước khi viết bất kỳ dòng code implementation nào**.

### Bước 3 (chỉ làm sau khi tôi duyệt test suite): Implementation

Bắt đầu code theo đúng thứ tự module, **không được đảo thứ tự**:

```
core/time  →  core/pattern  →  core/money  →  data/  →  domain/  →  features/  →  platform/
```

## Nguyên tắc bắt buộc tuân thủ trong TOÀN BỘ quá trình (không có ngoại lệ)

Copy nguyên các Architectural Invariants (mục 10) và NEVER list (mục 10) trong `plan1_final_v2.md` vào đầu mỗi file code thuộc `core/time`, `core/pattern`, `core/money` dưới dạng comment, để làm rõ ràng buộc cho mọi lần sửa code sau này (kể cả của chính bạn ở các phiên làm việc sau).

Cụ thể — 3 điều tuyệt đối không được vi phạm dù bất kỳ lý do gì (kể cả để "đơn giản hóa" hay "tối ưu tốc độ dev"):

1. **Không bao giờ** tính duration ca làm bằng phép trừ local time (`localEnd - localStart`). Luôn tính từ UTC instant đã resolve.
2. **Không bao giờ** để `ShiftTemplate` chứa bất kỳ trường liên quan tới tiền (pay multiplier, rate...). Toàn bộ ngữ nghĩa tiền tệ thuộc `PayRule`.
3. **Không bao giờ** auto-commit dữ liệu từ OCR/CSV/PDF import vào calendar chính mà chưa qua màn hình User Review.

Nếu trong quá trình implement bạn thấy một invariant nào đó gây khó khăn hoặc có vẻ không cần thiết — **dừng lại và hỏi tôi**, không tự ý bỏ qua.

## Với mỗi module thuộc `core/time`, `core/pattern`, `core/money`

Khi hoàn thành, phải nộp kèm:
- Bộ unit test đầy đủ (không chỉ test case "vui" mà cả edge case DST/timezone)
- Một file `EXPLANATION.md` ngắn giải thích logic đã implement, để tôi review trước khi merge

## Câu hỏi cần làm rõ trước khi bắt đầu (nếu có)

Nếu có bất kỳ phần nào trong `plan1_final_v2.md` chưa đủ rõ để viết `plan2.md`, hãy liệt kê câu hỏi cụ thể trước, đừng tự suy diễn và điền vào chỗ trống.

---

**File đính kèm:** `plan1_final_v2.md`