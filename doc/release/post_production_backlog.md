# P9.9 — Post-Production Feature Backlog (list only — KHÔNG code trong P9)

> Nguồn: `phases/P9_production_launch.md` §9 · `plan_p9.md` §P9.9.
> **Không phải release blocker P9.** Chỉ được mở code khi: production ổn định + first production review đạt + mỗi item có spec riêng qua gate discipline (spec → duyệt → rồi mới code). Không trộn vào hotfix stream.

## Backlog (thứ tự không phải cam kết ưu tiên)

| # | Feature | Ghi chú |
|---|---|---|
| 1 | OCR roster import | M4.5 spike spec đã có: `.plan/plan11_ocr_spike.md` (thresholds 70/60 locked, chờ 20–30 roster thật + ground truth từ user) |
| 2 | Cloud sync | Cần thiết kế xung đột + đổi mô hình privacy (hiện "no data collected" kiểm chứng được — thêm sync = re-audit bắt buộc) |
| 3 | Account system | Đổi privacy model; cân nhắc kỹ — mất lợi thế "no account" trong store copy |
| 4 | Sharing / partner overlay | Family/partner shift sharing; permission model mới |
| 5 | Widgets | Home-screen widget ca sắp tới; platform API mới (glance/HomeWidget) |
| 6 | Shift change detection | So sánh roster định kỳ, notify khi thay đổi |
| 7 | Wellness rules | Giới hạn giờ làm liên tiếp; cần input từ production review |
| 8 | Advanced AI | Chỉ sau khi có use case được xác nhận từ production feedback |
| 9 | B2B / payroll integrations | Đổi phạm vi sản phẩm; compliance riêng |

## Quy tắc

- Mọi feature ở đây **cấm** xuất hiện trong hotfix hoặc staged rollout
- User feedback từ production (first_production_review.md §1) quyết định thứ tự ưu tiên thực tế
- Feature nào bật network/analytics → re-audit `doc/release/privacy.md` + data safety form trước khi ship
