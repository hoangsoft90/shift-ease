phân tích plan3.md & suy nghĩ kỹ rồi đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Bản `plan3.md` đã đưa ra một quyết định chiến lược cực kỳ chính xác: **TUYỆT ĐỐI DỪNG LẠI, KHÔNG CHUYỂN SANG `core/money` VÀO LÚC NÀY**. Việc "đánh dấu ✅ quá rộng" trong `features.md` khi các hàm cốt lõi (`CREATE`, `UPDATE`, `SPLIT`, `renderEffectiveSchedule`) đang chứa lỗi domain nghiêm trọng (UTC string rỗng, silent drop lỗi DST) sẽ khiến toàn bộ hệ thống Pay Engine và UI phía sau xây trên một nền móng sụt lở.

MD\+ 2

Dưới đây là phân tích chi tiết, đánh giá phản biện và bộ giải pháp hoàn thiện cho `plan3.md`.

MD

1\. Phân tích & Phản biện các lỗi Core Domain Engine
----------------------------------------------------

### 🔴 Lỗi 1: Temporal Identity bị phá hủy (UTC start/end rỗng)

*   **Hiện trạng (`plan3.md` chỉ ra):** Trong `_applyCreate()` và `SPLIT`, hệ thống gán `startDateTimeUtc: ''`, `endDateTimeUtc: ''`, `timezone: ''`.
    
    MD
    
*   **Đánh giá & Phản biện:** Việc đẩy một `ShiftOccurrence` thiếu định danh thời gian vào domain là vi phạm trực tiếp nguyên tắc _Deterministic Contract_. Nếu Downstream Engines (Pay Engine, Notification, Calendar UI) nhận phải object này, chúng sẽ buộc phải "tự đoán" hoặc crash.
    
    MD\+ 3
    
*   **Chốt giải pháp:** Mọi `ShiftOccurrence` một khi đã instanciate ra domain bắt buộc phải **100% Valid**. Quá trình chuyển đổi từ Override Command -> UTC Resolution phải diễn ra **trước** khi tạo đối tượng `ShiftOccurrence`.
    
    MD
    

### 🔴 Lỗi 2: Contradiction trong `renderEffectiveSchedule()`

*   **Hiện trạng (`plan3.md` chỉ ra):** Comment ghi _"NEVER silently drop occurrences"_, nhưng code runtime lại lọc `.where((r) => r.isSuccess)` làm biến mất các ca lỗi DST.
    
    MD
    
*   **Đánh giá:** Đây là bug trôi dạt kiến trúc nguy hiểm. Người dùng có ca làm vào ngày nhảy giờ DST nhưng lịch hiển thị trống trơn mà không thông báo lý do, gây mất niềm tin hoàn toàn vào ứng dụng.
    
    MD\+ 2
    
*   **Chốt giải pháp (Chọn Option B của `plan3.md`):** Đổi return type của hàm render sang `ScheduleRenderResult`:
    
    MD
    

TypeScript

    interface ScheduleRenderResult {
      occurrences: ShiftOccurrence[]; // Các ca hợp lệ
      issues: RenderIssue[];          // Danh sách lỗi: DST_NONEXISTENT, AMBIGUOUS_TIME, MISSING_TEMPLATE
    }

### 🔴 Lỗi 3: Giả định sai số ±1 giờ khi tính DST Offset

*   **Hiện trạng:** Code Time Engine suy ra alternative UTC bằng `utc1 ± 1 hour`.
    
    MD
    
*   **Đánh giá:** Giả định này sẽ hỏng hoàn toàn ở các quốc gia/vùng dùng múi giờ lệch (như Lord Howe Island lệch 30 phút DST, hay Nepal +05:45).
    
    MD
    
*   **Chốt giải pháp:** Loại bỏ hoàn toàn phép cộng trừ cứng 1 giờ. Time Engine phải truy vấn trực tiếp thư viện TimeZone Database để lấy chính xác 2 candidate UTC Instants trong trường hợp rơi vào vùng nhập nhằng (Ambiguous Local Time).
    
    MD\+ 2
    

2\. Bổ sung & Đóng góp Kiến trúc Domain
---------------------------------------

### A. Quy trình Override Command Pipeline

Thay vì gọi `applyOverride()` để chỉnh sửa trực tiếp mảng danh sách, toàn bộ các thao tác `CREATE`, `UPDATE`, `DELETE`, `REPLACE`, `SPLIT`, `SWAP` phải chạy qua một Pipeline thống nhất:

MD\+ 2

Override Payload 
      └─► Input Validation (Format, Range)
            └─► Resolve Local Civil Time
                  └─► TZ Engine (Resolve UTC Candidates)
                        └─► Apply Invariants Check
                              └─► Output: Immutable Valid ShiftOccurrence(s)

### B. Chuẩn hóa Semantics cho thao tác SWAP (Tráo ca)

*   **Phản biện `plan3.md`:** `plan3.md` cảnh báo không nên copy cứng UTC từ ca A sang ca B.
    
    MD
    
*   **Chốt quy tắc:** SWAP trong ShiftEase được định nghĩa là **"Trao đổi Local Civil Intent"**. Ví dụ: Tráo ca Đêm (22:00 NY) của A với ca Ngày (07:00 LDN) của B -> Lấy cấu hình Local Time tráo đổi cho nhau, sau đó re-resolve UTC theo múi giờ địa phương của từng ca.
    
    MD\+ 1
    

### C. Tách biệt Occurrence Identity và Projection Identity

*   Không dùng String ID dạng `pattern_2026-09-04_day` làm primary key cố định.
    
    MD
    
*   **Cấu trúc ID đề xuất:**
    
    *   `occurrenceId`: UUID v4 cố định cho từng thực thể.
        
        MD
        
    *   `projectionHash`: `hash(patternId + shiftDate + version)` dùng để truy vết nguồn gốc baseline.
        
        MD\+ 1
        

3\. Bổ sung UX/UI Production Cốt lõi (Trải nghiệm Thực tế)
----------------------------------------------------------

Để ứng dụng đạt chất lượng Production thương mại chứ không dừng lại ở bản Demo, các tính năng UI sau cần được bổ sung vào roadmap:

MD

### 1\. "Glanceable Today" Screen (Màn hình chính đỉnh cao)

*   **Next Shift Card (Nổi bật nhất):** Hiển thị ca sắp tới kèm Countdown trực tiếp (_"Working in 03h 24m"_ hoặc _"OFF for 1d 08h"_).
    
    MD
    
*   **Recovery Window Indicator:** Báo khoảng thời gian khuyến nghị hồi phục sau ca đêm (_"Recommended recovery: 07:30 → 14:30"_).
    
    MD
    

### 2\. Sự Minh bạch Tuyệt đối (Build Trust)

*   **Feature "Why this shift?":** Khi bấm vào một ca làm, ứng dụng hiển thị rõ nguồn gốc:
    
    MD
    
    > _Nguồn: Pattern 4-on/4-off (Ngày 3/8) | Ghi đè: Override #102 | Múi giờ áp dụng: America/New\_York_
    > 
    > MD\+ 1
    
*   **Feature "What Changed?" (Roster History):** Nhật ký ghi lại các thay đổi của ca làm (VD: Ca ban đầu từ Pattern -> Sếp đổi giờ -> Bạn tự tráo ca).
    
    MD
    
*   **Pay Breakdown Detailed View:** Không chỉ hiện tổng tiền, mà hiển thị chi tiết: Lương gốc + Phụ cấp đêm + Phụ cấp cuối tuần + Overtime.
    
    MD\+ 1
    

### 3\. An toàn Dữ liệu & Miễn nhiễm Lỗi thao tác

*   **System-wide Undo:** Cho phép hoàn tác ngay lập tức khi xóa nhầm hoặc import đè lịch.
    
    MD
    
*   **Conflict & Duplicate Detection:** Cảnh báo khi ca làm đè lên lịch cá nhân (nha sĩ, họp phụ huynh) hoặc khi import trùng ca.
    
    MD
    
*   **Local Encrypted Backup (.json):** Cho phép Xuất/Nhập dữ liệu mã hóa cục bộ trước khi có tính năng Cloud Sync.
    
    MD\+ 1
    

4\. Khung Quản trị AI Agent theo Gates (Gates Strategy)
-------------------------------------------------------

Để tránh việc AI Coding Agent tự ý sinh code UI/Database dựa trên core engine đang lỗi, quy trình phát triển bắt buộc tuân theo **6 Cổng Kiểm soát (Gates)**:

MD\+ 2

┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐
    │ GATE 0 │───►│ GATE 1 │───►│ GATE 2 │───►│ GATE 3 │───►│ GATE 4 │───►│ GATE 5 │
    └────────┘    └────────┘    └────────┘    └────────┘    └────────┘    └────────┘
    Core Contract   Money Engine  Persistence   Domain Model  Calendar UX   Import/Sync
     Hardening      & Pay Rules    & SQLite       & Jobs

### Acceptance Criteria Bắt buộc cho GATE 0 (Gate hiện tại):

1.  ✅ **Zero Empty Temporal Fields:** Không còn bất kỳ `ShiftOccurrence` nào chứa UTC/Timezone rỗng.
    
    MD
    
2.  ✅ **100% Operations Resolved:** 6 thao tác `CREATE`, `UPDATE`, `DELETE`, `REPLACE`, `SPLIT`, `SWAP` xử lý chính xác 100% thời gian UTC và Local Time.
    
    MD
    
3.  ✅ **No Silent Drop:** `renderEffectiveSchedule()` trả về `ScheduleRenderResult` chứa đầy đủ danh sách ca làm lẫn danh sách lỗi (DST/Template).
    
    MD
    
4.  ✅ **Timezone Boundary Verification:** Đạt 100% pass trên bộ test suite phủ các múi giờ đặc biệt (lệch 30/45 phút) và chuyển đổi DST.
    
    MD\+ 1
    

**Hành động ngay:** Khởi chạy Gate 0 với yêu cầu: **"ShiftEase Core Contract Hardening — Time + Pattern + Override + Effective Schedule"**. Sau khi Gate 0 được verify xanh hoàn toàn mới mở prompt cấp phép phát triển `core/money`.

MD\+ 1