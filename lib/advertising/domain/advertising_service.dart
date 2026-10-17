enum InterstitialTrigger { save, newAnalysis }

abstract interface class AdvertisingService {
  Future<void> recordSuccessfulSave();
  Future<void> recordNewAnalysis();
  Future<void> showInterstitialIfEligible({
    InterstitialTrigger trigger = InterstitialTrigger.save,
    required bool Function() canShow,
  });
}
