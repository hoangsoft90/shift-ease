# P9.3 — Staged Launch Plan (ShiftEase)

> Nguồn: `phases/P9_production_launch.md` §3 · `plan_p9.md` §P9.3.
> Nguyên tắc: **launch ≠ feature delivery** — không gắn staged rollout với thay đổi feature nào (D-P9.1).

## 1. Giai đoạn

```text
Stage 0: submission accepted (store console)
Stage 1: small exposure      → Play staged 10% / TestFlight cohort (5–20)
Stage 2: monitor (≥3 ngày không có tín hiệu đỏ — xem §3)
Stage 3: increase            → 25% → 50% (mỗi bước ≥2 ngày monitor)
Stage 4: full release        → 100%
```

iOS: dùng phased release (7 ngày tự động) + hủy được; tương đương tiêu chí §3.

## 2. Điều kiện tăng exposure (Stage n → n+1)

TẤT CẢ phải đúng:

- [ ] Không P0/P1 mới trong cửa sổ monitor của stage hiện tại
- [ ] Không data-loss/corruption report mới
- [ ] Không crash/startup-fail report mới
- [ ] Notification signals (stale/duplicate/missing) = không tăng theo version mới
- [ ] Backup/restore report = healthy
- [ ] Store console (crash/ANR/vitals, nếu dùng) trong ngưỡng store

## 3. Tín hiệu đỏ — HALT/ROLLBACK

Halt ngay (pause rollout tại % hiện tại) khi bất kỳ:

- 1 report data-loss/corruption nghiêm trọng (chưa xác nhận root cause) → **halt + mở `doc/release/data_loss_incident.md`**
- Crash/startup-fail có repro → halt + hotfix procedure
- Nhiều report độc lập cùng triệu chứng time/income sai → halt, repro trước

Rollback (halt progression; Play không un-install được — halt chặn mở rộng; nếu lỗi nghiêm trọng → hotfix build mới theo `doc/release/hotfix_procedure.md`, KHÔNG "rebuild lén cùng build số").

## 4. Quy tắc trong rollout

- Không hủy/trộn feature change vào các build rollout (chỉ hotfix theo §3 của file này)
- Mỗi stage tăng phải ghi vào `doc/release/submission_record.md` (track/date/%)
- Monitor theo `doc/release/monitoring.md`; triage theo Part 2 của file đó

## 5. Kết thúc

Full release (100%) + không P0/P1 mở + không data-loss incident mở → đánh dấu **PRODUCTION LIVE** trong `result_p9_launch.md` (human xác nhận).
