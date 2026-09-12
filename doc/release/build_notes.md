# P8.3 / P8.4 — Release Build Notes (Android signed AAB / iOS archive)

> Nguồn: `phases/P8_release_preparation.md` §3–§4 · `plan_p8.md` §P8.3/P8.4.
> **Trạng thái tổng: BLOCKED — needs signing keys (human/CI).** Các bước dưới đây là checklist thực thi; agent không tự chạy và không PASS giả.

## Part 1 — Android (P8.3)

### 1.1 Điều kiện

- [ ] Keystore release (+ password + alias) — **human giữ, KHÔNG commit vào repo** (NEVER list)
- [ ] `key.properties` (local, gitignored) hoặc secret trong CI (GitHub Actions secrets)
- [ ] CI hoặc máy human có Flutter + JDK 17

### 1.2 Lệnh build (thực thi bởi human/CI — không chạy trong sandbox)

> ✅ **Signing đã implement (2026-09-12)** trong `android/app/build.gradle.kts`:
> `signingConfigs.release` được khai báo **chỉ khi** `android/key.properties`
> tồn tại (gitignored — `android/.gitignore` đã có rule `key.properties`,
> `*.keystore`, `*.jks`), đọc `storeFile`/`storePassword`/`keyAlias`/
> `keyPassword`; `storeFile` resolve tương đối `android/`. Không có file này →
> release build rơi về debug signing để QA vẫn cài được (Play sẽ từ chối
> "signed in debug mode" — phải có keystore thật khi build AAB).
>
> **Ads switch (2 nửa phải bật/tắt cùng nhau):**
> - `--android-project-arg=enableAds=false` → Gradle blank
>   `manifestPlaceholders["adsAppId"]`, APK không chứa AdMob APPLICATION_ID.
> - `--dart-define=ENABLE_ADS=false` → `AppAdsConfig.enableAds=false`, Dart
>   không bao giờ gọi `MobileAds.initialize()`.
> Test ads: `--dart-define=TEST_ADS=false` chỉ khi unit ID production đã điền.
>
> Workflow `build-release-apk.yml` truyền cả hai (input `enable_ads`,
> `test_ads` trên workflow_dispatch).

```bash
# AAB — artifact nộp Play (cần android/key.properties + keystore thật)
flutter build appbundle --release

# Release APK cho QA, ads TẮT hoàn toàn (không có APPLICATION_ID trong manifest
# + Dart không init SDK → không request nào; không crash)
flutter build apk --release \
  --android-project-arg=enableAds=false \
  --dart-define=ENABLE_ADS=false

# Release APK có ads thật (chỉ khi unit ID production đã điền trong ads_config.dart)
flutter build apk --release --dart-define=TEST_ADS=false
```

- Version tự lấy từ `pubspec.yaml` (`1.0.0+1` → versionName 1.0.0, versionCode 1) — không hard-code khác trong gradle.
- Build type `release` phải không có debug flag (đã audit: `lib/` không có kDebugMode/mock/endpoint).
- Gradle đọc `findProperty("enableAds")` (không lỗi khi không truyền → default `true`).
- **Build bằng `flutter build apk`, KHÔNG chạy `./gradlew` trực tiếp**: repo không
  commit Gradle wrapper (`android/.gitignore`) — flutter_tools inject wrapper đã pin
  (Gradle 9.3.1) từ cache của nó.

### 1.3 Verify sau build (mỗi dòng PASS/FAIL/NOT RUN — human)

| # | Hạng mục | Trạng thái |
|---|---|---|
| 1 | Install AAB (bundletool) / APK lên máy thật | NOT RUN |
| 2 | Launch, không crash | NOT RUN |
| 3 | Fresh install — DB mới tạo, mã hoá (SQLCipher mở bằng key mới) | NOT RUN |
| 4 | Upgrade from previous RC — theo `doc/release/upgrade_test_plan.md` | NOT RUN |
| 5 | Database opens; encrypted path opens (`verifyEncryption` = encrypted trong Settings) | NOT RUN |
| 6 | Notification permission flow (Android 13+ prompt) | NOT RUN |
| 7 | Backup/restore round-trip | NOT RUN |
| 8 | No debug UI / no debug logging (build release) | NOT RUN |
| 9 | Signature verify: `apksigner verify --print-certs` (hoặc Play Console chấp nhận — không bị từ chối "debug-signed") | NOT RUN |
| 10 | Ads disabled supply-chain verify (bila build dengan -PenableAds=false): APK `AndroidManifest.xml` hardcoded cos tidak ada `<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" ...` dengan nilai bukan kosong; APK boleh diinstall tanpa ads tanpa crash | NOT RUN |

### 1.4 Status

**BLOCKED — needs signing keys.** Không có keystore trong repo/sandbox; debug-APK pipeline (`build-debug-apk.yml`) là artifact QA, không thay thế signed release.

## Part 2 — iOS (P8.4)

### 2.1 Điều kiện

- [ ] Apple Developer account + distribution certificate + provisioning profile (App Store)
- [ ] macOS với Xcode (sandbox không có — cả build lẫn code signing)
- [ ] Bundle ID `com.shiftease.shiftease` đã đăng ký

### 2.2 Lệnh build (human)

```bash
flutter build ipa --release
# hoặc: open ios/Runner.xcworkspace → Product → Archive → Distribute
```

### 2.3 Verify sau build (human)

| # | Hạng mục | Trạng thái |
|---|---|---|
| 1 | Archive signed thành công | NOT RUN |
| 2 | Install (TestFlight/dev device) — launch, không crash | NOT RUN |
| 3 | Fresh install — DB encrypted, key trong Keychain | NOT RUN |
| 4 | Upgrade from previous build | NOT RUN |
| 5 | Keychain: key đọc lại được sau kill/reboot | NOT RUN |
| 6 | Notification permission + local reminder | NOT RUN |
| 7 | Backup/restore | NOT RUN |
| 8 | No debug UI / no development configuration | NOT RUN |

### 2.4 Status

**BLOCKED — needs certs/profiles + macOS.** Không PASS giả.

## Never (cả hai nền tảng)

- NEVER commit keystore/cert/password vào git
- NEVER PASS "signed release" chỉ vì debug build chạy được
- NEVER đổi signing config để "cho qua" — sai signing là lỗi phải sửa đúng cách

## 1.5 Ads-disable supply-chain (enable_ads=false)

> Không phải UI option; biasa dipakai untuk release APK sementara tanpa iklan
> (misalnya prototype/konsultasi internal) tanpa rubah kode Dart.
>
> Rantai kerja:
> 1. `pubspec.yaml` `admob.enable_ads: false`
>    Atau lewat CLI: `flutter build apk --release -PenableAds=false`.
> 2. `android/app/build.gradle.kts` — `enableAds` membaca properti Gradle
>    (default `true` kalau tidak ada) lalu `adsAppId` jadi `""` bila
>    `enableAds == "false"`.
> 3. `android/app/src/main/AndroidManifest.xml` — `<meta-data ... APPLICATION_ID ...>`
>    diisi oleh `manifestPlaceholders["adsAppId"]` → bila `adsAppId` kosong,
>    manifest mengandung `android:value=""`.
> 4. `google_mobile_ads` SDK di device menerima app ID kosong → SDK self-disable
>    (tidak request, tidak crash, tidak block startup).
> 5. Dart `AppAdsConfig.enableAds` masih `true` secara default (pubspec
>    `admob.enable_ads: true`); bila owner ingin kedua layer konsisten untuk
>    build tanpa iklan jangka panjang, set juga di pubspec — tapi workflow CI
>    cukup set `-PenableAds=false` saja.
>
> Catatan: `test_ads` (pubspec `admob.test_ads`) TIDAK berhubungan dengan
> enable_ads. `enable_ads=false` = hanya matikan SDK secara keseluruhan.
> `test_ads=false` = pakai production unit IDs (ads nyata bila unit disi).

```bash
# Verify lokal (QK, bukan verifikasi tanda tangan):
# Pastikan APK hasil build -PenableAds=false tidak mengandung app ID.
# (Sesuai prinsip: bila enableAds=false, meta-data APPLICATION_ID berisi "".)
```
