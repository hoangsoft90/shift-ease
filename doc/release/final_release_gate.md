# P9.1 — Final Release Gate (ShiftEase RC)

> Nguồn: `phases/P9_production_launch.md` §1 · `plan_p9.md` §P9.1.
> Quy tắc trung thực: gate ghi **PASS / FAIL / NOT RUN / WAIVED** — **waived ≠ PASS**. Waiver device/signed/closed do user phát hành (directive trong `prompt_p9.md`, 2026-09-11) cho mục đích LAUNCH PREP; rủi ro tương ứng được ghi nhận, không bị xóa.

## 1. Trạng thái phase P0–P8

| Phase | Status | Evidence |
|---|---|---|
| P0–P6 | ✅ DONE | suite + review lịch sử (`result16_rc.txt`, `result17`, `result18`) |
| P7.1 (H1 backup dir, M1 income impact) | ✅ PASS | `result_p7_production_verification.md` §2 |
| P7.2 SQLCipher | ✅ CODE READY (sandbox) · ⛔ device leg | SQLCipher 4.18.0 thật, fail-closed, 17 gate tests trên file mã hoá, `tool/cipher_proof.dart`; device negative test (copy-DB→plain) = BLOCKED → **WAIVED by user** |
| P7.3/P7.4 SecretStore | ✅ CODE READY · ⛔ device | production impl + 6 error-path tests; key persistence qua kill/reboot = BLOCKED → **WAIVED by user** |
| P7.5–P7.7 (notification device matrix, lifecycle walk) | ⛔ NOT RUN → **WAIVED by user** | logic + unit tests (E1/E2) PASS trong sandbox |
| P8.0 CI | ✅ on disk + PASS-local (4/4 lệnh) · ⏳ GitHub green run pending | `result_p8_release_candidate.md` §3; **run xanh trên GitHub là điều kiện bắt buộc TRƯỚC submission thật** |
| P8.1 freeze + P8.2 version/config | ✅ PASS | `doc/release_freeze.md`; 1.0.0+1; ShiftEase label thống nhất |
| P8.3/P8.4 signed builds | ⛔ BLOCKED (needs keys) → **WAIVED for prep; bắt buộc trước submit thật** | `doc/release/build_notes.md` |
| P8.5/P8.6 smoke/upgrade | ✅ docs · ⛔ device run → **WAIVED by user** | `doc/release/smoke_checklist.md`, `doc/release/upgrade_test_plan.md` |
| P8.7/P8.8 store/privacy | ✅ DRAFT (đúng behavior; thiếu support email + policy URL host) | `doc/release/store_assets.md`, `doc/release/privacy.md` |
| P8.9/P8.10 internal/closed testing | ⛔ NOT RUN → **WAIVED by user** | `doc/release/testing_protocols.md` |
| Open P0/P1 trên RC tree | ✅ **0** | suite **315/315**, analyze clean; H1/M1 closed (P7.1); code review `result19_code_review_p8.txt` = APPROVE |

## 2. Ship-blocker check (CẤM ship nếu còn bất kỳ mục nào dưới đây)

| Hạng mục | Known issue? |
|---|---|
| Data-loss path | **Không known** — overrides append-only, restore transactional rollback, corrupted-backup rejection (tests) |
| Migration-loss path | **Không known** — v1→v3 plain + encrypted PASS; fail-before/restart rollback tests (RC A7) |
| Major time-calculation error | **Không known** — INVARIANT-002 UTC duration, DST goldens, adversarial suite |
| Major income-calculation error | **Không known** — estimator parity goldens; unresolvable row → UNAVAILABLE (P7.1 M1), không số một phần |
| Encryption failure | **Không known trong code** — fail-closed opener, refuse plain keyed open, cipher proof; device verification WAIVED — rủi ro còn lại đã ghi nhận, không được tuyên bố "đã verify trên device" |

## 3. Freeze + version

- Freeze còn hiệu lực: `doc/release_freeze.md` (áp dụng từ 2026-09-11) — chỉ nhận P0/P1/crash/integrity/security/compliance
- Version/build từ `pubspec.yaml` (nguồn duy nhất): **1.0.0+1**

## 4. Kết luận gate

- **LAUNCH PREP: GATE OPEN.**
- **Submission thật chỉ khi:** (1) CI green ≥1 run trên GitHub, (2) signed artifact tồn tại + được ghi trong `doc/release/submission_record.md`, (3) policy URL + support email có thật, (4) khuyến nghị mạnh: smoke device chạy dù đã waiver.
- Waiver ở §1 là quyết định rủi ro của user — không biến các hàng BLOCKED thành PASS.
