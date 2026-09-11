# result_p8_release_candidate.md — P8 Release Preparation / Closed Testing Evidence

> Date: 2026-09-11 · Author: Buffy (Codebuff agent) · Phase: **P8 — Release Preparation / Closed Testing**
> Source documents: `.plan/plan_p8.md` + `phases/P8_release_preparation.md`; prerequisite evidence `result_p7_production_verification.md` (rev 2).
>
> **Kết luận trạng thái: P8 PREP COMPLETE (nhóm A) / RELEASE GATES BLOCKED (nhóm B human/device) — KHÔNG sang P9.**

---

## 1. Source revision / version / build

| Item | Value |
|---|---|
| Source revision | `git` metadata unavailable in sandbox (no `.git`); source tree = working directory 2026-09-11 |
| Version (pubspec) | **1.0.0+1** (`x.y.z+build` format — thống nhất) |
| Flutter / Dart | 3.47.2 stable / 3.13.2 |
| Android | applicationId `com.shiftease.shiftease` · versionCode/Name từ pubspec (không hard-code) · label **ShiftEase** (sửa 2026-09-11, trước là `shiftease`) · minSdk/targetSdk = flutter defaults |
| iOS | bundle `com.shiftease.shiftease` · display name **ShiftEase** (sửa 2026-09-11, trước là `Shiftease`) |
| Version table Android ↔ iOS | **1.0.0+1 = 1.0.0+1** (consistent — pubspec là nguồn duy nhất) |

### Release-config audit (P8.2)

| Mục | Kết quả |
|---|---|
| Debug flags / mock services / test endpoints / test seeds trên release path | **Sạch** — grep `lib/` không có `kDebugMode`/mock/localhost/endpoint/seed (match duy nhất là comment guard "refusing to auto-create a fake job") |
| Network trong release | Không HTTP client nào trong pubspec; manifest không `INTERNET` permission |
| Signing secrets trong repo | Không (grep sạch) — keystore khi có sẽ là secret CI/local gitignored |

## 2. Gate table P8.0–P8.11 (PASS | PARTIAL | BLOCKED + evidence)

| ID | Task | Status | Evidence |
|---|---|---|---|
| P8.0 | CI Flutter root | ✅ **PASS on disk — PASS-local; GitHub green run vẫn pending** (gate check đầu tiên theo §0) | **Verify lại theo p8_fix1 (2026-09-11):** reviewer của p8_fix1 nhìn thấy `test.yml` cũ (`source/**` + `dart test`, 978 bytes, không có `build-debug-apk.yml`) — đó là **checkout khác chưa đồng bộ**; disk của working tree này xác nhận: `test.yml` **7286 bytes, 8 jobs Flutter root** (`static-analysis`, `core-time-tests`, `core-pattern-tests`, `core-money-tests`, `import-tests`, `persistence-tests`, `ui-tests`, `full-suite`), grep `source/\|dart test\|setup-dart\|working-directory` chỉ hit comment lịch sử dòng 4; `build-debug-apk.yml` **tồn tại 2558 bytes, 0 hit**. p8_fix1 §1 sau đó xác nhận lại 2 file đúng. Path filters: `lib/**`, `test/**`, `pubspec.yaml`, `pubspec.lock`, `android/**`, `ios/**`, `scripts/**`, `tool/**`, `.github/workflows/**` + `workflow_dispatch`. Persistence job chạy `dart run tool/cipher_proof.dart` (SQLCipher proof). **Chưa green-run trên GitHub** (chưa push) — theo plan §P8.0 chỉ cần file đúng, KHÔNG claim CI green. |
| P8.1 | Feature freeze | ✅ PASS | `doc/release_freeze.md` — frozen: domain model, schema **v3**, import pipeline, pay engine, notification behavior, backup format, encryption (SQLCipher + SecureSecretStore), DST semantics. Intake: chỉ P0/P1/crash/integrity/security/compliance (+P2 release-blocking có phê duyệt). Feature request/OCR/Cloud/AI/sharing → cấm. |
| P8.2 | Version & config | ✅ PASS | §1 ở trên. Đã sửa lệch tìm thấy: app name Android+iOS → **ShiftEase** thống nhất. |
| P8.3 | Android signed release build | ⛔ **BLOCKED — needs signing keys** | `doc/release/build_notes.md` Part 1: lệnh + 9-dòng verify checklist (install/launch/fresh/upgrade/encrypted open/notification/backup/no-debug/signature). Không keystore trong sandbox/repo — không PASS giả. Debug APK artifact từ CI là QA-only. |
| P8.4 | iOS signed archive | ⛔ **BLOCKED — needs certs/profiles + macOS** | `doc/release/build_notes.md` Part 2: 8-dòng verify checklist. Sandbox không có Xcode/signing. |
| P8.5 | Smoke checklist | ✅ PASS (document) / ⛔ device run | `doc/release/smoke_checklist.md` — đủ 19 bước spec (install→…→restore) với expected; **mọi dòng = NOT RUN**, agent không tự điền PASS. |
| P8.6 | Upgrade plan | ✅ PASS (document) / ⛔ device run | `doc/release/upgrade_test_plan.md` — previous RC → candidate, 10 verify hàng (data/overrides/imported/PayRules/settings/encryption/notifications/migration/backup); migration matrix tham chiếu P7.8 (PASS sandbox). |
| P8.7 | Store assets | ✅ PASS (draft) / ⛔ assets thật | `doc/release/store_assets.md` — identity, assets checklist, short/full description + highlights **chỉ nêu feature có thật** (encrypted local DB, review-before-commit import, income preview, DST-safe, backup file, offline; không OCR/cloud/AI/sharing — D-P8.4). Screenshot list từ UI thật. BLOCKED items: icon/screenshots (cần build thật), support contact + policy URL (human). |
| P8.8 | Privacy / policy | ✅ PASS (draft, audit-based) | `doc/release/privacy.md` — audit basis có evidence từng dòng: **không collect** (không network permission + không analytics SDK), encrypted at rest (SQLCipher), key on-device (Keystore/Keychain), permission duy nhất `POST_NOTIFICATIONS`, local notifications, backup/export do user kiểm soát, delete-all in-app + uninstall. Policy draft v1 kèm; pre-submit checklist. Tuyên bố "no data collected" đúng vì app không có khả năng truyền — kèm cảnh báo re-audit nếu thêm dependency. |
| P8.9 | Internal testing protocol | ✅ PASS (document) / ⛔ execution | `doc/release/testing_protocols.md` Part 1: phạm vi 9 khu vực, severity P0–P3 định nghĩa rõ (P0/P1 = stop ship), issue template, luồng fix→rebuild→re-test. Status: NOT RUN (human/device). |
| P8.10 | Closed testing protocol | ✅ PASS (document) / ⛔ execution | Part 2: điều kiện = internal PASS, cohort 5–20, focus feedback đúng 9 mục spec, quy tắc không nhồi feature. Status: NOT RUN. |
| P8.11 | RC freeze + evidence | ⚠️ PARTIAL | Freeze doc + evidence file này đã có; **final freeze cần đợi closed testing ổn định + signed artifacts** (nhóm B). |
| — | `flutter analyze` + `flutter test` | ✅ PASS | **No issues found!** (kể cả `--fatal-infos`) + **315/315 All tests passed!** — re-run 2026-09-11 theo p8_fix1 §2 (4/4 lệnh local exit 0: pub get, analyze --fatal-infos, test, cipher_proof = SQLCipher 4.18.0). Số test ghi trong file này = số thật trên tree chốt. |

## 3. CI workflow — paths & commands (P8.0 evidence)

> Trạng thái trung thực: **on disk = đúng (đã verify)** · **local = 4/4 PASS** · **GitHub Actions = chưa có run nào (đợi push)**. P8.0 chỉ được coi "thật sự xong" theo p8_fix1 §5 khi có ≥1 run xanh trên GitHub.

| File | Nội dung |
|---|---|
| `.github/workflows/test.yml` | on: push [main, develop] + PR [main] + workflow_dispatch · paths: `lib/**`, `test/**`, `pubspec.yaml`, `pubspec.lock`, `android/**`, `ios/**`, `scripts/**`, `.github/workflows/**` · Commands: `flutter pub get` → `flutter analyze --fatal-warnings` → `flutter test test/` (per-engine jobs + full-suite gate) · extra: `node scripts/verify_*.mjs` golden cross-checks, dependency-rule guard, `dart run tool/cipher_proof.dart` (P7.2 SQLCipher proof) |
| `.github/workflows/build-debug-apk.yml` | JDK 17 temurin + Flutter stable → analyze + full suite (không phát APK từ suite đỏ) → `flutter build apk --debug` → artifact `shiftease-debug-apk` (14 ngày) · không keystore secrets |

## 4. Known issues + severity

| ID | Vấn đề | Severity | Trạng thái |
|---|---|---|---|
| KI-1 | CI chưa chạy lần nào trên GitHub (repo chưa push) — workflow đúng trên disk (đã verify byte-size + job list + 4 lệnh local PASS theo p8_fix1 §2; nghi vấn "workflow cũ `source/`" của reviewer = checkout stale, đã xác nhận lại đúng trong p8_fix1 §1) | P2 (release-blocking cho B) | Đợi human push → xem Actions xanh |
| KI-2 | P7 device legs còn mở (xem §5) → signed build trên device chưa thể verify encrypted/notification/lifecycle | P1 (blocker cho P8 B) | Human/device cycle |
| KI-3 | Support contact + privacy policy URL chưa có (thiếu human input) — store submit cần | P2 (submit blocker, không phải app bug) | Human cung cấp |
| KI-4 | App icon/screenshots chưa tạo từ build thật | P3 (trước submit) | Human |

Không có open P0/P1 **code** issue trong RC tree (suite 315/315, review P7.1 closed H1/M1).

## 5. P7 leftovers còn mở (không bị P8 che)

Theo `result_p7_production_verification.md` §5–§6 — tất cả là device legs:

1. P7.2 device: negative test copy-DB → plain SQLite → unreadable; reinstall → recovery screen
2. P7.3/P7.4 device: Keystore/Keychain key persistence qua kill/reboot
3. P7.5/P7.6: notification physical matrix (grant/deny/permanent/edit/delete/restart/reboot) — iOS M2 status
4. P7.7: lifecycle kill/reopen walk
5. P7.9/P7.10 device legs: backup/restore + DST trên hardware
6. P8 B-group phụ thuộc trực tiếp các hàng này

## 6. P8 Acceptance Criteria

### A — Agent (sandbox/config): ✅ COMPLETE (P8.0 = PASS on disk + PASS-local; GitHub run pending)

> Trạng thái đúng theo p8_fix1: **P8 PREP PASS** (sau khi verify lại disk + 4 lệnh local) — khác với "P8 PREP INCOMPLETE" tạm thời của p8_fix1 khi reviewer còn nhìn thấy checkout stale.

- [x] AC-P8.0 CI workflow Flutter root đúng trên đĩa (verify lại theo p8_fix1: 7286 bytes, 8 jobs; "workflow cũ source/" của reviewer = checkout stale — đã xác nhận lại trong chính p8_fix1 §1) — **GitHub green run vẫn pending (đợi push)**
- [x] AC-P8.1 `doc/release_freeze.md`
- [x] AC-P8.2 version/ids/config sạch; bảng version trong result
- [x] AC-P8.5 smoke checklist đầy đủ (NOT RUN honesty)
- [x] AC-P8.6 upgrade plan đầy đủ
- [x] AC-P8.7 store assets structure + copy đúng scope
- [x] AC-P8.8 privacy draft khớp app (audit-based)
- [x] AC-P8.9/10 internal + closed protocols
- [x] AC-P8.11 `result_p8_release_candidate.md` tồn tại, BLOCKED items honesty
- [x] `flutter analyze` (clean) + `flutter test` (315/315) PASS
- [x] `checklist.md` / `next.md` / `.project/state.md` đồng bộ

### B — Human / device: ⛔ NOT RUN (đúng định nghĩa — không agent tự PASS)

- [ ] Signed Android AAB/APK verified on device — BLOCKED (signing keys)
- [ ] Signed iOS verified on device — BLOCKED (certs + macOS)
- [ ] Smoke PASS thật — NOT RUN
- [ ] Upgrade PASS thật — NOT RUN
- [ ] Internal testing PASS — NOT RUN
- [ ] Closed testing PASS — NOT RUN
- [ ] Zero open P0/P1 — chưa thể xác nhận (testing chưa chạy)

## 7. Kết luận: được sang P9 không?

**KHÔNG.** Theo `phases/P8_release_preparation.md` §13: P8 DONE chỉ khi A + B đủ. Nhóm A pass (đã verify lại theo p8_fix1: disk đúng + 4 lệnh local exit 0) nhưng nhóm B chưa chạy — đúng kịch bản §9 của plan: trạng thái = **P8 PREP COMPLETE / RELEASE GATES BLOCKED**. Điểm còn thiếu duy nhất của A: ≥1 CI run xanh trên GitHub (p8_fix1 §5) — làm cùng lúc push.

Đường đóng B (thứ tự):

1. Human push repo lên GitHub → CI green run (đồng thời = chứng cứ P7.2 SQLCipher trên CI)
2. Human tạo keystore/certs (không commit) → signed AAB + iOS archive theo `doc/release/build_notes.md`
3. Cài artifact lên máy thật → chạy `doc/release/smoke_checklist.md` + `doc/release/upgrade_test_plan.md` (điền PASS/FAIL từng dòng)
4. P7 device legs (§5) → internal testing (P8.9) → closed testing (P8.10) → freeze cuối (P8.11)
5. Khi B đủ + zero P0/P1 → P9 mới mở
