import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/advertising/data/advertising_counter_store.dart';
import 'package:risparmiai/advertising/domain/advertising_service.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/data/repositories/savings_repository_impl.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'package:risparmiai/savings_checker/presentation/pages/savings_checker_page.dart';
import 'new_analysis_advertising_test.dart' show AdHarness;
import 'quantity_planner_test.dart' as fixture;
import 'conversation_intent_test.dart' show ScriptClient;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'fifth message with missing data and subsequent error defer ad until a complete result',
    (tester) async {
      final incomplete = fixture.plan();
      incomplete['status'] = 'needs_information';
      incomplete['missing'] = ['capacity'];
      incomplete['question'] = 'Quale capacità?';
      incomplete['operation'] = null;
      final client = ScriptClient([
        for (var i = 0; i < 4; i++) fixture.plan(),
        incomplete,
        StateError('Offline'),
        fixture.plan(),
      ]);
      final h = AdHarness();
      addTearDown(h.service.dispose);
      await tester.runAsync(h.start);
      final notifier = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: QuantityPlannerRepositoryImpl(aiClient: client),
      );
      addTearDown(notifier.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AdvertisingService>.value(value: h.service),
            ChangeNotifierProvider.value(value: notifier),
          ],
          child: const MaterialApp(home: SavingsCheckerPage()),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 1; i <= 7; i++) {
        await tester.enterText(find.byType(TextField), 'prodotto $i');
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('Invia'));
          while (notifier.isLoading) {
            await Future<void>.delayed(Duration.zero);
          }
          await tester.pump();
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(h.shows, i == 7 ? 1 : 0);
        if (i == 5) expect(notifier.hasPendingClarification, isTrue);
        if (i == 6) expect(notifier.hasFailedPlannerTurn, isTrue);
      }
      final counters = await tester.runAsync(
        () => AdvertisingCounterStore().read(),
      );
      expect(counters!.chatMessages, 0);
      expect(counters.saves, 0);
      expect(counters.newAnalyses, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('verified_price_observations_v1'), isNull);
    },
  );
}
