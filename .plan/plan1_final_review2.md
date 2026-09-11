phân tích solution plan1_final.md và review của các AI khác plan1_final_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Bản `plan1_final.md` đã định hình chuẩn xác tầm nhìn sản phẩm (_Personal Operating System for Shift Workers_ với 3 trụ cột Work – Life – Money), nhưng bản review `plan1_final_review.md` mới thực sự nâng tầm dự án từ một "ý tưởng sản phẩm hay" thành một **"kiến trúc hệ thống sẵn sàng lập trình"**.

MD\+ 2

Dưới đây là phân tích đối chiếu, phản biện và các bổ sung kiến trúc cốt lõi cần chốt trước khi chuyển sang `plan2`.

### So sánh & Đánh giá Xung đột Cốt lõi

| Hạng mục | 
Bản Plan Final (`plan1_final.md`)

MD





 | 

Bản Review Phản biện (`plan1_final_review.md`)

MD





 | Đánh giá & Hướng chốt |
| --- | --- | --- | --- |
| **Cam kết độ chính xác** | 

Đặt mục tiêu "tính đúng tuyệt đối".

MD





 | 

Bỏ khái niệm "tuyệt đối"; chuyển sang **Deterministic Contract** (Fail gracefully nếu thiếu input).

MD\+ 1





 | 

**Chọn Review:** "Thà báo không tính được còn hơn tự đoán rồi tính sai".

MD





 |
| **Quy trình Smart Import** | 

Nhận OCR/PDF/CSV -> Commit thẳng vào Calendar.

MD\+ 1





 | 

Tạo pipeline: **Parse -> Candidate Shifts -> Confidence Score -> User Review -> Commit**.

MD





 | 

**Chọn Review:** Tránh lỗi OCR làm sai lịch/lương, gây mất uy tín (loss of trust).

MD





 |
| **Cấu trúc Template & Pay** | 

Trộn `payMultiplier` vào `ShiftTemplate`.

MD





 | 

**Tách rời 100%**: `ShiftTemplate` (Thời gian/UI) vs `PayRule` (Tiền tệ).

MD





 | 

**Chọn Review:** Triệt tiêu bug trùng lặp hệ số (double-counting) khi tính ca đêm/cuối tuần.

MD





 |
| **Lịch lặp (Recurrence)** | 

Tính toán lặp lại dựa trên timestamp.

MD\+ 1





 | 

Recurrence bắt buộc chạy theo **Local Civil Time** (Giờ hành chính địa phương).

MD





 | 

**Chọn Review:** Đảm bảo ca 22:00 chạy xuyên suốt qua đêm DST không bị lệch giờ UTC.

MD





 |
| **Phạm vi P0 (MVP)** | 

Đưa Widget và Commute Reminder vào P0.

MD





 | 

Chuyển Widget & Smart Commute sang **P1**; bổ sung **Quick Add / Paste Schedule** vào P0.

MD





 | 

**Chọn Review:** Giảm độ phức tạp đa nền tảng (WidgetKit/Glance) cho AI agent trong pha đầu.

MD





 |

### Các Đóng góp & Bổ sung Kiến trúc Cốt lõi cho `plan2`

**1\. Tách biệt 3 khái niệm Thời gian (Civil Time Architecture)** AI Coding Agents rất dễ nhầm lẫn khi xử lý thời gian lặp. Data Model trong `plan2` cần định nghĩa rõ:

MD\+ 1

*   **Local Civil Time** (`22:00 NY Time`): Dùng cho quy luật Pattern, hiển thị giao diện và mong muốn của người dùng.
    
    MD
    
*   **UTC Instant** (`2026-11-01T...Z`): Dùng để sắp xếp chuỗi sự kiện, kích hoạt Reminder và so sánh mốc thời gian.
    
    MD
    
*   **Actual Elapsed Duration**: Thời gian thực tế trôi qua (giây), dùng để tính tổng số giờ làm và Pay Engine.
    
    MD
    

**2\. Mô hình Occurrence Override (Thay thế Exception đơn thuần)** Không dùng thuộc tính đơn giản `isException: boolean`. Hệ thống cần mô hình hóa lớp ghi đè (`Override`) chứa các thao tác rõ ràng: `CREATE`, `UPDATE`, `DELETE`, `REPLACE`, `SPLIT`, `SWAP`. Pattern gốc giữ vai trò Baseline; khi render lịch, hệ thống lấy Baseline chồng lớp Overrides để ra **Effective Schedule**.

MD\+ 4

**3\. Tách biệt Job (Nơi làm việc) và Shift Template** Mỗi Job (Bệnh viện A, Phòng khám B) phải sở hữu bộ `ShiftTemplate` và `PayRule` riêng biệt. Việc để `ShiftTemplate` ở cấp Global sẽ thất bại khi người dùng làm ca đêm tại 2 nơi với hai mức phụ cấp khác nhau.

MD\+ 1

**4\. Khung quy tắc bất biến cho AI Agents (Architectural Invariants)** Để AI agent không tự ý sửa đổi logic domain khi phát triển các module UI, `plan2` bắt buộc phải có danh sách quy tắc **"NEVER DO THIS"**:

MD\+ 1

*   **INVARIANT-001:** Không bao giờ tự động thay đổi `Pattern` gốc khi người dùng chỉnh sửa một ngày làm việc cụ thể (`Occurrence`).
    
    MD
    
*   **INVARIANT-002:** Không bao giờ tính duration ca làm qua đêm bằng phép trừ local time đơn thuần (`localEnd - localStart`).
    
    MD
    
*   **INVARIANT-003:** Không bao giờ tự động ghi dữ liệu OCR/PDF vào cơ sở dữ liệu mà chưa qua màn hình xác nhận của người dùng (`User Review`).
    
    MD
    
*   **INVARIANT-004:** Không bao giờ cho phép `PayRule` mới áp dụng đè lên làm thay đổi dữ liệu thu nhập trong quá khứ (`Versioned Pay Rules`).
    
    MD
    

### Lộ trình Ưu tiên Tinh chỉnh (Refined Roadmap)

*   **P0 (Cốt lõi chắc chắn):** Today Screen, Calendar View, Quick Add (1-tap), Pattern Builder (2-2-3, 4-on/4-off), Multi-job cơ bản, DST/Timezone Engine (`core/time`), Offline-first, Notification cơ bản, Smart Paste (Copy/Paste lịch dạng text).
    
    MD\+ 1
    
*   **P1 (Điểm khác biệt & Bán Pro):** Smart Import (OCR Screenshot/PDF với Màn hình Review), Pay Rule Engine & Income Breakdown, Availability Finder, Partner Overlay (Webcal export/Share link), Widgets.
    
    MD\+ 1
    
*   **P2 (Tính năng phòng thủ):** Pattern Auto-detection (Tự nhận diện chu kỳ từ lịch import), Shift Change Detection (Cảnh báo khi sếp đổi lịch), Recovery Reminders.
    
    MD\+ 1
    

### Khai thác Hook Marketing từ Trải nghiệm Phù hợp

Thay vì quảng cáo chung chung "App lịch ca tốt nhất", Hook truyền thông đánh thẳng vào "pain point" nhập liệu:

MD\+ 1

> **"Screenshot your hospital roster. ShiftEase handles the rest."**
> 
> MD
> 
> **"Work your shifts. Live your life."**
> 
> MD\+ 1

Sản phẩm không bắt người dùng ngồi nhập từng ca làm, mà biến tờ lịch phân ca (roster) nhận được thành công cụ quản lý toàn bộ cuộc sống của họ trong vài giây.

MD

### Quyết định Cần Khóa (D1–D8) Trước Khi Viết Spec `plan2`

1.  **D1 (Pattern Versioning):** Khi đổi Pattern từ ngày X, hệ thống lưu `effective_from` / `effective_until` để giữ nguyên lịch quá khứ.
    
    MD
    
2.  **D2 (Override Ops):** Thống nhất enum cho thao tác ghi đè: `CREATE | UPDATE | DELETE | REPLACE | SPLIT | SWAP`.
    
    MD
    
3.  **D3 (Recurrence Standard):** Khóa định hướng lặp lịch theo **Local Civil Time**.
    
    MD
    
4.  **D4 (DST Edge Cases):** Với giờ không tồn tại hoặc bị lặp lại do DST, hệ thống hiển thị dialog xác nhận thay vì tự làm tròn.
    
    MD
    
5.  **D5 (Decoupled Pay):** Loại bỏ hoàn toàn thông số giá trị tiền tệ khỏi `ShiftTemplate`.
    
    MD
    
6.  **D6 (Pay Integrity):** Lương quá khứ giữ cố định theo snapshot thời điểm đó, không tự đổi khi điều chỉnh `PayRule`.
    
    MD
    
7.  **D7 (Import Safeguard):** Quy định bắt buộc mọi luồng OCR/CSV phải qua màn hình xác nhận (`Confidence Review`).
    
    MD
    
8.  **D8 (Webcal Server Architecture):** Tách rõ bản Offline Export (.ics) cho MVP và Private Webcal Server Token cho P1.
    
    MD
    

Dự án đã đủ độ chín về mặt định hướng sản phẩm. Bạn nên sử dụng khung 8 quyết định trên để chốt spec kỹ thuật chi tiết trong `plan2` trước khi phân chia prompt cho các AI coding agents.

MD\+ 3