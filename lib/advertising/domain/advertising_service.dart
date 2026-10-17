abstract interface class AdvertisingService {
  Future<void> recordSuccessfulSave();
  Future<void> showInterstitialIfEligible({required bool Function() canShow});
}
