enum InterstitialTrigger { save, newAnalysis, chat }

abstract interface class AdvertisingService {
  Future<void> recordSuccessfulSave();
  Future<void> recordNewAnalysis();
  Future<void> recordChatMessage();
  Future<void> showInterstitialIfEligible({
    InterstitialTrigger trigger = InterstitialTrigger.save,
    required bool Function() canShow,
  });
}
