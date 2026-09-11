# PROMPT — ShiftEase P8: Release Preparation / Closed Testing

> Đọc và tuân thủ: `.plan/plan_p8.md` + `phases/P8_release_preparation.md`
> Prerequisite evidence: `result_p7_production_verification.md`
> **Không feature mới. Không OCR / Cloud / AI / Sharing / B2B.**

---

## Nhiệm vụ

Implement **P8 prep** đúng `plan_p8.md`. Tách rõ:

- Việc agent **phải làm xong** trong session (CI, freeze, version, checklists, store/privacy drafts, result file)
- Việc **BLOCKED** cần human/device (signed build, smoke thật, closed testing) — ghi BLOCKED, **không** tự PASS

---

## 0. Gate vào P8

1. Nếu `.github/workflows/test.yml` vẫn `working-directory: source` + `dart test` → **sửa P8.0 trước mọi thứ**.
2. Không đánh P7 device gates PASS khi không có evidence.
3. Full suite phải chạy trên Flutter root: `flutter analyze` + `flutter test`.

---

## Task (theo thứ tự)

### P8.0 — CI

- Viết lại `test.yml`: Flutter stable, repo root, `flutter pub get`, `flutter analyze`, `flutter test`
- paths: `lib/**`, `test/**`, `pubspec.yaml`, `android/**`, `ios/**`, workflows
- Optional: workflow upload debug APK artifact (không commit keystore)

### P8.1 — Freeze

- Tạo `doc/release_freeze.md`: schema v3, import/pay/notification/backup/encryption frozen; chỉ nhận P0/P1/crash/integrity/security/compliance

### P8.2 — Version & config

- App name ShiftEase; version `pubspec` thống nhất; applicationId / bundle ID; không debug endpoint / mock / test seed trên release path
- Ghi bảng version vào result

### P8.5 / P8.6 — Checklists

- Smoke flow đủ bước trong `plan_p8.md` §P8.5 (mỗi dòng PASS/FAIL/NOT RUN)
- Upgrade plan: previous RC → candidate (data, overrides, import, PayRules, settings, encryption, notifications)

### P8.7 / P8.8 — Store & privacy

- Description + highlights **chỉ feature có thật**
- Cấm quảng cáo OCR / cloud / AI / family sharing
- Privacy khớp: local DB, encryption (không overclaim), notifications, backup/export, permissions, analytics nếu có

### P8.9 / P8.10 — Protocols

- Internal testing script + severity P0–P3
- Closed testing focus: onboarding, shifts, calendar, import, income, notification, backup, crashes, wording
- P0/P1 → fix + rebuild, không ship

### P8.3 / P8.4 — Release build notes

- Document signed AAB (Android) + iOS archive
- Nếu không có signing: status **BLOCKED**, không PASS

### P8.11 — Evidence

- Tạo `result_p8_release_candidate.md` (bảng gate, CI, known issues, P7 leftover, được sang P9 không)
- Đồng bộ `checklist.md`, `next.md`, handoff nếu cần

---

## NEVER

- NEVER để CI test nhầm project Dart `source/`
- NEVER PASS device/signed/closed không evidence
- NEVER thêm feature / OCR / Cloud / AI
- NEVER quảng cáo store feature chưa ship
- NEVER commit signing secrets
- NEVER tự mở P9 khi DoD P8 chưa đủ (nhóm B human/device)

---

## Xong khi (session agent)

- [ ] CI Flutter root đúng trên đĩa
- [ ] Freeze + version + smoke/upgrade checklists + store/privacy drafts + testing protocols
- [ ] `result_p8_release_candidate.md` honesty về BLOCKED
- [ ] `flutter analyze` + `flutter test` PASS
- [ ] Docs đồng bộ
- [ ] **Không** claim P8 Definition of Done đầy đủ nếu signed/smoke/closed chưa chạy

Bắt đầu từ **P8.0**.
