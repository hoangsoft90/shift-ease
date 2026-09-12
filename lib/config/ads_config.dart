// =============================================================================
// ShiftEase — AdMob configuration (2026-09-11)
// =============================================================================
// Monetization: banner ads under the Jobs screen (Play Store + App Store).
//
// Three independent gates (all must be open for any ad to load):
//   1. enableAds (build-time `--dart-define=ENABLE_ADS=...`, mirrored in the
//      pubspec `admob.enable_ads` docs) — hard master switch. When false the
//      app NEVER initializes the AdMob SDK. This is the flag you flip for a
//      release APK that must ship without ads while the AdMob account is still
//      being set up / while troubleshooting. The matching native half is
//      `--android-project-arg=enableAds=false` (blanks the manifest
//      APPLICATION_ID); the release workflow passes both.
//   2. testAds (build-time `--dart-define=TEST_ADS=...`) — SDK/creative
//      selection:
//      • true  → Google test ad unit IDs + sample APPLICATION_IDs (no real
//        ad traffic, no invalid-traffic/LIMIT risk, no account limit).
//      • false → production AdMob IDs below are used. Android units FILLED
//        (2026-09-11) so production Android serves real ads; iOS IDs empty
//        → production iOS ads stay disabled (no crash, no test-ID fallback).
//   3. Unit availability — a format is only requested when its resolved ID
//      is non-empty. Production iOS universally returns '' → no iOS ad ever
//      loads until iOS production app IDs are supplied.
//
// Production placeholders (owner fills from the AdMob console, then flips
// testAds to false):
//   kAdMob*AppIdProduction        → the App IDs (manifest/plist), NOT units
//   kAdMob*UnitProduction         → ad unit IDs per platform/format
// =============================================================================

import 'dart:io' show Platform;

/// Build-time defaults. Supplied by CI/local builds as
///   --dart-define=ENABLE_ADS=false --dart-define=TEST_ADS=true
/// Defaulting to `true` keeps plain `flutter run`/`flutter test` behavior
/// (and every existing test) exactly as before.
const bool _enableAdsFromBuild =
    bool.fromEnvironment('ENABLE_ADS', defaultValue: true);
const bool _testAdsFromBuild =
    bool.fromEnvironment('TEST_ADS', defaultValue: true);

/// Dart-side mirror of the pubspec `admob:` block (pubspec parsing of custom
/// maps would need a hook; one place to flip keeps config debuggable).
/// Mutable (not `const`) ONLY so tests can exercise both branches — they must
/// restore defaults in tearDown. Production flips these from the build-time
/// defaults below: enableAds = false for a no-ad release; testAds = false for
/// real ads once the AdMob IDs are filled in — both WITHOUT editing this file:
///   flutter build apk --release \
///     --android-project-arg=enableAds=false --dart-define=ENABLE_ADS=false
class AppAdsConfig {
  /// Master switch. When false the app never initializes the AdMob SDK.
  static bool enableAds = _enableAdsFromBuild;

  /// true = test mode (Google test IDs, sample app IDs). See file header.
  static bool testAds = _testAdsFromBuild;
}

/// Hard block: whether ANY ad code should run at all on this build.
/// Doubly guards so a single-assignment mistake cannot open ads:
///   • compile-time: if [AppAdsConfig.enableAds] is `false`, Dart never calls
///     into the AdMob SDK (banner/interstitial/app-open services early-return),
///     and the `google_mobile_ads` package would be dead code on that build
///     (native library still linked but unreachable).
///   • config-primitive: resolved unit ID must still be non-empty after the
///     test/production selection (production iOS, empty placeholders).
bool adsEnabled({bool? android}) =>
    AppAdsConfig.enableAds && AdUnitIds.banner(android: android) != '';

/// Google's official PUBLISHER-wide sample APPLICATION_IDs (safe to ship —
/// they only activate test infrastructure; Google's own docs use them).
const String kAdMobAndroidSampleAppId =
    'ca-app-pub-3940256099942544~3347511713';
const String kAdMobIosSampleAppId = 'ca-app-pub-3940256099942544~1458002511';

/// Google's official test AD UNIT IDs (banner/interstitial). Real inventory
/// never serves on these; clicks/impressions are explicitly allowed.
const String kAdMobTestBannerAndroid =
    'ca-app-pub-3940256099942544/6300978111';
const String kAdMobTestBannerIos = 'ca-app-pub-3940256099942544/2934735716';
const String kAdMobTestInterstitialAndroid =
    'ca-app-pub-3940256099942544/1033173712';
const String kAdMobTestInterstitialIos =
    'ca-app-pub-3940256099942544/4411468910';
const String kAdMobTestOpenAppAndroid =
    'ca-app-pub-3940256099942544/9257395921';
const String kAdMobTestOpenAppIos = 'ca-app-pub-3940256099942544/5575463023';

/// Production AdMob IDs — **Android FILLED 2026-09-11** (app + banner +
/// interstitial + open + rewarded). iOS app chưa tạo trên AdMob console →
/// iOS production IDs để rỗng ('') cho tới khi có: với test_ads=false, iOS
/// ads sẽ tự TẮT (không crash, không fallback sang test IDs).
const String kAdMobAndroidAppIdProduction =
    'ca-app-pub-6917313063209470~6379119743';
const String kAdMobIosAppIdProduction = '';
const String kAdMobAndroidBannerUnitProduction =
    'ca-app-pub-6917313063209470/7669818989';
const String kAdMobIosBannerUnitProduction = '';
const String kAdMobAndroidInterstitialUnitProduction =
    'ca-app-pub-6917313063209470/5811153858';
const String kAdMobIosInterstitialUnitProduction = '';
const String kAdMobAndroidOpenAppUnitProduction =
    'ca-app-pub-6917313063209470/8158115597';
const String kAdMobAndroidRewardedUnitProduction =
    'ca-app-pub-6917313063209470/3866305343';

/// Resolved per-platform ad unit IDs honoring [AppAdsConfig.testAds].
///
/// [android] overrides the platform probe in tests (production callers omit
/// it). Returns '' (ads disabled) for production placeholders — NEVER falls
/// back to a Google test ID when test mode is off.
class AdUnitIds {
  static String banner({bool? android}) =>
      _pick(android: android, testA: kAdMobTestBannerAndroid,
          testI: kAdMobTestBannerIos, prodA: kAdMobAndroidBannerUnitProduction,
          prodI: kAdMobIosBannerUnitProduction);

  static String interstitial({bool? android}) =>
      _pick(android: android, testA: kAdMobTestInterstitialAndroid,
          testI: kAdMobTestInterstitialIos,
          prodA: kAdMobAndroidInterstitialUnitProduction,
          prodI: kAdMobIosInterstitialUnitProduction);

  /// App Open ad unit — SHOWN on every cold start (AppOpenAdService in
  /// main.dart) once the SDK is initialized. iOS: no production app yet →
  /// '' (self-disabling) in production; test mode uses Google's test unit.
  static String openApp({bool? android}) =>
      _pick(android: android, testA: kAdMobTestOpenAppAndroid,
          testI: kAdMobTestOpenAppIos,
          prodA: kAdMobAndroidOpenAppUnitProduction, prodI: '');

  /// Rewarded ad unit — production Android ID đã điền, format CHƯA hiển thị
  /// (no placement yet → test mode returns '' so nothing requests it).
  static String rewarded({bool? android}) =>
      _pick(android: android, testA: '', testI: '',
          prodA: kAdMobAndroidRewardedUnitProduction, prodI: '');

  static String _pick({
    required bool? android,
    required String testA,
    required String testI,
    required String prodA,
    required String prodI,
  }) {
    final isAndroid = android ?? Platform.isAndroid;
    if (AppAdsConfig.testAds) return isAndroid ? testA : testI;
    return isAndroid ? prodA : prodI;
  }
}
