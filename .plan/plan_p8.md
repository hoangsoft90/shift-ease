# plan_p8.md — ShiftEase P8: Release Preparation / Closed Testing

> **Trạng thái:** CHỐT spec — sẵn sàng cho agent (phần code/docs) + human (signed build / device / closed testing).
> **Spec gốc:** `phases/P8_release_preparation.md`
> **Prerequisite:** `phases/P7_production_verification.md` + `result_p7_production_verification.md`
> **Báo cáo bắt buộc:** `result_p8_release_candidate.md`
> **NGHIÊM CẤM:** OCR, Cloud, AI, Sharing, B2B, tax/net-pay, feature mới.

---

## 0. Điều kiện vào P8

Theo `phases/P8_release_preparation.md` §0 và §13: **P8 chỉ bắt đầu sau khi P7 PASS.**

Thực tế hiện tại (review 2026-09-11):

| Điều kiện | Kỳ vọng vào P8 |
|-----------|----------------|
| P7.1 H1/M1 fixed + tested | PASS |
| SQLCipher + SecureSecretStore **code** (fail-closed) | CODE READY tối thiểu |
| Full `flutter analyze` + `flutter test` | PASS trên source root |
| CI trỏ đúng Flutter root (không `source/` + `dart test`) | **Bắt buộc sửa trước hoặc trong P8.0** |
| Device gates P7 (notification matrix, lifecycle, SQLCipher negative trên máy thật) | Không tự PASS; ghi BLOCKED hoặc human waiver |

**Quy tắc honesty:**

- Agent **không** đánh P7 device gates = PASS khi không có evidence.
- Agent **không** đánh P8 signed-build / internal / closed testing = PASS khi chưa chạy thật.
- Session agent có thể hoàn thành **P8 prep (code + docs + CI)**; **P8 Definition of Done đầy đủ** cần human/device.

Nếu CI vẫn target `working-directory: source` + `dart-lang/setup-dart` → coi là **P7 leftover / P8.0 blocker**; sửa trước các task release khác.

---

## 1. Mục tiêu P8

- Freeze scope release candidate
- Version / build / release configuration sạch
- CI đúng Flutter project + (khuyến nghị) artifact debug/release pipeline
- Checklist smoke + upgrade
- Store metadata / privacy **đúng behavior thật**
- Protocol internal + closed testing
- Evidence file `result_p8_release_candidate.md`
- **Không** thêm feature lớn

---

## 2. Phạm vi — In / Out

### In scope

| ID | Task |
|----|------|
| P8.0 | CI Flutter root + optional debug APK workflow |
| P8.1 | Feature freeze document |
| P8.2 | Version, applicationId, bundle ID, release flags |
| P8.3 | Android release build notes / config (signed AAB — human/CI execute) |
| P8.4 | iOS release build notes / config (archive — human/CI execute) |
| P8.5 | Release smoke checklist (và script nếu hữu ích) |
| P8.6 | Upgrade test plan (previous RC → candidate) |
| P8.7 | Store assets structure + copy (no deferred features) |
| P8.8 | Privacy / policy disclosures khớp app thật |
| P8.9 | Internal testing protocol + severity template |
| P8.10 | Closed testing protocol |
| P8.11 | RC freeze checklist + final result file |

### Out of scope

- OCR / M4.5 / M5
- Cloud sync, Webcal dynamic, E2E backup cloud
- Family sharing, Availability Finder nâng cao
- Health AI, B2B, payroll tax
- Schema/domain feature mới
- Tự claim device PASS / closed testing PASS không evidence

---

## 3. Task chi tiết

### P8.0 — CI & pipeline (làm trước)

**Hiện trạng đã xác nhận:** `.github/workflows/test.yml` còn:

- `working-directory: source`
- `dart-lang/setup-dart`
- `dart test`
- paths: `source/**`

App thật là Flutter ở **repo root** (`lib/`, `pubspec.yaml`, `android/`, `ios/`).

**Yêu cầu:**

```yaml
# test.yml — ý tưởng bắt buộc
on:
  push / pull_request:
    paths:
      - 'lib/**'
      - 'test/**'
      - 'pubspec.yaml'
      - 'pubspec.lock'
      - 'android/**'
      - 'ios/**'
      - '.github/workflows/**'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - checkout
      - setup Flutter stable
      - flutter pub get
      - flutter analyze
      - flutter test
```

**Khuyến nghị:** workflow/job `build-debug-apk` upload artifact (không commit keystore).

**NEVER:** secrets signing trong repo public; claim CI green nếu chưa push được — chỉ cần file workflow đúng.

---

### P8.1 — Feature freeze

Tạo `doc/release_freeze.md` (hoặc section tương đương) ghi:

- Domain model frozen
- DB schema frozen (hiện **v3**)
- Import pipeline frozen
- Pay engine frozen
- Notification behavior frozen
- Backup format frozen
- Encryption approach frozen (SQLCipher + SecureSecretStore seam)

Chỉ nhận vào RC: P0/P1 bug, crash, data integrity, security, store compliance.

Không nhận feature request mới vào candidate này.

---

### P8.2 — Version / build configuration

Verify và sửa nếu lệch:

| Mục | Kỳ vọng |
|-----|--------|
| App name | ShiftEase |
| `pubspec.yaml` version | `x.y.z+build` thống nhất |
| Android applicationId | production id ổn định |
| iOS bundle identifier | production id ổn định |
| Release mode | không debug flags / test endpoints / mock services |
| Test data | không seed trên production path |

Ghi bảng version Android ↔ iOS vào `result_p8_release_candidate.md`.

---

### P8.3 — Android release build

- Preferred artifact: **AAB**; APK cho QA trực tiếp nếu cần
- Agent: document bước signed build + checklist install/launch/fresh/upgrade/DB/notification/backup
- Execute signed build: **CI có signing hoặc human**
- Status nếu không có keystore: `BLOCKED — needs signing keys`
- **NEVER** PASS “Android signed release” chỉ vì debug build local

Checklist verify (khi build chạy được):

- install, launch, fresh install, upgrade from RC
- database opens; encrypted path opens nếu build SQLCipher
- notification permission flow
- backup/restore
- no debug UI / no debug logging

---

### P8.4 — iOS release build

Tương tự Android: archive signed, Keychain, notification, backup/restore, no dev config.

BLOCKED nếu không có cert/profile — ghi rõ, không PASS giả.

---

### P8.5 — Release smoke test

Checklist bắt buộc (mỗi dòng: PASS / FAIL / NOT RUN):

```text
Install
→ launch
→ create job
→ create shift
→ create overnight shift
→ create recurring pattern
→ edit occurrence
→ delete occurrence
→ import roster
→ review
→ commit
→ CSV re-import
→ review diff
→ calculate income
→ switch jobs
→ enable notification
→ restart
→ backup
→ restore
```

Expected: no crash, no data loss, duration đúng, income đúng, no stale notification.

Agent có thể thêm script hỗ trợ; kết quả device = human.

---

### P8.6 — Upgrade test

Plan tối thiểu:

```text
previous RC → release candidate
```

Verify: data, overrides, imported roster, PayRules, settings, encryption still opens DB, notifications valid.

Schema migration: bám matrix P7; không destructive migration mới trong P8 trừ hotfix P0.

---

### P8.7 — Store assets

Chuẩn bị structure + copy:

- App icon requirements
- Screenshots từ UI thật: Today, Week/Month, Import, Income, Settings
- Short description + full description
- Feature highlights
- Support contact
- Category + content rating notes

**Cấm quảng cáo** nếu chưa ship:

- OCR
- Cloud sync
- AI
- Family sharing

---

### P8.8 — Privacy / policy

Disclosures khớp behavior thật:

- Local database
- Encryption (đúng mức đã verify — không overclaim)
- Notifications
- Backup / export / ICS
- Analytics/crash reporting (có thì nói; không thì nói không)
- Permissions

Không claim “no data collected” nếu sai với cấu hình release cuối.

---

### P8.9 — Internal testing

Protocol:

- Distribute RC nội bộ
- Chạy smoke + upgrade + DST + import + income + multi-job + offline
- Mỗi issue: severity **P0 / P1 / P2 / P3**
- P0/P1 → fix + rebuild trước khi tiếp

Template issue trong `doc/` hoặc trong result file.

---

### P8.10 — Closed testing

Sau internal PASS:

```text
Internal PASS → closed cohort nhỏ → feedback → chỉ fix P0/P1 (và P2 release-blocking)
```

Focus feedback: onboarding, add shifts, calendar, import, income clarity, notification, backup confidence, crashes, wording.

Không dùng closed testing để nhồi feature.

---

### P8.11 — Release candidate freeze

Khi ổn định:

- Freeze code + record source revision
- Final analyze/test report
- Android + iOS release artifacts (khi có)
- Store metadata + privacy + screenshots + version numbers verified

---

## 4. Quyết định khóa

| ID | Quyết định |
|----|------------|
| D-P8.1 | Không feature mới trong RC; chỉ bug/security/compliance |
| D-P8.2 | CI phải test Flutter root trước khi claim P8 progress |
| D-P8.3 | Device/signed/closed PASS chỉ với evidence thật |
| D-P8.4 | Store copy không quảng cáo OCR/Cloud/AI/sharing chưa ship |
| D-P8.5 | Privacy đúng behavior; không overclaim encryption |
| D-P8.6 | P0/P1 từ testing → stop ship, fix, rebuild |

---

## 5. NEVER list

- NEVER bắt đầu task store/smoke “PASS” khi CI vẫn test nhầm `source/`
- NEVER đánh P7/P8 device gates PASS không evidence
- NEVER thêm OCR/Cloud/AI/Sharing trong P8
- NEVER quảng cáo store feature chưa có
- NEVER commit keystore / cert password vào git
- NEVER silent unkeyed open trên SQLCipher build
- NEVER tự chuyển P9 khi P8 DoD §13 chưa đủ

---

## 6. Acceptance Criteria

### A — Agent có thể PASS (sandbox / config)

- [ ] AC-P8.0 CI workflow Flutter root đúng trên đĩa
- [ ] AC-P8.1 `doc/release_freeze.md` (hoặc tương đương) tồn tại
- [ ] AC-P8.2 version/ids/config sạch; bảng version trong result
- [ ] AC-P8.5 smoke checklist đầy đủ
- [ ] AC-P8.6 upgrade plan đầy đủ
- [ ] AC-P8.7 store assets structure + copy đúng scope
- [ ] AC-P8.8 privacy draft khớp app
- [ ] AC-P8.9/10 internal + closed protocols
- [ ] AC-P8.11 `result_p8_release_candidate.md` tồn tại, honesty BLOCKED items
- [ ] `flutter analyze` + `flutter test` PASS
- [ ] `checklist.md` / `next.md` đồng bộ

### B — Human / device (không agent tự PASS)

- [ ] Signed Android AAB/APK verified on device
- [ ] Signed iOS verified on device
- [ ] Smoke PASS thật
- [ ] Upgrade PASS thật
- [ ] Internal testing PASS
- [ ] Closed testing PASS
- [ ] Zero open P0/P1

**P8 DONE** chỉ khi A + B đủ (`phases/P8_release_preparation.md` §13).

---

## 7. Thứ tự triển khai agent

```text
1. P8.0 CI Flutter root (+ optional debug APK workflow)
2. flutter analyze + flutter test
3. P8.1 freeze doc
4. P8.2 version/config
5. P8.5 smoke checklist + P8.6 upgrade plan
6. P8.7 store drafts + P8.8 privacy
7. P8.9 / P8.10 testing protocols
8. P8.3 / P8.4 release build notes (BLOCKED nếu thiếu signing)
9. result_p8_release_candidate.md + sync checklist/next/handoff
```

---

## 8. Báo cáo `result_p8_release_candidate.md`

Bắt buộc có:

1. Source revision / version / build numbers
2. Bảng P8.0–P8.11: PASS | PARTIAL | BLOCKED + evidence
3. CI workflow paths + commands
4. Known issues + severity
5. P7 leftovers còn mở
6. Kết luận: được sang P9 hay **không** (mặc định không nếu B chưa đủ)

---

## 9. Sau P8

Chỉ khi P8 DoD đầy đủ → `phases/P9_production_launch.md`.

Nếu chỉ xong nhóm A (prep): trạng thái = **P8 PREP COMPLETE / RELEASE GATES BLOCKED** — không P9.
