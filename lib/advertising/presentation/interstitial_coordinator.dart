import 'package:flutter/widgets.dart';
import '../domain/advertising_service.dart';

class InterstitialCoordinator {
  const InterstitialCoordinator(this.service);
  final AdvertisingService service;

  Future<void> afterSave(
    BuildContext context, {
    required bool newlySaved,
  }) async {
    if (!newlySaved) return;
    try {
      await service.recordSuccessfulSave();
      if (!context.mounted) return;
      // Never show a late-loaded ad: only a ready ad at this UI transition.
      await service.showInterstitialIfEligible(
        canShow: () =>
            context.mounted &&
            ModalRoute.of(context)?.isCurrent == true &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
    } catch (_) {
      // Advertising failure must never change the successful save outcome.
    }
  }
}
