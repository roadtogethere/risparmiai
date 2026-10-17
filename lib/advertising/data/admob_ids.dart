import 'package:flutter/foundation.dart';

/// Debug/profile use Google demo units. Release uses the production units below.
/// Native AdMob app IDs must also be configured in AndroidManifest.xml/Info.plist.
class AdmobIds {
  // Insert your ad UNIT IDs here (containing '/', not the app IDs with '~').
  static const productionAndroidBanner = '';
  static const productionAndroidInterstitial = '';
  static const productionIosBanner = '';
  static const productionIosInterstitial = '';

  static bool get configured =>
      supported && banner.isNotEmpty && interstitial.isNotEmpty;

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get banner {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    if (kReleaseMode) {
      return ios ? productionIosBanner : productionAndroidBanner;
    }
    return ios
        ? 'ca-app-pub-3940256099942544/2435281174'
        : 'ca-app-pub-3940256099942544/9214589741';
  }

  static String get interstitial {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    if (kReleaseMode) {
      return ios ? productionIosInterstitial : productionAndroidInterstitial;
    }
    return ios
        ? 'ca-app-pub-3940256099942544/4411468910'
        : 'ca-app-pub-3940256099942544/1033173712';
  }
}
