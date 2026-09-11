# PROMPT — ShiftEase P9: Production Launch / Post-release Monitoring

> Đọc và tuân thủ: `.plan/plan_p9.md` + `phases/P9_production_launch.md`
> User: P8 PREP xong; bỏ qua/waive phần device-signed-closed nếu không có evidence — **ghi honest, không PASS giả**.
> **Không feature mới. Không OCR / Cloud / AI / Sharing / B2B.**

---

## Nhiệm vụ

Làm **P9 launch prep / ops** — tài liệu + runbook + template. Không ship feature.

Tách rõ:

- Agent **phải xong** trong session: docs P9.1–P9.9 + `result_p9_launch.md`
- Human/store: submit, staged rollout, monitor thật — ghi **NOT RUN / BLOCKED**, không tự PASS

---

## Task (theo thứ tự)

### P9.1 — Final release gate

Tạo `doc/release/final_release_gate.md`:

- Bảng P0–P8 honest (P7 device / P8 signed-smoke-closed = BLOCKED hoặc waived by user)
- Cấm ship nếu còn data-loss / migration-loss / major time-income error / encryption failure
- Freeze còn hiệu lực; version từ pubspec

### P9.2 — Submission record

Tạo `doc/release/submission_record.md` (template):

- revision, version+build, artifact + checksum, date, platform, track
- Quy tắc: submit đúng artifact đã freeze; không rebuild lén

### P9.3 — Staged launch

Tạo `doc/release/staged_launch.md`:

`small exposure → monitor → increase → full`

- Tiêu chí tăng rollout / halt
- Không gắn feature change vào launch

### P9.4 / P9.5 — Monitoring + triage

Tạo `doc/release/monitoring.md` (+ triage):

- Stability / Data / Time / Income / Notification signals
- App local-only: không bịa analytics dashboard
- Issue fields: severity, repro, platform, version, feature, data-loss risk, workaround, owner, status

### P9.6 — Hotfix procedure

Document: detect → evidence → repro → root cause → minimal fix → regression → release → emergency ship → monitor.

**NEVER** nhét feature vào hotfix.

### P9.7 — Data-loss incident

Stop releases → repro on copy → versions/path → evidence → test → fix → verify backup/restore → hotfix → write-up.

**NEVER** first response = xóa database user.

### P9.8 — First production review template

Crash/startup, notification, backup, UX, import, income, device-OS → quyết định phase sau **tách** hotfix.

### P9.9 — Backlog only

`doc/release/post_production_backlog.md` và/hoặc `next.md`: OCR, cloud, sharing, widgets, … — **không code**.

### P9.10 — Evidence

Tạo `result_p9_launch.md`:

- version/build, platform status, launch date (NOT RUN nếu chưa submit)
- rollout + monitoring paths
- P0–P3 counts
- Status: **LAUNCH PREP COMPLETE** (không claim **PRODUCTION LIVE** nếu chưa live)

Đồng bộ `checklist.md`, `next.md`.

---

## NEVER

- NEVER feature / OCR / Cloud / AI trong P9
- NEVER claim LIVE / P9 DONE không submit + monitor
- NEVER claim device P7/P8 PASS chỉ vì waive
- NEVER hotfix + unrelated feature
- NEVER “xóa DB” first response
- NEVER thêm analytics SDK lén
- NEVER commit signing secrets

---

## Xong khi (session agent)

- [ ] Mọi file doc P9.1–P9.9 tồn tại trên disk
- [ ] `result_p9_launch.md` honesty PREP vs LIVE
- [ ] checklist/next đồng bộ
- [ ] Không đổi behavior app trừ P0/P1 được chỉ định

**P9 PRODUCTION DONE** = human (store live + monitor + review) theo phase §11.

Bắt đầu từ **P9.1**.
