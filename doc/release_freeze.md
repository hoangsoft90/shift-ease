# Release Freeze — ShiftEase Release Candidate

> P8.1 (`plan_p8.md` §P8.1 / `phases/P8_release_preparation.md` §1).
> Áp dụng từ 2026-09-11 cho release candidate **1.0.0+1** (start date = ngày áp dụng; ghi đè ngày bắt đầu 2026-09-12 sai trước đó).

## 1. Bị đóng băng (frozen) — không thay đổi trong RC

| Hạng mục | Trạng thái frozen | Ghi chú |
|---|---|---|
| Domain model | FROZEN | lib/core model (jobs, patterns, occurrences, overrides, pay rules, import sessions). Không thêm/sửa field trừ P0/P1 integrity. |
| DB schema | FROZEN ở **v3** | `PRAGMA user_version = 3`. Migration matrix P7 giữ nguyên; **cấm destructive migration mới** trừ hotfix P0. |
| Import pipeline | FROZEN | parse → map → validate → review → commit (INVARIANT-004 no auto-commit); re-import diff + income impact (P7.1 M1 semantics: unresolvable → UNAVAILABLE, không silent skip). |
| Pay engine | FROZEN | estimator parity goldens (HOURS_IN_WINDOW, overnight, DST), per-occurrence rules, multi-job total. |
| Notification behavior | FROZEN | E1 stale-cancel (fixed id), E2 RESUME resync, POST_NOTIFICATIONS runtime request (Android 13+). |
| Backup format | FROZEN | JSON schema+version+checksum, mọi bảng, restore transactional rollback. File `shiftease-backup-*.json` trong app-support dir. |
| Encryption approach | FROZEN | **SQLCipher 4.18.0** qua build hook (`source: sqlcipher`, fail-closed, refuse plain keyed open) + `SecureSecretStore` (Keystore/Keychain qua flutter_secure_storage). Không đổi key id / key lifecycle trong RC. |
| DST semantics | FROZEN | Spring gap chặn với lỗi tường minh; fall-back hai candidate → user pick tường minh, offset persist vào override payload (INVARIANT-002 UTC duration). |

## 2. Chỉ nhận vào RC

- **P0/P1 bug**, crash, data integrity, security issue
- **P2 bug có ảnh hưởng release** (release-blocking, phê duyệt từng case)
- **Store compliance issue** (chỉnh sửa metadata/behavior theo yêu cầu store)

## 3. Không nhận vào RC

- Feature request mới (mọi feature → backlog `next.md`, không vào candidate)
- OCR / M4.5 / M5 — deferred (`plan11_ocr_spike.md` là spec gate, chưa duyệt chạy)
- Cloud sync, Webcal dynamic, E2E backup cloud
- Family sharing, Availability Finder nâng cao, Health AI, B2B, payroll tax
- Refactor "đẹp hơn" không gắn bug P0–P2

## 4. Quy trình thay đổi trong freeze

1. Issue vào với severity P0–P3 (template: `doc/release/testing_protocols.md`).
2. P0/P1 → fix + test + **rebuild artifact mới** (bump build number, không đổi version).
3. P2 release-blocking → chủ RC phê duyệt bằng văn bản trong `result_p8_release_candidate.md` (mục Known issues) rồi mới fix.
4. P2/P3 không blocking → backlog sau release.

Mọi thay đổi code trong freeze phải giữ: `flutter analyze` clean + full suite pass + không phá frozen items ở §1.
