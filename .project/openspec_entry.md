# Openspec Entry — ShiftEase Session 2026-09-12 (release packaging + 2 crash P0 launch đã fix)

## Summary

Phiên này đưa repo từ "code + CI test" thành **có artifact phát hành thật**: 4 workflow GitHub Actions
(CI test · debug APK · release APK · release AAB ký **keystore cố định**), ads có 2 công tắc
(`ENABLE_ADS` / `TEST_ADS`), và **2 crash P0 lúc mở app đã fix tận gốc + verify trên máy thật**
(Pixel 3a, Android 12, arm64). Kết thúc phiên: `main` @ `a1d9b0c`, analyze sạch, **343/343**,
**5/5 run CI xanh**, release APK cài từ CI → cold start không crash, ads SDK init thật.

Số phận của 2 crash (đều **chỉ hiện ở release**, không thể thấy bằng debug build):

| # | Triệu chứng | Nguyên nhân gốc | Fix |
|---|---|---|---|
| 1 | Crash mọi lần mở app: `MobileAdsInitProvider: IllegalStateException: * Invalid application ID. *` | `-PenableAds=false` ghi `APPLICATION_ID=""` với giả định "SDK tự tắt" — thực tế ContentProvider của SDK validate **trước** `Application.onCreate()` và giết process | `adsAppId` thành **hằng số hợp lệ** trong `build.gradle.kts`; tắt ads chỉ còn là quyết định ở Dart (`--dart-define=ENABLE_ADS=false`) |
| 2 | Crash mọi cold start: `Failed to create an instance of androidx.work.impl.WorkDatabase` | `flutter build apk --release` **bật R8 minify** (Flutter plugin set `isMinifyEnabled = true`), Room tạo impl bằng reflection `Class.forName("..._Impl").newInstance()` → R8 xoá `<init>()`; WorkManager auto-init qua `androidx.startup` (kéo vào bởi ads SDK) chết trước `Application.onCreate()` | `android/app/proguard-rules.pro`: `-keep class * extends androidx.room.RoomDatabase { <init>(); }` + guard CI. **Không** tắt minify |

## Changes Made

### New — build / release
- `.github/workflows/build-release-apk.yml` — release APK (fat, hoặc dispatch `split_per_abi=true` → APK arm64 ~29 MB), verify app id + chữ ký `apksigner` + R8
- `.github/workflows/build-release-aab.yml` — AAB nộp Play, **fail-fast** nếu thiếu keystore secrets, verify `CN=ShiftEase` trước khi upload
- `android/app/proguard-rules.pro` — keep constructor Room (rule wildcard, phủ mọi DB Room từ dependency nào)
- `tool/check_manifest_ads.py` — parse **giá trị attribute thật** (AXML cho APK, protobuf cho bundle); `strings | grep` không đọc được string pool UTF-16 nên đã báo "OK" giả 2 lần
- `tool/check_r8_keep.py` — đọc `usage.txt` (R8 removed-code report), **fail build** nếu constructor bị xoá; thiếu report cũng fail (không no-op)
- `android/key.properties` **không tồn tại ở local** — chỉ được ghi từ GitHub secrets trong CI (`.gitignore` chặn keystore/key.properties)

### New — monetization
- `lib/config/ads_config.dart` (`enableAds` · `testAds` · unit IDs thật), `lib/features/ads/ad_service.dart` (UMP consent → `MobileAds.initialize()` → App Open cold start → Interstitial sau import commit), `lib/features/ads/ad_banner_widget.dart`, `test/config/ads_config_test.dart` (12 test)

### New — store / gh-pages / skills
- `chplay.md` (Play submission pack: listing ASO, Data Safety, content rating, checklist), `store_assets/{icon.png,feature_graphic.png,guide.html,privacy.html}`, `tool/make_store_assets.py`, `tool/make_icon.py`
- gh-pages: **chỉ còn 3 file public** (`index.html`, `guide.html`, `privacy.html`) — trước đó branch mirror cả source tree
- `.agents/skills/shiftease-ci-apk/SKILL.md` (project) + skill global `android-release-only-crash` (`SKILL.md`/`SPEC.md`/`SOURCES.md` + 2 script, validator PASS)

### Modified
- `android/app/build.gradle.kts` — compileSdk/targetSdk **36**, `signingConfigs.release` từ `key.properties`, `proguardFiles(...)`, `adsAppId` hằng số
- `android/app/src/main/AndroidManifest.xml` — `APPLICATION_ID` luôn hợp lệ + POST_NOTIFICATIONS
- `doc/release/build_notes.md` — §1.5 viết lại (bản cũ **đang mô tả đúng cái cách gây crash**), thêm §1.6 về R8/ProGuard
- `pubspec.yaml` (`admob:` flags), `lib/main.dart` (DB path mobile + ads init theo flag), scripts/tool

## Tests / Verification (chạy lại trên đĩa 2026-09-12 — không chép số cũ)

- `flutter analyze --no-pub --fatal-infos` → **No issues found!** (15.4s)
- `flutter test test/` → **343/343 All tests passed!** (exit=0, 2m03s)
  - `test/config` **12** · `test/core` **247** · `test/domain` **28** · `test/features` **16** · `test/ui` **40**
- **CI @ `a1d9b0c` — 5/5 xanh**: ShiftEase CI · Build Debug APK · Build release APK (push + dispatch split) · Build release AAB
- Guard output **thật** trên CI (không phải pass rỗng):
  `R8 removed-code report: build/app/outputs/mapping/release/usage.txt` → `OK: androidx.work.impl.WorkDatabase_Impl kept its no-arg constructor (3 other member(s) removed)`
- **Máy thật** (Pixel 3a / Android 12 / arm64-v8a), APK release từ CI cài đè (cùng keystore): `pidof`=665 · `ResumedActivity: com.shiftease.shiftease/.MainActivity` · `mHasSurface=true isReadyForDisplay()=true` · crash buffer **rỗng** · `E/flutter|FATAL` = **0** · ads SDK init (`Ads: ... setTestDeviceIds("CE6FF61F67B050F7AA6FC92007DB4284")`)
- Đối chứng bug #2: census DEX APK cũ cho thấy `WorkDatabase_Impl` **còn class + tên**, chỉ mất constructor → khớp nhánh `InstantiationException` trong message Room

## Decisions Made

1. **Fix tận gốc, không workaround.** Crash #1 không "tắt ads bằng cách làm rỗng khai báo"; crash #2 không `isMinifyEnabled=false`. Cả hai đều là bẫy đã lộ ra trên máy thật.
2. **"Tắt ads" chỉ là quyết định ở Dart** (`ENABLE_ADS`), manifest luôn mang app id hợp lệ — SDK validate trước `Application.onCreate()`, không try/catch nào cứu được.
3. **Verify artifact bằng parse giá trị thật** (attribute AXML / `usage.txt`), không bằng tìm chuỗi. Check cũ báo "OK" giả và để bug lọt 2 lần.
4. **Build xanh ≠ đã verify.** Gate release = cold start trên máy thật với artifact **ký release**; đã đưa thành checklist trong skill.
5. **Keystore cố định** (alias `shiftease`, SHA-256 ghi trong header workflow AAB) sống trong GitHub secrets — **không regenerate** (đổi upload key là Play từ chối).
6. **Bài học lặp lại → đóng thành skill**: generic `android-release-only-crash` (global, dùng cho mọi app) + sửa guidance **sai** trong skill project (`isMinifyEnabled=false`).
7. **Set `test_ads=false` + `enable_ads=true`** là default của release APK/AAB (bản phục vụ ads thật); dispatch có thể đổi mà không sửa code.

## Pending

- **Play Console (human)**: điền Data Safety + content rating theo `chplay.md` → bump `versionCode` → upload **AAB ký release** (đừng dùng APK).
- **iOS**: chưa build/verify (cần macOS + certs) — P8.4 vẫn BLOCKED.
- **Device/CI matrix cũ** (E3 permission · G SQLCipher native · I 15-row): nay **đã có release APK + adb** nên blocker giảm mạnh, nhưng **chưa chạy hết 15 dòng** — không được claim PASS.
- **AdMob**: thêm máy thật vào test device (`CE6FF61F67B050F7AA6FC92007DB4284`) trước khi test ads thật, tránh invalid traffic.
- **`next.md` / `next1.md` chưa sync** theo phiên này (ngoài scope `.project/`).
