# P9.8 — First Production Review (template)

> Nguồn: `phases/P9_production_launch.md` §8 · `plan_p9.md` §P9.8.
> Thực hiện sau cửa sổ ổn định đầu tiên — **human chọn ngày** (gợi ý 7–14 ngày sau full release). Review này quyết định phase tiếp theo; **tách khỏi hotfix stream** — không trộn quyết định roadmap với việc dập P0/P1.

## Thông tin review

| Trường | Giá trị |
|---|---|
| Review date | ____________________ |
| Cửa sổ dữ liệu | từ ______ đến ______ (≥7 ngày sau full release) |
| Version đang chạy production | 1.0.0+____ |
| Người review | ____________________ |

## 1. Đánh giá theo khu vực (mỗi dòng: OK / ISSUE + evidence)

| Khu vực | Câu hỏi | Kết quả |
|---|---|---|
| Crash / startup | Crash-free sessions đạt mức nào (store console)? Có startup-fail/recovery-screen report? | ______ |
| Notification | Stale/duplicate/missing report? Permission flow vướng ở đâu? | ______ |
| Backup/restore | Round-trip health trên canary + support channel? Corrupt file report? | ______ |
| UX | Top complaints từ reviews/support (top 3)? | ______ |
| Import/re-import | Thất bại ở bước nào (map/validate/review/commit)? Diff/impact card hiểu được không? | ______ |
| Income | Sai số report? UNAVAILABLE gặp quá thường xuyên? PayRule confusion? | ______ |
| Device/OS | Model/OS version nào tập trung issue? minSdk/targetSdk còn hợp lý? | ______ |
| Data integrity | Bất kỳ báo hiệu corruption/missing data? (nếu có → incident procedure đã chạy đúng chưa) | ______ |

## 2. Issue counts tại thời điểm review

| P0 | P1 | P2 | P3 | Ghi chú |
|---|---|---|---|---|
| ___ | ___ | ___ | ___ | từ triage log (`doc/release/monitoring.md` Part 2) |

## 3. Quyết định phase tiếp theo (tách khỏi hotfix)

- [ ] Production ổn định theo tiêu chí phase §11 → mở giai đoạn feature tiếp theo từ `doc/release/post_production_backlog.md` (chọn ĐÚNG MỘT, spec trước — gate discipline)
- [ ] Chưa ổn định → kéo dài monitor / fix P1/P2 rồi review lại
- Quyết định: ____________________ (ngày + người + lý do)

## 4. Bài học quy trình

- Điều gì trong runbook (monitoring/triage/hotfix) hoạt động tốt / cần sửa? → cập nhật docs
- Privacy/monitoring setup có cần re-audit? (`doc/release/privacy.md` checklist)
