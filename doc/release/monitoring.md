# P9.4/P9.5 — Production Monitoring Runbook + Feedback Triage (ShiftEase)

> Nguồn: `phases/P9_production_launch.md` §4–§5 · `plan_p9.md` §P9.4/P9.5.
> **Honesty (D-P9.6, cập nhật 2026-09-11 lần 2 — AdMob):** app local-only; **Sentry crash reporting** (error-only, PII off) + **AdMob ads** (`google_mobile_ads` ^9.1.0, TEST mode `admob.test_ads=true`) đều user-approved — xem `doc/release/privacy.md`. Monitoring = **Sentry dashboard (crash/error) + AdMob console (sau khi có account thật: impressions/clicks/revenue + policy center) + Play/App Store console + kênh user support + quy trình thủ công**. KHÔNG analytics/telemetry ngoài 2 SDK đó — thêm SDK khác → user duyệt riêng + re-audit privacy (NEVER thêm lén).

## Part 1 — Monitoring signals (P9.4)

Nguồn tín hiệu khả dụng thật:

1. **Sentry dashboard** — crash/uncaught error theo version + OS, stack trace đầy đủ (error-only: PII off, traces off). Tích hợp 2026-09-11, DSN trong `lib/main.dart`. Tần suất check: mỗi ngày trong staged launch, mỗi tuần sau đó
2. **AdMob console** — impressions/clicks/revenue theo ad unit, **policy center alerts** (invalid traffic, LIMIT status). Tích hợp 2026-09-11 (TEST mode — số liệu chỉ có ý nghĩa khi flip production + tạo account/unit thật). Alert cần hành động: ads LIMIT = dừng rollout + review traffic chất lượng
2. **Play Console / App Store Connect** — crash rate, ANR, rating/review text, (nếu bật) Android vitals
3. **Kênh support** (email/form/user group của closed cohort)
4. **Kiểm tra thủ công định kỳ** — cài build production lên máy giữ làm "canary device", chạy smoke rút gọn sau mỗi stage rollout

| Nhóm | Tín hiệu theo dõi | Nguồn |
|---|---|---|
| **Stability** | crash, startup fail (treo splash/recovery screen), fatal, DB open fail (recovery screen xuất hiện = key/DB không mở được) | store console + support + canary |
| **Data** | migration fail (nâng cấp mất data), restore fail, backup fail (file không tạo / không đọc lại được), corruption report, "missing shift" report | support + canary |
| **Time** | DST fail (giờ lệch sau đổi giờ), timezone report (đi vùng khác), overnight duration sai | support + canary |
| **Income** | số tiền sai, UNAVAILABLE xuất hiện thường xuyên (spam), PayRule version confusion | support |
| **Notification** | permission fail (không được hỏi/bị từ chối vĩnh viễn), stale (nhắc ca đã qua), duplicate, missing (không nhắc) | support + canary |
| **Store signals** | review score/rate, review text themes, uninstalls (nếu hiển thị) | store console |

Nhịp kiểm tra đề xuất: hàng ngày trong Stage 1–2, 2–3 ngày/lần sau đó; **bắt buộc** trước mỗi lần tăng exposure (`staged_launch.md` §2).

## Part 2 — Triage template (P9.5)

Mỗi production issue nhận đủ các trường sau (không trống — "unknown" phải ghi rõ):

```text
[ID-YYMMDD-nn] <tiêu đề>
Severity:        P0 | P1 | P2 | P3
Repro:           always | sometimes | once | not-yet
Platform:        Android 13+ | Android <13 | iOS <phiên bản> | all
Version/build:   1.0.0+<n> (từ report/canary)
Feature:         stability | data | time | income | notification | import | backup | UX
Data-loss risk:  yes/no — mô tả nếu yes
Workaround:      <bước cụ thể cho user, hoặc none>
Evidence:        link/tệp (screenshot, log, backup file bị lỗi — BẢO TOÀN, không ghi đè)
Owner:           <tên>
Status:          open | investigating | fix-in-progress | fixed-awaiting-release | released | closed
```

Priority handling:

| Severity | SLA hành động |
|---|---|
| **P0** | Immediate emergency — mở `data_loss_incident.md` nếu dính data; ngược lại `hotfix_procedure.md` ngay; halt rollout |
| **P1** | Urgent fix — hotfix stream; stop ship tới khi fix+rebuild |
| **P2** | Scheduled — đợt fix kế hoặc release sau; ghi backlog nếu không release-blocking |
| **P3** | Backlog — `post_production_backlog.md` (không trộn vào hotfix) |

Đếm số lượng theo severity mỗi tuần → điền vào `result_p9_launch.md` (P0–P3 counts).
