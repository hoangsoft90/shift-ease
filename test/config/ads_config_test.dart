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
    test('placeholder production units resolve to EMPTY (ads disabled) — '
        'never fall back to Google test IDs', () {
      AppAdsConfig.testAds = false;
      expect(AdUnitIds.banner(android: true), '');
      expect(AdUnitIds.banner(android: false), '');
      expect(AdUnitIds.interstitial(android: true), '');
      expect(AdUnitIds.interstitial(android: false), '');
      expect(adsEnabled(android: true), isFalse);
      expect(adsEnabled(android: false), isFalse);
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
}
