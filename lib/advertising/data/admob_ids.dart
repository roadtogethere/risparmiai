import 'package:flutter/foundation.dart';

/// Google demo units only. Replace these together with the native app IDs
/// when configuring production monetization.
class AdmobIds {
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get banner => defaultTargetPlatform == TargetPlatform.iOS
      ? 'ca-app-pub-3940256099942544/2435281174'
      : 'ca-app-pub-3940256099942544/9214589741';

  static String get interstitial => defaultTargetPlatform == TargetPlatform.iOS
      ? 'ca-app-pub-3940256099942544/4411468910'
      : 'ca-app-pub-3940256099942544/1033173712';
}
