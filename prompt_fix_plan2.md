# Yêu cầu sửa `plan2.md` trước khi tiếp tục

Tôi đã review `plan2.md` bạn gửi. Cấu trúc tổng thể tốt (ER diagram, VersionedEntity, Override enum, state machine Import, CI gate đều đúng tinh thần đã khóa ở `plan1_final_v2.md`). Nhưng có **2 lỗi kỹ thuật thật sự** nằm đúng trong 2 module "bảo vệ tuyệt đối" (`core/time`, `core/money`) — phải sửa trước khi tôi duyệt sang bước viết Golden Test Suite / implementation. Ngoài ra có 4 khoảng trống và một số lỗi encoding cần dọn.

**Không tự ý bỏ qua hoặc coi nhẹ 2 lỗi dưới đây — đây chính là loại lỗi mà toàn bộ `plan1_final_v2.md` được viết ra để ngăn chặn.**

---

## 🔴 Lỗi #1: Golden test case DST-001 / DST-002 sai ngày (mục 7.1)

Quy ước `shiftDate` đã chốt xuyên suốt dự án: `shiftDate` = ngày ca *bắt đầu* buổi tối.

**DST-001** ghi `shiftDate: "2026-03-08"`, tức ca bắt đầu 22:00 ngày 08/03. Nhưng đổi giờ mùa xuân (spring-forward) tại Mỹ năm 2026 xảy ra lúc **2:00 sáng ngày 08/03** — tức là *trước* 22:00 cùng ngày. Vậy ca 22:00 08/03 → 06:00 09/03 diễn ra **hoàn toàn sau** thời điểm đổi giờ, không cắt ngang DST gì cả — nó phải là ca 8 tiếng bình thường, không phải 7 tiếng như case đang ghi.

Ca thực sự cắt ngang đêm đổi giờ phải có `shiftDate: "2026-03-07"` (bắt đầu tối thứ Bảy 07/03, kết thúc sáng Chủ Nhật 08/03 — đúng đêm xảy ra bước nhảy 2h→3h).

**DST-002** (`shiftDate: "2026-11-01"`, fall-back) mắc lỗi tương tự — đổi giờ mùa thu xảy ra lúc 2h sáng 01/11, nên ca cắt ngang phải có `shiftDate: "2026-10-31"`, không phải `"2026-11-01"`.

**Yêu cầu:**
- Sửa lại `shiftDate` cho DST-001 và DST-002.
- Tính lại toàn bộ `utcStart`/`utcEnd`/`durationHours` cho cả 2 case bằng thư viện timezone chuẩn dựa trên IANA tz database (VD: `luxon`, `Temporal`, hoặc tương đương trong ngôn ngữ bạn dùng) — **không tự tính tay**.
- Sau khi sửa, chạy độc lập một script nhỏ in ra kết quả UTC cho từng case DST trong file, để tôi có thể đối chiếu trước khi coi bộ test này là "golden".
- Rà lại toàn bộ các case DST khác trong file (kể cả case tưởng như đã đúng) bằng cùng phương pháp — vì đây là golden test, một lỗi lọt qua sẽ khiến code sai vẫn "pass".

## 🔴 Lỗi #2: Overtime double-counting trong Pay Engine (mục 5.2 + 5.4)

Thuật toán hiện tại:
- `Base Pay` = toàn bộ `durationHours × baseHourlyRate` (tính **tất cả** giờ, kể cả giờ overtime, ở mức 1x)
- `Overtime` = `overtimeHours × baseHourlyRate × multiplier` (cộng **thêm**, không thay thế)

→ Giờ overtime bị tính **(1 + multiplier)x** thay vì đúng **multiplier x**. Với multiplier 1.5, người dùng bị tính 2.5x thay vì 1.5x — sai ngay từ công thức gốc.

**Yêu cầu:** chọn một trong hai cách sau, ghi rõ lựa chọn và lý do trong `plan2.md`, rồi sửa code mẫu ở mục 5.2:

- **Cách A — Overtime Premium:** `Base Pay` tính tất cả giờ ở 1x (giữ nguyên); dòng `Overtime` chỉ cộng phần **premium**: `overtimeHours × baseHourlyRate × (multiplier - 1)`.
- **Cách B — Regular + OT tách bạch:** `Base Pay` chỉ tính `regularHours = durationHours - overtimeHours`; dòng `Overtime` tính đầy đủ `overtimeHours × baseHourlyRate × multiplier`.

Cả hai cách đều cho tổng đúng — chọn cách nào rõ ràng hơn để hiển thị trên UI breakdown cho người dùng, rồi document lại.

**Đồng thời sửa `calculateOvertimeHours` (mục 5.4):** hàm hiện tại `return` ngay ở rule đầu tiên trong vòng lặp `overtimeRules`, nghĩa là nếu có nhiều rule cùng lúc (VD: "SHIFT > 8h" và "WEEK > 40h" — rất phổ biến, giống luật California) thì **chỉ rule đầu tiên trong mảng được áp dụng**, các rule sau bị bỏ qua hoàn toàn. Cần:
- Định nghĩa rõ cách kết hợp nhiều rule: lấy `max()` giữa các rule áp dụng được, hay áp theo thứ tự ưu tiên đã cấu hình.
- Đảm bảo không cộng dồn overtime hours hai lần nếu cùng một khung giờ khớp cả rule SHIFT và rule WEEK.
- Viết rõ pseudo-code mới thay cho bản hiện tại, kèm ví dụ số cụ thể (VD: ca 10h/ngày, tuần đã làm 42h → bao nhiêu giờ OT, tính theo rule nào).

---

## 🟡 4 khoảng trống cần bổ sung

1. **`CalendarEvent` mới chỉ có supertype.** `plan1_final_v2.md` mục 5 đã chốt 4 subtype: `ShiftOccurrence`, `TimeOff`, `PersonalEvent`, `AvailabilityBlock`. `plan2.md` chỉ định nghĩa `CalendarEvent` chung chung với `refId` trỏ tới đâu đó — cần bổ sung interface cụ thể cho `TimeOff`, `PersonalEvent`, `AvailabilityBlock` và vẽ lại vào ER diagram ở mục 2.1.

2. **Pay Rule Template Library biến mất.** `plan1_final_v2.md` mục 7 đã chốt: cung cấp sẵn template theo ngành/quốc gia (VD: "US Hospital Nurse — California overtime rule") để người dùng mới không phải tự cấu hình từ đầu. `plan2.md` không có section nào cho việc này. Bổ sung một mục nhỏ trong phần 5 (Pay Engine) mô tả cấu trúc `PayRuleTemplate` và cách seed dữ liệu ban đầu cho ít nhất Mỹ/Anh/Đức.

3. **Golden test cho Money Engine chưa tồn tại.** CI job ở mục 7.3 có bước `Run Golden Tests (Money Engine)` nhưng không có file case nào tương ứng như `time_engine_cases.json`. Đúng chỗ vừa phát hiện bug overtime — càng cần viết `money_engine_cases.json` với các case cụ thể (base pay, từng loại differential, overtime theo SHIFT/DAY/WEEK, kết hợp nhiều differential cùng lúc) **trước khi** code Pay Engine.

4. **OCR spike-test gate không được phản ánh trong Milestones.** `plan1_final_v2.md` mục 8 đã mandate: không commit kiến trúc OCR lớn trước khi test với 20-30 roster thật. Nhưng M5 "OCR Import" ở mục 8.1 ghi thẳng 3 tuần như một cam kết chắc chắn. Sửa lại: thêm một milestone `M4.5: OCR Spike Test` (1 tuần, không phải build architecture) trước M5, với deliverable là báo cáo % correct dates/shift type/start-end trên tập roster thật, và điều kiện: chỉ tiến hành M5 đầy đủ nếu kết quả spike-test đạt ngưỡng tối thiểu (bạn đề xuất ngưỡng cụ thể, tôi sẽ duyệt).

---

## 🟢 Dọn dẹp nhỏ

Rà lại toàn văn bản `plan2.md` — có vài chỗ bị lỗi encoding, lẫn ký tự không phải tiếng Việt/tiếng Anh dự kiến:
- Dòng ~324 (bảng Confidence Scoring, cột "Date format"): ký tự lạ thay vì từ "mờ"/"không rõ ràng"
- Dòng ~765 (comment trong `WebcalToken.token`): ký tự lạ thay vì "random-generated"
- Dòng ~786 (Sharing flow bước 2): chữ bị thiếu/lẫn, có vẻ đang muốn nói "anonymous UUID"

Đây có thể là dấu hiệu lỗi rộng hơn khi sinh văn bản — quét toàn file bằng công cụ kiểm tra ký tự ngoài phạm vi ASCII/Unicode tiếng Việt chuẩn để chắc chắn không còn chỗ nào khác.

---

## Sau khi sửa xong

Gửi lại `plan2.md` đã sửa kèm:
1. Output của script kiểm tra lại các case DST (yêu cầu ở Lỗi #1)
2. Ví dụ số cụ thể minh họa công thức overtime mới không còn double-count (yêu cầu ở Lỗi #2)
3. Diff ngắn gọn liệt kê những gì đã thay đổi so với bản trước

Tôi sẽ review lại trước khi cho phép chuyển sang bước viết Golden Test Suite đầy đủ và bắt đầu implementation.
