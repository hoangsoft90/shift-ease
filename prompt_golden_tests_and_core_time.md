# plan2.md đã được duyệt — Bước tiếp theo

`plan2.md` đã qua 2 vòng review, mọi lỗi phát hiện (DST test date, overtime double-counting, khoảng trống CalendarEvent/PayRuleTemplate/Money golden tests/OCR milestone, và sự cố mất dấu tiếng Việt ở vòng sửa trước) đều đã được xác nhận sửa đúng và kiểm chứng độc lập. **Đây là bước duyệt chính thức để chuyển sang giai đoạn tiếp theo.**

Làm đúng theo thứ tự dưới đây — **không nhảy bước, không bắt đầu code trước khi tôi duyệt Golden Test Suite ở Bước 1**.

---

## Bước 1: Hoàn thiện Golden Test Suite

Mở rộng từ các case đã có trong `plan2.md` mục 7 (`time_engine_cases.json`, `money_engine_cases.json`) thành bộ test đầy đủ, sẵn sàng chạy được thật (không chỉ là ví dụ minh họa trong tài liệu).

### 1.1 Time Engine (`time_engine_cases.json`)

- Giữ nguyên toàn bộ case đã có (DST-001 → DST-005, BORDER-001...), đã kiểm chứng đúng.
- Bổ sung thêm case còn thiếu để phủ đầy đủ các tình huống đã liệt kê ở `plan1_final_v2.md` mục 3:
  - Ca bắc qua ranh giới **năm** (31/12 → 01/01), không chỉ ranh giới tháng
  - User đổi timezone thiết bị **giữa chừng** khi đã có occurrence cũ tồn tại — xác nhận occurrence cũ giữ nguyên timezone gốc (INVARIANT-007), viết test cho đúng hành vi này chứ không chỉ ghi chú
  - Property-based test cho Pattern: `occurrence[n + cycleLength]` phải cùng vị trí pattern như `occurrence[n]`; sửa occurrence #10 không ảnh hưởng occurrence #11 trở đi trừ khi sửa Pattern (khớp INVARIANT-001)
  - Ít nhất 1 case cho DST tại **UK** (Europe/London) — khác ngày với EU lục địa nếu có, và 1 case múi giờ Nam Bán Cầu (VD Australia) nếu bạn định hỗ trợ sau này, để kiểm tra code không hard-code giả định "DST luôn ở mùa xuân/thu Bắc Bán Cầu"

### 1.2 Money Engine (`money_engine_cases.json`)

- Giữ nguyên 9 case đã có (PAY-001 → PAY-009).
- Bổ sung case cho **PayRuleTemplate** mới thêm ở mục 5.6: ít nhất 1 case áp dụng template "US Hospital Nurse — California" và xác nhận kết quả breakdown đúng với luật OT California (>8h/ngày HOẶC >40h/tuần, lấy giá trị lớn hơn — đúng logic `resolveOvertimeMultiplier` đã có).
- Bổ sung case cho **PayRule versioning** (D6): tính lương cho một occurrence đã qua, sau đó thay đổi `baseHourlyRate` hiệu lực từ ngày sau đó — xác nhận `actualPayEstimate` của occurrence cũ **không đổi** (snapshot bất biến).

### 1.3 Import Pipeline

Viết case test cho state machine Import (mục 3): input thô mẫu (text paste đơn giản) → candidate shifts với confidence → xác nhận hệ thống **không tự commit** nếu confidence thấp, đúng INVARIANT-004.

### 1.4 CI Integration

Tích hợp cả 3 bộ test trên vào pipeline CI đã mô tả ở mục 7.3 — mỗi lần có PR động tới `core/time`, `core/pattern`, hoặc `core/money` đều phải chạy toàn bộ test tương ứng, PR bị block nếu fail bất kỳ case nào.

**Dừng lại sau Bước 1, gửi lại toàn bộ test suite (file thật, chạy được) để tôi review và duyệt trước khi sang Bước 2.**

---

## Bước 2 (chỉ làm sau khi tôi duyệt Bước 1): Implement `core/time`

Bắt đầu code module đầu tiên trong chuỗi bảo vệ tuyệt đối: `core/time`.

Yêu cầu bắt buộc:
- Toàn bộ 8 Invariant ở mục 1.2 của `plan2.md` phải pass trên Golden Test Suite đã duyệt ở Bước 1 — **100% case pass**, không có ngoại lệ, không "pass gần đúng"
- Dùng thư viện timezone dựa trên IANA tz database (không tự viết logic DST tay)
- Nộp kèm:
  - Bộ unit test đầy đủ (ngoài Golden Test Suite, thêm test cho các hàm nội bộ)
  - File `EXPLANATION.md` giải thích ngắn gọn: kiến trúc module, cách xử lý 3 khái niệm Civil Time / UTC Instant / Duration, cách xử lý case DST ambiguous/non-existent (D4)
  - Kết quả chạy Golden Test Suite (log đầy đủ, không phải tóm tắt "all pass")

Nếu trong lúc code phát hiện một Invariant nào đó khó thực hiện hoặc mâu thuẫn với thực tế kỹ thuật — **dừng lại và hỏi tôi, không tự ý nới lỏng hay bỏ qua**, đúng tinh thần đã ghi ở mục 1.2/1.3 của `plan2.md`.

Sau khi `core/time` được duyệt, tiếp tục tuần tự sang `core/pattern` rồi `core/money` — mỗi module đều qua quy trình review tương tự trước khi module tiếp theo bắt đầu.

---

**File đính kèm:** `plan2.md` (đã duyệt)
