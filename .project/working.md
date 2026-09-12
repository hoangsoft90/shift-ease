# Working Memory — ShiftEase

> Auto-updated tracking file. Last updated: **2026-09-12**
> Trạng thái project chi tiết: `.project/state.md`. Session entry: `.project/openspec_entry.md`.
> Phiên này: **release packaging (4 workflow GH Actions) + fix 2 crash P0 chỉ hiện ở release, verify trên máy thật.**

## Session State (2026-09-12)

### Bối cảnh

User báo "release APK cài được vào phone, nhưng mở lên bị crash" → dùng **adb với máy thật**
(Pixel 3a / Android 12 / arm64-v8a) để debug thay vì đoán từ code. Truy ra **2 bug độc lập**,
cả hai đều **invisible ở debug build**:

1. `MobileAdsInitProvider: IllegalStateException: * Invalid application ID. *` — do `-PenableAds=false`
   ghi `APPLICATION_ID=""` (fix `8755ec1`).
2. `Failed to create an instance of androidx.work.impl.WorkDatabase` — R8 xoá constructor rỗng mà
   Room gọi bằng reflection (fix `a1d9b0c`).

Cuối phiên user xác nhận **"đã hết lỗi"** và yêu cầu rút bài học thành skill.

### Verification (bằng chứng chạy lại trên đĩa 2026-09-12 — không tin số cũ)

- `flutter analyze --no-pub --fatal-infos` → **No issues found!** (15.4s)
- `flutter test test/` → **343/343 All tests passed!** (exit=0, 2m03s)
  - `test/config` 12 · `test/core` 247 · `test/domain` 28 · `test/features` 16 · `test/ui` 40
- **CI @ `a1d9b0c` — 5/5 run xanh**: ShiftEase CI · Build Debug APK · Build release APK (push `34672504259` + dispatch split `34672509479`) · Build release AAB (`34672504297`)
- Guard CI **thật** (không pass rỗng): `R8 removed-code report: build/app/outputs/mapping/release/usage.txt` → `OK: androidx.work.impl.WorkDatabase_Impl kept its no-arg constructor (3 other member(s) removed)`
- **Máy thật sau khi cài APK release từ CI**: `pidof`=665 · `ResumedActivity` = `.MainActivity` · `mHasSurface=true isReadyForDisplay()=true` · crash buffer **rỗng** · `grep -c "E/flutter\|FATAL"` = **0** · ads SDK init (`Ads: ... setTestDeviceIds("CE6FF61F67B050F7AA6FC92007DB4284")`)
- Git: `main` @ `a1d9b0c` (log phiên: `9a98489`→`da0afaf`→`e48da3e`→`cb96d85`→`1f6e2f6`→`8755ec1`→`2dc2cdd`→`a1d9b0c`), working tree sạch (chỉ `store_assets/guide.html` untracked)

### Đã làm trong phiên này

- [x] Debug bằng adb trên máy thật thay vì suy luận: `logcat -b crash` → stack thật
- [x] Fix crash #1: `adsAppId` thành hằng số luôn hợp lệ; tắt ads chỉ còn ở Dart (`ENABLE_ADS`)
- [x] Fix crash #2: `android/app/proguard-rules.pro` + `proguardFiles(...)`; **không** tắt minify
- [x] Guard CI: `tool/check_manifest_ads.py` (parse giá trị attribute) + `tool/check_r8_keep.py` (usage.txt)
- [x] Workflow: release APK (có `split_per_abi`), release AAB ký keystore cố định từ GitHub secrets
- [x] Sửa guidance **sai** trong `doc/release/build_notes.md` §1.5 (đang mô tả cách blank app id)
- [x] Gh-pages chỉ còn 3 file public (index/guide/privacy) — trước đó mirror source
- [x] `chplay.md` + `store_assets/` (icon 512, feature graphic 1024×500, privacy, user guide)
- [x] Skill: generic `android-release-only-crash` (global, validator PASS) + cập nhật `shiftease-ci-apk`
- [x] Verify lại toàn bộ trên máy thật + CI trước khi ghi docs (analyze 343/343)

### Trạng thái release (đã khoá bằng bằng chứng)

| Hạng mục | Trạng thái |
|---|---|
| Release APK | ✅ build + ký + cài + cold-start OK trên máy thật |
| Release AAB | ✅ build + verify `CN=ShiftEase` (Play sẽ không từ chối "debug-signed") |
| Debug APK | ✅ build + assert manifest **có** app id production |
| CI test | ✅ 343/343 |
| Play submission | ⏸ chưa — human điền form theo `chplay.md` rồi upload AAB |
| iOS | ⏸ chưa — cần macOS + certs |

## Pending Decisions / Cần hỏi user

1. **Upload Play Console** bây giờ (bump `versionCode` → AAB) hay chạy **device matrix 15 dòng** trước?
2. **AdMob**: thêm máy thật vào test device rồi test ads thật, hay giữ `test_ads=true` đến khi submit?
3. Đưa skill global `android-release-only-crash` vào `.agents/skills/` của repo (đi kèm code) hay giữ global?

## Pending Work

**Immediate:**
- [ ] Play Console: Data Safety + content rating → bump versionCode → upload AAB ký release
- [ ] Chạy hết 15-row device matrix trong `doc/mobile_readiness.md` (giờ đã có release APK + adb → blocker giảm mạnh)
- [ ] Sync `next.md` / `next1.md` theo phiên này

**Later:**
- [ ] iOS build/archive (P8.4) — cần macOS + certs
- [ ] AdMob test device + theo dõi doanh thu ads sau khi publish
- [ ] Deferred §14: OCR/M4.5 spike (cần 20–30 roster thật) · Cloud · Sharing

## Known Issues / Notes

- **Kỷ luật quan trọng nhất phiên này: build xanh KHÔNG phải đã verify.** Cả 2 crash đều đi qua
  build + test + CI xanh nhiều lần; chỉ lộ khi cài artifact release lên máy thật.
- **Không bao giờ** blank `APPLICATION_ID` để "tắt ads", và **không bao giờ** `isMinifyEnabled=false`
  để "cho build qua" — hai bẫy đã gây đúng 2 crash P0.
- Verify artifact bằng **parse giá trị thật**, không `strings | grep` (APK manifest là string pool UTF-16).
- Không build APK local (không có toolchain) — build ở CI; nhưng **`adb` có sẵn và là công cụ verify**.
- Test device AdMob của Pixel 3a: `CE6FF61F67B050F7AA6FC92007DB4284` — thêm vào AdMob trước khi test ads thật.
- `.agents/` nằm trong `.gitignore` → token/skill local **không** bị đẩy lên remote (đã verify `git ls-files .agents` rỗng).
- Lịch sử test số: 207 (Gate C) → 249 → 288 (RC, 2026-09-08) → 315 (P7.2) → **343 (2026-09-12, verify lại)**.
