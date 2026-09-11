**Review P8 — đối chiếu filesystem thật với `plan_p8.md` / `result_p8_release_candidate.md`**

---

## 1. Verdict

| Hạng mục | Kết luận |
|----------|----------|
| **P8 Definition of Done (A+B)?** | **Không** — đúng như agent ghi: nhóm B BLOCKED |
| **P8 PREP (nhóm A) hoàn tất?** | **Gần đạt, nhưng P8.0 CI FAIL trên disk** — report agent **mâu thuẫn** với file thật |
| **Được sang P9?** | **Không** |
| **Mức tin report agent** | Trung bình — docs P8.1–P8.10 tốt; **claim CI đã đúng là sai** |

---

## 2. Đối chiếu từng gate

| Gate | Agent claim | Filesystem / review | Đánh giá |
|------|-------------|---------------------|----------|
| **P8.0 CI** | PASS — Flutter root, 8 jobs, `build-debug-apk.yml` | `.github/workflows/test.yml` = **978 bytes, vẫn `source/**` + `dart-lang/setup-dart` + `dart test`**. Chỉ có **1** file workflow; **không** có `build-debug-apk.yml` | **FAIL — claim sai** |
| **P8.1 Freeze** | PASS | `doc/release_freeze.md` đầy đủ, schema v3, intake rõ | **PASS** |
| **P8.2 Version** | PASS, tên ShiftEase | `AndroidManifest` `android:label="ShiftEase"`; `pubspec` `1.0.0+1` | **PASS** (config) |
| **P8.3/4 Signed build** | BLOCKED | `doc/release/build_notes.md` có | **PASS honesty** (BLOCKED đúng) |
| **P8.5 Smoke** | doc PASS / device NOT RUN | `smoke_checklist.md` 19 bước, mặc định NOT RUN | **PASS** |
| **P8.6 Upgrade** | tương tự | `upgrade_test_plan.md` | **PASS** |
| **P8.7 Store** | draft | `store_assets.md` | **PASS** (draft) |
| **P8.8 Privacy** | draft | `privacy.md` | **PASS** (draft) |
| **P8.9/10 Protocols** | doc | `testing_protocols.md` | **PASS** |
| **P8.11 Evidence** | PARTIAL | `result_p8_release_candidate.md` có; kết luận không sang P9 | **PARTIAL** — tốt về B, **hỏng vì overclaim P8.0** |
| **Analyze/test 315/315** | PASS | Không chạy lại trong session review này; có `tool/cipher_proof.dart` | **Chưa tự verify** — tạm tin có điều kiện |

---

## 3. Lỗi nghiêm trọng: P8.0 evidence giả

`result_p8` viết:

> `test.yml` đã đúng… không còn `working-directory: source`…  
> `build-debug-apk.yml` (1 job)…

**Đọc trực tiếp `test.yml` hiện tại:**

```yaml
paths:
  - 'source/**'
defaults:
  run:
    working-directory: source
- uses: dart-lang/setup-dart@v1
- run: dart test
```

- Không Flutter setup  
- Không `lib/**` / `test/**`  
- Thư mục workflows: **chỉ** `test.yml` — không `build-debug-apk.yml`

Đây là **P0 documentation integrity**: AC-P8.0 **chưa đạt**, dù checklist/result đánh PASS.

---

## 4. Phần agent làm đúng

1. **Tách A/B rõ** — không tự PASS smoke/signed/closed/device.  
2. **`doc/release_freeze.md`** — đúng tinh thần freeze RC.  
3. **Bộ `doc/release/`** — smoke, upgrade, store, privacy, protocols, build_notes đủ dùng cho human.  
4. **Privacy/store** — không quảng cáo OCR/Cloud/AI.  
5. **Kết luận không sang P9** — đúng.  
6. **P7 leftovers** vẫn được liệt kê — không che.

---

## 5. P8 PREP vs P8 DONE

| | |
|--|--|
| **P8 PREP (nhóm A)** | **Chưa sạch** vì P8.0 CI chưa sửa trên disk |
| **P8 DONE (A+B)** | **Chưa** — thiếu signed build, smoke/upgrade/internal/closed thật |

Trạng thái đúng nên ghi:

> **P8 PREP INCOMPLETE (P8.0 CI còn sai) / RELEASE GATES BLOCKED**  
> không phải “P8 PREP COMPLETE”.

---

## 6. Hành động tiếp theo

### Ngay (agent hoặc bạn) — bắt buộc

1. **Sửa thật** `.github/workflows/test.yml` → Flutter root:
   - `flutter pub get` / `analyze` / `test`
   - paths: `lib/**`, `test/**`, `pubspec.yaml`, …
2. **Thêm** `build-debug-apk.yml` **chỉ nếu** vẫn muốn artifact (hoặc xóa claim trong result).
3. **Sửa** `result_p8_release_candidate.md` + `checklist.md`:
   - P8.0 = FAIL hoặc PASS sau khi file đúng
   - Bỏ mô tả workflow “8 jobs / build-debug-apk” nếu không tồn tại
4. (Khuyến nghị) Chạy lại `flutter analyze` + `flutter test`, ghi số test thật vào result.

### Human (sau CI đúng)

5. Push → xem CI green  
6. Signed build + điền smoke/upgrade  
7. Internal → closed → rồi mới xét P8 DONE / P9  

### Không làm

- Không sang P9  
- Không tin P8.0 PASS chỉ vì result viết PASS  
- Không thêm feature trong lúc freeze  

---

## 7. Tóm tắt một câu

**Docs P8.1–P8.10 và thái độ BLOCKED cho device là ổn; nhưng P8.0 CI vẫn là workflow Dart/`source/` cũ — agent đã claim PASS sai. P8 prep chưa đạt cho đến khi sửa CI trên disk và chỉnh lại evidence.**
-----------------
Đã ghi 2 workflow đúng Flutter root. Dưới đây là **hướng dẫn sửa còn lại** theo đúng review.

---

## 1. Đã sửa trên disk (P8.0)

| File | Nội dung |
|------|----------|
| `.github/workflows/test.yml` | Flutter root: `flutter pub get` → `analyze` → `test` → `dart run tool/cipher_proof.dart`; paths `lib/**`, `test/**`, …; **không** còn `source/` |
| `.github/workflows/build-debug-apk.yml` | Debug APK artifact sau khi analyze+test xanh; không keystore |

**Bạn nên kiểm tra nhanh:**

```bash
cd /Users/hoang/htdocs_apps/ShiftEase
head -40 .github/workflows/test.yml
ls .github/workflows/
# Kỳ vọng: test.yml + build-debug-apk.yml, không còn working-directory: source
```

Nếu agent ghi đè lại file cũ — so sánh với 2 file vừa ghi.

---

## 2. Chạy local trước khi tin CI

```bash
cd /Users/hoang/htdocs_apps/ShiftEase
flutter pub get
flutter analyze --no-pub --fatal-infos
flutter test test/
dart run tool/cipher_proof.dart
```

- Cả 4 lệnh phải exit 0.
- Ghi **số test thật** (vd. `All tests passed!` dòng cuối) vào `result_p8` — đừng giữ số “315” nếu lệch.

Nếu `cipher_proof.dart` fail: SQLCipher hook trong `pubspec` chưa link đúng trên máy CI/local → xử lý P7.2 trước, không claim encryption trên CI.

---

## 3. Sửa evidence cho khớp disk (bắt buộc)

### 3.1 `result_p8_release_candidate.md`

Sửa các chỗ claim sai:

| Chỗ cũ (sai) | Sửa thành |
|--------------|-----------|
| “test.yml đã đúng từ P7_fix2…” trong khi disk vẫn `source/` | Ghi: **P8.0 fixed 2026-09-11 (review)**: workflow Flutter root + `build-debug-apk.yml` có trên disk |
| “8 jobs…” | Mô tả **đúng file hiện tại**: job `analyze-and-test` + job `golden-scripts` (và job debug APK riêng file) |
| P8.0 = PASS trong khi trước đó file sai | P8.0 = **PASS sau khi verify file** (hoặc PASS-local / BLOCKED-CI-green nếu chưa push) |

Thêm mục Known issues cập nhật:

- ~~KI-1 workflow sai source~~ → **đã sửa file**; còn lại: **chưa green run trên GitHub** (đợi push).

### 3.2 `checklist.md` / `next.md`

- P8.0: không ghi PASS CI green cho đến khi push thấy Actions xanh.
- Có thể ghi: `CI workflow on disk: Flutter root ✅ · GitHub run: chưa / PASS (link)`.

### 3.3 Không cần sửa lại

- `doc/release_freeze.md`
- `doc/release/smoke_checklist.md`, `upgrade_test_plan.md`, `privacy.md`, `store_assets.md`, `testing_protocols.md`, `build_notes.md`  
→ đã ổn về hướng prep; chỉ điền PASS/FAIL khi **người** chạy device.

---

## 4. Thứ tự việc tiếp theo (không cần device ngay)

```text
1. Xác nhận 2 workflow trên disk (bước 1)
2. Chạy 4 lệnh local (bước 2) — sửa code nếu đỏ
3. Patch result_p8 + checklist/next (bước 3)
4. git add .github/workflows/ … → push
5. Mở GitHub Actions: Test + (optional) Build debug APK phải xanh
6. Tải APK artifact → lúc đó mới bắt đầu smoke trên máy (nhóm B)
```

---

## 5. Khi nào coi P8.0 / P8 prep thật sự xong

| Tiêu chí | OK khi |
|----------|--------|
| File CI | Không còn `source/`, `dart test` cho app |
| Local | analyze + test + cipher_proof PASS |
| Evidence | result_p8 mô tả **đúng** workflow hiện có |
| CI GitHub | Ít nhất 1 run xanh trên commit có workflow mới |
| P8 DONE đầy đủ | Vẫn cần signed build + smoke/upgrade/internal/closed (human) |

---

## 6. Việc **không** làm

- Không mở P9.
- Không đánh “P8 PREP COMPLETE” nếu local test đỏ hoặc workflow lại bị agent ghi đè về `source/`.
- Không commit keystore / mật khẩu signing.
- Không điền PASS vào `smoke_checklist.md` khi chưa chạy máy.

---

**Tóm lại:** CI đã được viết lại đúng Flutter root; bạn chỉ cần **verify local → sửa docs cho khớp → push → xem Actions xanh**, rồi mới sang nhánh device/signed của P8. Nếu muốn, tôi có thể viết luôn đoạn patch cụ thể cho mục P8.0 trong `result_p8_release_candidate.md`.