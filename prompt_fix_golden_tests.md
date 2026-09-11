# Yêu cầu sửa Golden Test Suite trước khi duyệt Bước 1

Đã review `result1.txt`. Phần lớn đúng và làm kỹ (đặc biệt case DST UK, Australia, ranh giới năm — tôi đã tự tính tay độc lập và khớp). Nhưng có 1 lỗi tính toán, 1 chỗ cần giải trình, và 1 vấn đề hình thức nộp bài cần xử lý trước khi tôi duyệt để sang Bước 2.

---

## 🔴 Việc 1: Sửa lỗi SH-002 (Australia fall-back)

Case hiện tại tự mâu thuẫn với chính ghi chú của nó.

Ghi chú viết: *"22:00 Apr 4 **AEDT** → 06:00 Apr 5 **AEST**"* — đúng, vì lúc 22:00 tối 04/04 chưa tới thời điểm chuyển giờ (~3h sáng 05/04), nên offset đầu ca phải là AEDT = **UTC+11**.

Nhưng `utcStart: 2026-04-04T12:00:00.000Z` lại tương ứng với offset **+10** (AEST — offset *sau* khi đã chuyển giờ), không phải +11 như ghi chú tự nói.

Tính đúng: `22:00 - 11h = 11:00Z`.

**Yêu cầu sửa:**
- `utcStart`: `2026-04-04T11:00:00.000Z` (không phải `12:00:00.000Z`)
- `utcEnd`: giữ nguyên `2026-04-04T20:00:00.000Z` (offset AEST/+10 sau chuyển giờ, đã đúng)
- `durationHours`: sửa thành `9.0` (không phải `8.0`)
- Sửa luôn tiêu đề mô tả case từ *"Fall-back Apr (8h→8h)"* thành *"Fall-back Apr (8h→9h)"* — đúng pattern chung của mọi fall-back case khác trong bộ (DST-002, DST-005, DST-007 đều 8h→9h). Tiêu đề "8h→8h" hiện tại tự mâu thuẫn với định nghĩa fall-back.
- Chạy lại `scripts/verify_all_cases.mjs` sau khi sửa, xác nhận case này giờ pass tự-nhất-quán (`utcEnd - utcStart = durationHours`).

## 🟡 Việc 2: Giải trình PAY-005 (Week-level OT)

Đối chiếu số liệu: `Regular Pay $350` (= 10h × $35), `OT Pay $105` (= 2h × $35 × 1.5). Nhưng theo công thức "Cách B" đã chốt (`Regular = duration - overtimeHours`), nếu ca này dài 10h và có 2h được tính là overtime, Regular Pay phải là `8h × $35 = $280`, không phải $350 — nếu không, 2h đó vừa được trả ở mức 1x (nằm trong Regular) vừa được trả thêm 1.5x (Overtime) = double-count, đúng loại lỗi đã sửa ở vòng trước.

**Có thể** đây là do 2h OT này đến từ việc tổng hợp nhiều ca trong tuần (không phải riêng ca PAY-005 vượt ngưỡng), và cách phân bổ theo tuần có logic khác với phân bổ theo ca đơn lẻ. Nhưng báo cáo hiện tại không đủ chi tiết để xác nhận.

**Yêu cầu:** giải thích rõ trong `EXPLANATION.md` (hoặc file tương đương) cách hệ thống phân bổ overtime hours khi ngưỡng là `WEEK` chứ không phải `SHIFT`:
- Nếu case PAY-005 chỉ có 1 ca duy nhất trong tuần đó (input đơn giản để test), thì phải sửa số theo đúng Cách B như PAY-004/006/007.
- Nếu case này giả định có nhiều ca khác trong cùng tuần (input phức tạp hơn), cần show rõ input đầy đủ của tất cả các ca trong tuần đó và cách 2h OT được gán vào ca nào — không chỉ đưa ra 1 ca với con số tổng.

## 🟢 Việc 3: Đính kèm file thật, không chỉ báo cáo tóm tắt

`result1.txt` là báo cáo tổng hợp — tôi cần file thật, chạy được, để verify độc lập (không chỉ đọc số liệu đã qua tổng hợp). Gửi kèm trực tiếp:

- `test/golden/time_engine_cases.json`
- `test/golden/money_engine_cases.json`
- `test/golden/import_pipeline_cases.json`
- `.github/workflows/test.yml`
- `scripts/verify_all_cases.mjs`

## 🟢 Việc 4 (nhỏ): Rà lại ghi chú tiếng Anh/Việt lẫn ngôn ngữ khác

Ghi chú SH-001 lẫn một từ tiếng Hà Lan ("altijd" thay vì "always"). Không ảnh hưởng nội dung, nhưng rà nhanh toàn bộ ghi chú trong 3 file JSON xem còn chỗ nào tương tự không — nhất là sau sự cố mất dấu tiếng Việt ở vòng trước, nên cẩn trọng hơn với mọi thao tác sinh/sửa text hàng loạt.

---

## Sau khi sửa xong

Gửi lại đầy đủ 5 file thật ở trên (không phải báo cáo tóm tắt), kèm:
1. Xác nhận SH-002 đã pass verify script
2. Giải thích PAY-005 kèm input đầy đủ nếu là case nhiều ca/tuần
3. Output đầy đủ của `verify_all_cases.mjs` cho toàn bộ 20+ time engine cases

Sau khi cả 4 việc trên đạt, tôi sẽ duyệt để chuyển sang Bước 2: Implement `core/time`.
