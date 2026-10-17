import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'admob_ids.dart';
import 'advertising_debug_log.dart';

/// SDK boundary, allowing lifecycle tests without native ads or network access.
abstract interface class AdmobInterstitial {
  Future<void> show({
    required void Function() onShown,
    required void Function() onClosed,
    required void Function() onFailed,
  });
  void dispose();
}

class GoogleAdmobInterstitial implements AdmobInterstitial {
  GoogleAdmobInterstitial._(this._ad);
  final InterstitialAd _ad;

  static Future<AdmobInterstitial?> load() async {
    final result = Completer<AdmobInterstitial?>();
    await InterstitialAd.load(
      adUnitId: AdmobIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          logAdvertisingEvent('interstitial', 'loaded');
          result.complete(GoogleAdmobInterstitial._(ad));
        },
        onAdFailedToLoad: (error) {
          logAdvertisingEvent(
            'interstitial',
            'load_failed',
            errorCode: error.code,
          );
          result.complete(null);
        },
      ),
    );
    return result.future;
  }

  @override
  Future<void> show({
    required void Function() onShown,
    required void Function() onClosed,
    required void Function() onFailed,
  }) {
    _ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdImpression: (_) => logAdvertisingEvent('interstitial', 'impression'),
      onAdClicked: (_) => logAdvertisingEvent('interstitial', 'clicked'),
      onAdShowedFullScreenContent: (_) => onShown(),
      onAdDismissedFullScreenContent: (_) => onClosed(),
      onAdFailedToShowFullScreenContent: (_, _) => onFailed(),
    );
    return _ad.show();
  }

  @override
  void dispose() {
    unawaited(_ad.dispose());
  }
}
