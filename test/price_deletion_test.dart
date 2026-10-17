import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/savings_checker/data/datasources/verified_price_store.dart';
import 'package:risparmiai/savings_checker/data/repositories/savings_repository_impl.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/domain/entities/price_analysis.dart';
import 'package:risparmiai/savings_checker/domain/services/price_comparison_service.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'package:risparmiai/savings_checker/presentation/pages/savings_checker_page.dart';
import 'package:risparmiai/savings_checker/presentation/pages/verified_prices_page.dart';
import 'price_history_test.dart' as fixture;
import 'quantity_planner_test.dart' as planner;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const store = VerifiedPriceStore();
  const comparison = PriceComparisonService();

  Future<void> act(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(() async {
      await action();
      await tester.pump();
      await store.read();
      await tester.pump();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  test(
    'deleting the minimum recalculates all statistics; undo restores exact record',
    () async {
      final first = await store.save(await fixture.priced(0.1412));
      final second = await store.save(await fixture.priced(0.15));
      final third = await store.save(await fixture.priced(0.2));
      final removed = await store.delete(first.observation.price.observationId);
      final remaining = await const VerifiedPriceStore().read();
      final summary = comparison.summarize(remaining);
      expect(summary.count, 2);
      expect(summary.minimum, 0.15);
      expect(summary.average, closeTo(0.175, 1e-12));
      final current = await fixture.priced(0.18);
      expect(comparison.compare(current, remaining).previousMinimum, 0.15);
      await store.restore(removed!);
      await store.restore(removed);
      final restored = await store.read();
      expect(restored.map((entry) => entry.price.observationId), [
        first.observation.price.observationId,
        second.observation.price.observationId,
        third.observation.price.observationId,
      ]);
      expect(restored.first.savedAt, first.observation.savedAt);
      expect(restored.first.price.unitCost, 0.1412);
      expect(restored.first.price.analysis.plan.facts['price']!.value, 0.1412);
      expect(comparison.summarize(restored).minimum, 0.1412);
    },
  );

  test(
    'last deletion yields no history; repeated delete is harmless',
    () async {
      final price = await fixture.priced(0.15);
      await store.save(price);
      final removed = await store.delete(price.observationId);
      expect(removed, isNotNull);
      expect(await store.delete(price.observationId), isNull);
      final empty = await store.read();
      final summary = comparison.summarize(empty);
      expect(summary.count, 0);
      expect(summary.minimum, isNull);
      expect(summary.average, isNull);
      expect(
        comparison.compare(await fixture.priced(0.18), empty).position,
        PricePosition.noHistory,
      );
    },
  );

  test(
    'concurrent delete, save and undo retain unrelated observations',
    () async {
      final first = await store.save(await fixture.priced(0.1412));
      final newPrice = await fixture.priced(0.15);
      final deletion = store.delete(first.observation.price.observationId);
      final saving = store.save(newPrice);
      final removed = await deletion;
      await saving;
      await store.restore(removed!);
      final records = await store.read();
      expect(records, hasLength(2));
      expect(records.map((entry) => entry.price.observationId).toSet(), {
        first.observation.price.observationId,
        newPrice.observationId,
      });
    },
  );

  testWidgets('delete updates summary without confirmation; undo restores it', (
    tester,
  ) async {
    final lowest = (await tester.runAsync(
      () async => store.save(await fixture.priced(0.1412)),
    ))!;
    await tester.runAsync(() async => store.save(await fixture.priced(0.15)));
    await act(
      tester,
      () => tester.pumpWidget(const MaterialApp(home: VerifiedPricesPage())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Minimo: 0,1412 €/liter'), findsOneWidget);
    expect(find.text('Osservazioni: 2'), findsOneWidget);
    await act(
      tester,
      () => tester.tap(
        find.byKey(
          ValueKey('delete-${lowest.observation.price.observationId}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Minimo: 0,1500 €/liter'), findsOneWidget);
    expect(find.text('Media: 0,1500 €/liter'), findsOneWidget);
    expect(find.text('Osservazioni: 1'), findsOneWidget);
    await act(tester, () => tester.tap(find.text('Annulla')));
    await tester.pumpAndSettle();
    expect(find.text('Minimo: 0,1412 €/liter'), findsOneWidget);
    expect(find.text('Osservazioni: 2'), findsOneWidget);
    expect(await tester.runAsync(store.read), hasLength(2));
  });

  testWidgets(
    'last price can be undone from empty state; deletion survives restart',
    (tester) async {
      final saved = (await tester.runAsync(
        () async => store.save(await fixture.priced(0.1412)),
      ))!;
      await act(
        tester,
        () => tester.pumpWidget(const MaterialApp(home: VerifiedPricesPage())),
      );
      await tester.pumpAndSettle();
      await act(
        tester,
        () => tester.tap(
          find.byKey(
            ValueKey('delete-${saved.observation.price.observationId}'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Nessun prezzo salvato.'), findsOneWidget);
      await act(tester, () => tester.tap(find.text('Annulla')));
      await tester.pumpAndSettle();
      expect(find.text('Osservazioni: 1'), findsOneWidget);
      await act(
        tester,
        () => tester.tap(
          find.byKey(
            ValueKey('delete-${saved.observation.price.observationId}'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await act(
        tester,
        () => tester.pumpWidget(const MaterialApp(home: VerifiedPricesPage())),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Nessun prezzo salvato.'), findsOneWidget);
      expect(await tester.runAsync(store.read), isEmpty);
    },
  );

  testWidgets('returning to chat refreshes cached comparison and saved state', (
    tester,
  ) async {
    final first = (await tester.runAsync(
      () async => store.save(await fixture.priced(0.1412)),
    ))!;
    await tester.runAsync(() async => store.save(await fixture.priced(0.15)));
    final notifier = SavingsChatNotifier(
      repository: SavingsRepositoryImpl(),
      planner: QuantityPlannerRepositoryImpl(
        aiClient: planner.Client([fixture.water(0.18)]),
      ),
    );
    addTearDown(notifier.dispose);
    await tester.runAsync(() => notifier.analyzeShoppingPrompt('Acqua'));
    expect(notifier.priceComparison!.previousMinimum, 0.1412);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: notifier,
        child: const MaterialApp(home: SavingsCheckerPage()),
      ),
    );
    await tester.pumpAndSettle();
    await act(tester, () => tester.tap(find.byTooltip('Archivio')));
    await tester.pumpAndSettle();
    await act(
      tester,
      () => tester.tap(
        find.byKey(ValueKey('delete-${first.observation.price.observationId}')),
      ),
    );
    await tester.pumpAndSettle();
    await act(tester, tester.pageBack);
    await tester.pumpAndSettle();
    expect(notifier.priceComparison!.previousMinimum, 0.15);
    expect(notifier.priceComparison!.previousAverage, 0.15);
    expect(notifier.priceComparison!.count, 1);
    await tester.runAsync(notifier.saveCurrentPrice);
    expect(notifier.priceSaved, isTrue);
    await tester.runAsync(
      () => store.delete(notifier.comparablePrice!.observationId),
    );
    await tester.runAsync(notifier.refreshPriceHistory);
    expect(notifier.priceSaved, isFalse);
    expect(notifier.canSavePrice, isTrue);
  });
}
