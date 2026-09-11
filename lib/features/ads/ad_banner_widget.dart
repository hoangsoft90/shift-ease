// =============================================================================
// ShiftEase — AdMob banner widget (2026-09-11)
// =============================================================================
// Pin-to-bottom banner for the Jobs screen. Fully self-hiding:
//   • ads disabled (unit empty) / load failed / SDK not ready → SizedBox.shrink
//     (no layout jump for the user, no dead space)
//   • load success → 50dp banner, centered
// The widget never throws into the app: banner lifecycle errors are absorbed
// by the listener in BannerAdService (INVARIANT-008: ads are additive).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:shiftease/features/ads/ad_service.dart';

/// App-owned singleton so the banner survives screen rebuilds (one banner
/// instance per app; re-creating per build would leak ad objects).
final BannerAdService adService = BannerAdService();

/// Whether ads are enabled on the current platform/build (test hook: pass
/// [android] to force a branch in widget tests).
bool adsEnabledForPlatform({bool? android}) => adsEnabled(android: android);

class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  @override
  void initState() {
    super.initState();
    adService.onLoadedChanged = () {
      if (mounted) setState(() {});
    };
    // Kick the consent+init+load chain lazily on first widget mount — the
    // calendar must not wait for any ad infrastructure (INVARIANT-008).
    if (!adsEnabled()) return;
    initializeAds().then((_) => adService.loadBanner());
  }

  @override
  void dispose() {
    adService.onLoadedChanged = null;
    // NOTE: the singleton service itself is NOT disposed here — it is
    // app-scoped (dispose happens never in production; the banner is
    // cheap when idle and survives navigation).
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = adService.banner;
    if (ad == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
