// AdMob config tests (2026-09-11): the flag/ID contract that keeps the app
// out of AdMob trouble — test mode NEVER serves real traffic, production
// placeholders NEVER fall back to Google test IDs.
//
// Pure Dart logic: no Google SDK calls, no platform channels.
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftease/config/ads_config.dart';

void main() {
  tearDown(() {
    // The config is mutable ONLY for these tests — always restore test mode.
    AppAdsConfig.testAds = true;
  });

  group('AdUnitIds — test mode (test_ads=true, the shipped default)', () {
    test('Android banner/interstitial = Google TEST units', () {
      AppAdsConfig.testAds = true;
      expect(AdUnitIds.banner(android: true), kAdMobTestBannerAndroid);
      expect(AdUnitIds.interstitial(android: true),
          kAdMobTestInterstitialAndroid);
    });

    test('iOS banner/interstitial = Google TEST units', () {
      AppAdsConfig.testAds = true;
      expect(AdUnitIds.banner(android: false), kAdMobTestBannerIos);
      expect(AdUnitIds.interstitial(android: false),
          kAdMobTestInterstitialIos);
    });

    test('test units are never empty → adsEnabled true in test mode', () {
      AppAdsConfig.testAds = true;
      expect(adsEnabled(android: true), isTrue);
      expect(adsEnabled(android: false), isTrue);
    });
  });

  group('AdUnitIds — production mode (test_ads=false)', () {
    test('Android: real units resolve; iOS: still empty (ads disabled) — '
        'and NOTHING falls back to Google test IDs', () {
      AppAdsConfig.testAds = false;
      // Android production units filled 2026-09-11.
      expect(AdUnitIds.banner(android: true),
          kAdMobAndroidBannerUnitProduction);
      expect(AdUnitIds.interstitial(android: true),
          kAdMobAndroidInterstitialUnitProduction);
      expect(adsEnabled(android: true), isTrue);
      // iOS app/units not created yet → disabled, never a test-ID fallback.
      expect(AdUnitIds.banner(android: false), '');
      expect(AdUnitIds.interstitial(android: false), '');
      expect(adsEnabled(android: false), isFalse);
      // The core invariant: production mode NEVER serves Google test IDs.
      expect(AdUnitIds.banner(android: true), isNot(kAdMobTestBannerAndroid));
      expect(AdUnitIds.interstitial(android: true),
          isNot(kAdMobTestInterstitialAndroid));
    });

    test('production constants do not contain Google sample prefixes', () {
      // If someone fills a production unit with the Google sample ID, the
      // config review catches it here.
      for (final unit in [
        kAdMobAndroidBannerUnitProduction,
        kAdMobIosBannerUnitProduction,
        kAdMobAndroidInterstitialUnitProduction,
        kAdMobIosInterstitialUnitProduction,
      ]) {
        expect(unit.startsWith('ca-app-pub-3940256099942544/'), isFalse,
            reason:
                'production unit must not be the Google sample ad unit ID');
      }
    });
  });

  group('shipped default', () {
    test('test_ads defaults to TRUE in the repo (protect the AdMob account)',
        () {
      expect(AppAdsConfig.testAds, isTrue);
    });
  });

  group('production IDs filled (2026-09-11) — Android, still test mode', () {
    test('Android production units are real IDs (not sample, not empty)', () {
      expect(kAdMobAndroidAppIdProduction,
          'ca-app-pub-6917313063209470~6379119743');
      expect(kAdMobAndroidBannerUnitProduction,
          'ca-app-pub-6917313063209470/7669818989');
      expect(kAdMobAndroidInterstitialUnitProduction,
          'ca-app-pub-6917313063209470/5811153858');
      expect(kAdMobAndroidOpenAppUnitProduction,
          'ca-app-pub-6917313063209470/8158115597');
      expect(kAdMobAndroidRewardedUnitProduction,
          'ca-app-pub-6917313063209470/3866305343');
    });

    test('iOS production still empty → iOS ads stay disabled when flipped',
        () {
      AppAdsConfig.testAds = false;
      expect(AdUnitIds.banner(android: false), '');
      expect(AdUnitIds.interstitial(android: false), '');
    });

    test('test mode STILL resolves to Google test units despite filled prod',
        () {
      // The whole point of test_ads=true: filled production IDs must not be
      // requested until the flag flips.
      expect(AdUnitIds.banner(android: true), kAdMobTestBannerAndroid);
      expect(AdUnitIds.interstitial(android: true),
          kAdMobTestInterstitialAndroid);
    });

    test('openApp/rewarded: production IDs resolve only when flag flips; '
        'test mode returns empty (formats not rendered yet)', () {
      expect(AdUnitIds.openApp(android: true), '');
      expect(AdUnitIds.rewarded(android: true), '');
      AppAdsConfig.testAds = false;
      expect(AdUnitIds.openApp(android: true),
          'ca-app-pub-6917313063209470/8158115597');
      expect(AdUnitIds.rewarded(android: true),
          'ca-app-pub-6917313063209470/3866305343');
    });
  });
}
