# result_admob_integration.md — AdMob Ads Integration (test_ads=true)

> Date: 2026-09-11 · User request: tích hợp AdMob kiếm tiền trên Play/App Store,
> flag `test_ads=true` để tránh AdMob giới hạn quảng cáo (LIMIT).

## Kiến trúc

```
pubspec.yaml (admob.test_ads: true)  ← 1 nơi flip
        ↓ mirror
lib/config/ads_config.dart           ← flag + ID resolution
   ├─ test mode  → Google TEST unit IDs (3940256099942544/...)
   └─ production → placeholder ''  ⇒ ads DISABLED (never falls back to test IDs)
        ↓
lib/features/ads/ad_service.dart     ← UMP consent → MobileAds.init → banner load
lib/features/ads/ad_banner_widget.dart ← self-hiding banner, pin bottom app shell
```

- **Banner duy nhất** đặt dưới app shell (`lib/app/app.dart` Column:
  JobsScreen + AdBannerWidget) — mọi màn đều có banner, calendar không bị ảnh
  hưởng layout khi ads tắt/chưa load (`SizedBox.shrink`).
- **Consent trước init** (UMP: `requestConsentInfoUpdate` →
  `loadAndShowConsentFormIfRequired` → `MobileAds.initialize()`): đúng thứ tự
  Google yêu cầu cho EEA/UK; failure của consent không block app.
- **Ads không bao giờ làm app lỗi**: mọi Google API call nằm trong try/catch,
  banner load-fail → dispose + về trạng thái tắt (INVARIANT-008 offline-first
  không đổi).
- minSdk pin **24** (google_mobile_ads 9.1.0 yêu cầu, trước đó
  `flutter.minSdkVersion`); targetSdk 36 giữ nguyên.

## Flag test_ads — đúng yêu cầu "tránh admob giới hạn quảng cáo"

- `admob.test_ads: true` trong pubspec (comment giải thích) + mirror
  `AppAdsConfig.testAds` (mutable chỉ để test flip, tearDown restore).
- Test mode → toàn bộ traffic dùng **Google test unit IDs**: thiết bị được coi
  là test device, không có invalid traffic thật trên account, **không rủi ro
  LIMIT**.
- Native manifests dùng **Google sample APPLICATION_IDs** (`~3347511713` /
  `~1458002511`) — Google chính thức cung cấp cho mục đích test, không thuộc
  account của ai → không thể sinh invalid traffic lên account thật.
- **Production checklist** ghi trong privacy.md §ads: khi đi live BẮT BUỘC
  (1) điền IDs thật vào `ads_config.dart` + manifest + Info.plist,
  (2) khai báo Data safety (Advertising ID) / App Privacy, (3) re-audit
  privacy.md — rồi mới flip `test_ads=false`. Test ID với `test_ads=false`
  sẽ bị **test chống fallback** chặn (ads = disabled, không crash).

## Files thay đổi

| File | Thay đổi |
|---|---|
| `pubspec.yaml` | + `google_mobile_ads: ^9.1.0`, + `admob: test_ads: true` |
| `lib/config/ads_config.dart` | NEW — flag, test/production IDs, `AdUnitIds.banner/interstitial` (return `''` khi production placeholder) |
| `lib/features/ads/ad_service.dart` | NEW — UMP consent + init + `BannerAdService` lifecycle |
| `lib/features/ads/ad_banner_widget.dart` | NEW — self-hiding banner widget + singleton service |
| `lib/app/app.dart` | wrap home: `Expanded(JobsScreen)` + `AdBannerWidget` |
| `android/.../AndroidManifest.xml` | + AdMob APPLICATION_ID (sample) meta-data |
| `ios/Runner/Info.plist` | + `GADApplicationIdentifier` (sample) + 39 SKAdNetworkItems |
| `android/app/build.gradle.kts` | minSdk pin 24 |
| `doc/release/privacy.md` | re-audit lần 3: 2 network consumers, Data safety checklist trước khi live ads |
| `doc/release/monitoring.md` | + AdMob console signal (impressions/clicks/policy alerts) |
| `test/config/ads_config_test.dart` | NEW — 6 tests |

## Tests (mới: 6)

- Test mode: đúng Google test ID từng platform; `adsEnabled = true`.
- Production placeholder: trả `''`, `adsEnabled = false` — **không fallback
  sang test ID** (test chống ship nhầm).
- Production constants không chứa prefix sample Google.
- Shipped default `testAds == true` (bảo vệ account).

## Evidence (session này)

- `flutter pub get` → resolved google_mobile_ads **9.1.0** (UMP API surface
  verified trực tiếp trong pub cache: `requestConsentInfoUpdate`,
  `loadAndShowConsentFormIfRequired(listener)`, `RequestConfiguration.testDeviceIds`).
- `flutter analyze --no-pub --fatal-infos` → **No issues found!**
- `flutter test test/` → **328/328 All tests passed!** (322 + 6)
- (2 vòng fix analyze trong session: unused import/field, và signature
  `loadAndShowConsentFormIfRequired` cần listener ở 9.1.0.)

## Còn lại (human, khi muốn kiếm tiền thật)

1. Tạo AdMob account → tạo app Android + iOS → lấy APPLICATION_IDs thật.
2. Tạo banner (+ interstitial nếu muốn) ad units → điền vào `ads_config.dart`
   (`kAdMob*Production`) + manifest + Info.plist.
3. Khai báo Play Data safety (Advertising ID collected/shared) + App Store
   App Privacy; re-audit privacy.md.
4. Flip `admob.test_ads: false` (pubspec + mirror trong `ads_config.dart`) →
   push → CI build → test trên device thật: banner hiện ads thật, không LIMIT.
5. (Tuỳ chọn) Gắn device test ID từ logcat vào RequestConfiguration để
   preview ads thật trên máy dev.
