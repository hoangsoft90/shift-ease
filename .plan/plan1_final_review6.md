phân tích  review của các AI khác plan1_final_review*.md dành cho plan1_final.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện cuối cùng. Sau đó tổng hợp chốt solution vào plan1_final_v2.md
--------------------
Viewed 2 files, ran a command

Viewed 2 files, ran a command

### Phân tích tổng hợp cuối: 5 bản review cho `plan1_final.md`

Đã đọc toàn bộ (review1 rất dài — bản kỹ thuật sâu nhất trong cả chuỗi; review2/4/5 hội tụ gần như trùng khớp; review3 bổ sung thêm góc nhìn thực thi). Điểm mấu chốt: **plan1\_final.md đã chốt xong tầm nhìn sản phẩm (9/10), nhưng domain model chưa sẵn sàng để code (Pay Engine chỉ 5.5/10, Import Strategy 6/10)**. Cả 5 review đồng thanh: **không code ngay, cần một vòng nữa để khóa kiến trúc domain.**

#### Đồng thuận tuyệt đối (5/5 review)

*   Bỏ "tính đúng tuyệt đối" → **Correctness Contract**: deterministic với input hợp lệ, báo "không tính được" thay vì đoán sai
*   Smart Import **không được auto-commit**: `Parse → Candidate Shifts → Confidence Score → User Review → Commit`
*   **Tách hoàn toàn** `ShiftTemplate` (thời gian/UI) khỏi `PayRule` (tiền) — `payMultiplier` trong template là nguồn double-counting
*   Recurrence chạy theo **Local Civil Time**, không phải UTC interval thuần túy
*   `isException: boolean` quá yếu → cần **Override object** với operation rõ ràng (CREATE/UPDATE/DELETE/REPLACE/SPLIT/SWAP)
*   **Pattern & PayRule phải versioned** (`effective_from`/`effective_until`) — không mutate lịch sử
*   Widget & Smart Commute → dời sang P1; Quick Add + Paste text/CSV → đẩy lên P0
*   Cần **Architectural Invariants + NEVER list** làm kim chỉ nam cho AI agents
*   Webcal: tách `.ics` export offline (P0) khỏi Dynamic Webcal cần server/token (P1+)

#### Mâu thuẫn cần xử lý dứt điểm

**OCR ở P0 hay P1?** Review1 (kỹ nhất): đừng quyết bằng cảm tính — làm prototype với 20-30 roster thật, đo % correction cần thiết, rồi mới quyết. Review3: muốn OCR sớm hơn vì đây là "sống còn". **Quyết định chốt:** Paste text/CSV = P0 (rủi ro thấp, giá trị cao ngay). Image OCR/PDF = P1, **có gate**: chỉ commit kiến trúc lớn sau khi spike-test đạt ngưỡng chất lượng tối thiểu.

**Health/Wellness bỏ hẳn hay giữ nhẹ?** Review3 nhấn mạnh giữ (rule-based, không AI). Tôi giữ nguyên chủ trương P2 đã chốt ở `plan1_final.md`, nhưng tách riêng: "thời gian nghỉ giữa ca" (tính toán thuần túy từ dữ liệu occurrence) đưa lên Today screen ngay từ P0 vì không phải feature sức khỏe mới, chỉ là hiển thị dữ liệu sẵn có.

#### Bổ sung mới từ review3 (chưa ai nói)

*   **ImportSession** lưu lại để audit + hỗ trợ "What changed?" khi employer gửi roster mới
*   **Pay Differential dạng pluggable** (không hard-code vài field) để dễ thêm hazard pay, call-back pay sau này
*   **Pattern type mở rộng** (`FIXED_CYCLE | ALTERNATING_WEEKS | CUSTOM`) — kiến trúc chừa chỗ, không cần implement hết ngay
*   **Partner reverse-sharing** (đối tác đề xuất sự kiện vào lịch user, pending/accepted) — để dành P2/P3
*   Yêu cầu AI agent sinh kèm **test đơn vị + file giải thích logic** cho mỗi module lõi, con người review trước khi nhận code

#### Một lưu ý cần treo lại

Review1 nhắc tới việc có "`plan1_review6.md`" tồn tại trong thư mục dự án cục bộ của người dùng đó. Tôi không có file này và `plan1_final.md` của chúng ta được xây dựng chính xác từ review1–5 đã có — nên bỏ qua chi tiết này, không phải sai sót cần sửa trong tài liệu của ta.

Giờ tổng hợp chốt vào `plan1_final_v2.md`.

Creating fileCreating file

Creating file

1 minute ago