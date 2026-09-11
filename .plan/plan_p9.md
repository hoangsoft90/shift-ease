# plan_p9.md — ShiftEase P9: Production Launch / Post-release Monitoring

> **Trạng thái:** CHỐT spec — agent làm **launch prep / ops docs**; human làm submit + monitor thật.
> **Spec gốc:** `phases/P9_production_launch.md`
> **Prerequisite (user 2026-09-11):** P8 PREP (nhóm A) xong; device/signed/closed **waive hoặc human tự chịu** — agent không claim P7/P8 device PASS không evidence.
> **Báo cáo:** `result_p9_launch.md`
> **NGHIÊM CẤM:** OCR, Cloud, AI, Sharing, B2B, tax, feature mới trong P9.

---

## 0. Mục tiêu

P9 là phase **phát hành thật và kiểm soát rủi ro sau phát hành**, không phải phát triển feature.

Ưu tiên sự cố:

1. Data integrity
2. Crash-free operation
3. Correct time calculation
4. Correct income calculation
5. Notification reliability
6. Backup/restore
7. User-facing UX bugs

---

## 1. Điều kiện vào P9 (honesty)

Ghi rõ trong `result_p9_launch.md`:

| Phase | Status được phép ghi |
|-------|----------------------|
| P0–P6 | DONE |
| P7 | CODE READY; device legs = BLOCKED hoặc **waived by user** |
| P8 | PREP COMPLETE (nhóm A); signed/smoke/closed = BLOCKED hoặc **waived by user** |
| Open P0/P1 trên RC tree | Không được có; nếu có → dừng submit |

Agent **không**:

- Claim “P8 PASS đầy đủ” / “P7 device PASS” khi chỉ có waiver
- Claim “production live” / “P9 DONE” khi chưa submit + monitor thật

---

## 2. In / Out scope

### In scope

| ID | Task |
|----|------|
| P9.1 | Final release gate checklist |
| P9.2 | Production submission record template |
| P9.3 | Staged launch plan |
| P9.4 | Monitoring runbook |
| P9.5 | Feedback triage template |
| P9.6 | P0/P1 hotfix procedure |
| P9.7 | Data-loss incident procedure |
| P9.8 | First production review template |
| P9.9 | Post-production feature backlog (list only) |
| P9.10 | `result_p9_launch.md` + sync checklist/next |

### Out of scope

- OCR, cloud sync, accounts, sharing, widgets, wellness, AI, B2B
- Thêm analytics/crash SDK **trừ khi user duyệt riêng** (privacy re-audit)
- Feature work trong hotfix
- Tự upload store / tự ký artifact nếu không có credential

---

## 3. Task chi tiết

### P9.1 — Final release gate

**File:** `doc/release/final_release_gate.md`

- Bảng P0–P8 status (honest PREP vs DONE vs waived)
- Cấm ship nếu còn known: data-loss path, migration-loss, major time/income error, encryption failure
- Xác nhận freeze (`doc/release_freeze.md`) còn hiệu lực
- Version/build từ `pubspec.yaml`

### P9.2 — Production submission pack

**File:** `doc/release/submission_record.md` (template điền)

Ghi nhận:

- source revision (git SHA khi có)
- version + build number
- artifact (AAB/IPA) + checksum nếu có
- submission date, platform, store track

Quy tắc: submit **đúng** artifact đã validate; không rebuild lén với diff không document.

Tham chiếu `doc/release/build_notes.md` cho lệnh build; signing = human/CI secrets.

### P9.3 — Staged launch

**File:** `doc/release/staged_launch.md`

```text
small production exposure → monitor → increase exposure → full release
```

- Không gắn launch với feature change
- Tiêu chí tăng rollout
- Tiêu chí halt/rollback

### P9.4 — Monitoring

**File:** `doc/release/monitoring.md`

Theo dõi tối thiểu:

| Nhóm | Tín hiệu |
|------|----------|
| Stability | crash, startup fail, fatal, DB open fail |
| Data | migration/restore/backup fail, corruption, missing shifts |
| Time | DST, timezone, overnight duration |
| Income | sai số, UNAVAILABLE spam, PayRule version |
| Notification | permission, stale, duplicate, missing |

**Honesty:** app local-only, không analytics SDK trong RC → monitoring = store console + user support + thủ công; không bịa “đã có dashboard analytics”.

### P9.5 — Triage

**File:** `doc/release/triage.md` (hoặc section trong monitoring)

Mỗi issue:

- severity P0–P3
- repro, platform, version/build, feature
- data-loss risk, workaround, owner, status

Priority: P0 emergency → P1 urgent → P2 scheduled → P3 backlog.

### P9.6 — Hotfix procedure

```text
Detect → evidence → reproduce → root cause → minimal fix
→ regression test → release build → emergency release → monitor
```

Hotfix **không** kèm feature không liên quan.

### P9.7 — Data-loss incident

1. Stop unrelated releases
2. Reproduce on a **copy** of data
3. Identify affected versions + path (migration/restore/write)
4. Preserve evidence
5. Regression test
6. Minimal fix + verify backup/restore
7. Hotfix + incident document

**NEVER** first response = “xóa database”.

### P9.8 — First production review

Template sau cửa sổ ổn định (human chọn, gợi ý 7–14 ngày):

- crash-free / startup
- notification / backup-restore health
- top UX complaints
- import / income / device-OS issues
- Quyết định phase tiếp **tách** khỏi hotfix stream

### P9.9 — Post-production backlog

**File:** `doc/release/post_production_backlog.md` và/hoặc cập nhật `next.md`

Chỉ liệt kê, **không code** trong P9:

- OCR roster import
- Cloud sync / account
- Sharing / partner overlay
- Widgets
- Shift change detection / wellness
- Advanced AI / B2B payroll

Không phải release blocker P9.

### P9.10 — Evidence

**File:** `result_p9_launch.md`

- production version/build
- platform release status (NOT RUN nếu chưa submit)
- launch date, rollout strategy
- monitoring setup (paths doc)
- issue counts P0–P3
- hotfixes
- status: **LAUNCH PREP COMPLETE** vs **PRODUCTION LIVE**

Sync: `checklist.md`, `next.md`.

---

## 4. Quyết định khóa

| ID | Quyết định |
|----|------------|
| D-P9.1 | P9 = ops/launch, không feature |
| D-P9.2 | Honesty: waived device ≠ PASS evidence |
| D-P9.3 | Submit đúng artifact freeze; không rebuild lén |
| D-P9.4 | Hotfix minimal; không nhét feature |
| D-P9.5 | Data-loss: không bảo user xóa DB đầu tiên |
| D-P9.6 | Không thêm analytics SDK lén |

---

## 5. NEVER list

- NEVER OCR/Cloud/AI/Sharing/B2B trong P9
- NEVER claim production live / P9 DONE không submit + monitor
- NEVER claim P7/P8 device PASS chỉ vì waive
- NEVER hotfix + feature unrelated
- NEVER “xóa DB” là first response data-loss
- NEVER commit signing secrets

---

## 6. Acceptance Criteria

### A — Agent (docs/ops prep)

- [ ] AC-P9.1 `doc/release/final_release_gate.md`
- [ ] AC-P9.2 `doc/release/submission_record.md`
- [ ] AC-P9.3 `doc/release/staged_launch.md`
- [ ] AC-P9.4 `doc/release/monitoring.md` (+ triage)
- [ ] AC-P9.6/7 hotfix + data-loss procedures documented
- [ ] AC-P9.8 first production review template
- [ ] AC-P9.9 post-production backlog tách riêng
- [ ] AC-P9.10 `result_p9_launch.md` honesty PREP vs LIVE
- [ ] checklist.md / next.md đồng bộ
- [ ] Không đổi app behavior trừ P0/P1 được chỉ định rõ

### B — Human / store

- [ ] Signed artifact submitted
- [ ] Staged or full production live
- [ ] Monitoring observed in practice
- [ ] No unresolved P0/P1
- [ ] First production review completed

**P9 DONE** chỉ khi `phases/P9_production_launch.md` §11 đủ (live + monitor + ổn định).

---

## 7. Thứ tự triển khai agent

```text
1. P9.1 final_release_gate.md
2. P9.2 submission_record.md
3. P9.3 staged_launch.md
4. P9.4 monitoring.md + P9.5 triage
5. P9.6 hotfix + P9.7 data-loss procedures
6. P9.8 review template + P9.9 backlog
7. result_p9_launch.md + checklist/next
```

---

## 8. Định nghĩa xong

| Trạng thái | Khi nào |
|------------|--------|
| **P9 LAUNCH PREP COMPLETE** | Nhóm A đủ; result file không claim LIVE giả |
| **P9 PRODUCTION / DONE** | Nhóm B đủ theo phase §11 |

Sang “product feature phase” (OCR, cloud, …) chỉ sau production ổn định + review — không trộn hotfix.
