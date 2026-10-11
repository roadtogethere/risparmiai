import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/savings_checker/data/datasources/verified_price_store.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/data/repositories/savings_repository_impl.dart';
import 'package:risparmiai/savings_checker/domain/entities/price_analysis.dart';
import 'package:risparmiai/savings_checker/domain/entities/quantity_plan.dart';
import 'package:risparmiai/savings_checker/domain/repositories/verified_price_history.dart';
import 'package:risparmiai/savings_checker/domain/services/price_comparison_service.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'package:risparmiai/savings_checker/presentation/pages/savings_checker_page.dart';
import 'package:risparmiai/savings_checker/presentation/pages/verified_prices_page.dart';
import 'quantity_planner_test.dart' as fixture;

Map<String, dynamic> water(double price, {double quantity = 1}) {
  final result = fixture.plan(value: quantity);
  result['facts']['price'] = fixture.fact(price, 'EUR');
  return result;
}

Future<ComparablePrice> priced(double price, {double quantity = 1}) async {
  final analysis = await QuantityPlannerRepositoryImpl(
    aiClient: fixture.Client([water(price, quantity: quantity)]),
  ).analyzeTurn('Acqua');
  return ComparablePrice.fromAnalysis(analysis);
}

class DelayedHistory implements VerifiedPriceHistory {
  final gate = Completer<void>();
  int writes = 0;
  bool fail = false;
  @override
  Future<List<SavedPrice>> read() async => [];
  @override
  Future<SavePriceResult> save(ComparablePrice price) async {
    writes++;
    await gate.future;
    if (fail) throw StateError('disk failure');
    return SavePriceResult(
      SavedPrice(price, DateTime.now()),
      alreadySaved: false,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const store = VerifiedPriceStore();

  for (final price in [5e-324, 1e308]) {
    test('historical mean keeps finite positive extreme $price', () async {
      await store.save(await priced(price));
      await store.save(await priced(price));
      final result = const PriceComparisonService().compare(
        await priced(price),
        await store.read(),
      );
      expect(result.previousAverage, price);
      expect(result.position, PricePosition.tiedMinimum);
    });
  }

  for (final incomplete in [true, false]) {
    test(
      'incomplete or AI-suggested facts cannot expose a save action ($incomplete)',
      () async {
        final payload = fixture.paper(complete: !incomplete);
        if (!incomplete) {
          payload['facts']['sheets_per_roll']['source'] = 'ai_suggestion';
        }
        final notifier = SavingsChatNotifier(
          repository: SavingsRepositoryImpl(),
          planner: QuantityPlannerRepositoryImpl(
            aiClient: fixture.Client([payload]),
          ),
        );
        await notifier.analyzeShoppingPrompt('Carta');
        expect(notifier.comparablePrice, isNull);
        expect(notifier.canSavePrice, isFalse);
        await notifier.saveCurrentPrice();
        expect(await store.read(), isEmpty);
        notifier.dispose();
      },
    );
  }

  test(
    'unrounded cost, identity and display unit; analysis never writes',
    () async {
      final price = await priced(12, quantity: 85);
      expect(price.unitCost, 12 / 85);
      expect(price.totalPrice, 12);
      expect(price.quantity, 85);
      expect(price.categoryKey, 'water');
      expect(price.canonicalMetric, 'liter');
      expect(price.displayUnit, 'liter');
      expect(price.analysis.revision, 1);
      expect(price.analysis.id, isNotEmpty);
      expect(await store.read(), isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString(
          VerifiedPriceStore.storageKey,
        ),
        isNull,
      );
    },
  );

  test(
    'first price has no relative judgment; saving does not change snapshot',
    () async {
      final notifier = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: QuantityPlannerRepositoryImpl(
          aiClient: fixture.Client([water(2)]),
        ),
      );
      await notifier.analyzeShoppingPrompt('Acqua 1 L 2 euro');
      final comparison = notifier.priceComparison!;
      expect(comparison.position, PricePosition.noHistory);
      expect(comparison.previousMinimum, isNull);
      expect(comparison.percentFromAverage, isNull);
      expect(comparison.isPotentialNewMinimum, isFalse);
      expect(notifier.canSavePrice, isTrue);
      await notifier.saveCurrentPrice();
      expect(notifier.priceSaved, isTrue);
      expect(notifier.priceComparison, same(comparison));
      expect((await store.read()), hasLength(1));
      await notifier.saveCurrentPrice();
      expect((await store.read()), hasLength(1));
      notifier.dispose();
    },
  );

  for (final example in [
    (1.0, PricePosition.potentialMinimum),
    (2.0, PricePosition.tiedMinimum),
    (2.5, PricePosition.belowAverage),
    (3.0, PricePosition.tiedAverage),
    (4.0, PricePosition.aboveAverage),
  ]) {
    test(
      'previous minimum/average classify ${example.$1} as ${example.$2}',
      () async {
        await store.save(await priced(2));
        await store.save(await priced(4));
        final current = await priced(example.$1);
        final comparison = const PriceComparisonService().compare(
          current,
          await store.read(),
        );
        expect(comparison.position, example.$2);
        expect(comparison.count, 2);
        expect(comparison.previousMinimum, 2);
        expect(comparison.previousAverage, 3);
        expect(comparison.differenceFromMinimum, example.$1 - 2);
        expect(comparison.differenceFromAverage, example.$1 - 3);
        expect(comparison.percentFromMinimum, (example.$1 - 2) / 2 * 100);
        expect(await store.read(), hasLength(2));
      },
    );
  }

  test('zero is comparable but unsaveable', () async {
    final price = await priced(0);
    expect(price.unitCost, 0);
    expect(price.canSave, isFalse);
    await expectLater(store.save(price), throwsFormatException);
    expect(await store.read(), isEmpty);
  });

  test(
    'legacy/M3 aggregates are not references and stay byte-identical',
    () async {
      final legacy = jsonEncode([
        {
          'key': 'other',
          'display_name': 'Altro',
          'primary_unit': 'litro',
          'average_unit_cost': 0.001,
          'sum_of_unit_costs': 0.02,
          'entries_count': 20,
          'required_attributes': [],
        },
      ]);
      SharedPreferences.setMockInitialValues({
        'user_custom_categories': legacy,
      });
      final current = await priced(2);
      expect(
        const PriceComparisonService()
            .compare(current, await store.read())
            .count,
        0,
      );
      await store.save(current);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'user_custom_categories',
        ),
        legacy,
      );
    },
  );

  test(
    'saved version immutable, corrections require another explicit save',
    () async {
      final client = fixture.Client([
        water(12, quantity: 85),
        water(12, quantity: 90),
        water(10, quantity: 90),
      ]);
      final notifier = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: QuantityPlannerRepositoryImpl(aiClient: client),
      );
      await notifier.analyzeShoppingPrompt('85 unità 12 euro');
      final id = notifier.plannerAnalysis!.id;
      await notifier.analyzeShoppingPrompt('Scusa sono 90');
      expect(notifier.comparablePrice!.unitCost, 12 / 90);
      expect(notifier.plannerAnalysis!.id, id);
      expect(await store.read(), isEmpty);
      await notifier.saveCurrentPrice();
      final raw = (await SharedPreferences.getInstance()).getString(
        VerifiedPriceStore.storageKey,
      );
      final revision = notifier.plannerAnalysis!.revision;
      await notifier.analyzeShoppingPrompt('Il prezzo corretto è 10 euro');
      expect(notifier.plannerAnalysis!.revision, greaterThan(revision));
      expect(notifier.plannerAnalysis!.id, id);
      expect(notifier.priceSaved, isFalse);
      expect(notifier.canSavePrice, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString(
          VerifiedPriceStore.storageKey,
        ),
        raw,
      );
      await notifier.saveCurrentPrice();
      final history = await store.read();
      expect(history, hasLength(2));
      expect(history.first.price.totalPrice, 12);
      expect(history.last.price.totalPrice, 10);
      expect(history.first.price.quantity, 90);
      notifier.dispose();
    },
  );

  test('concurrent repeated saves across instances are idempotent', () async {
    final price = await priced(3);
    final results = await Future.wait([
      store.save(price),
      const VerifiedPriceStore().save(price),
    ]);
    expect(results.where((r) => !r.alreadySaved), hasLength(1));
    expect(await store.read(), hasLength(1));
    expect((await const VerifiedPriceStore().save(price)).alreadySaved, isTrue);
  });

  test(
    'same economics in a later revision of same analysis is not duplicated',
    () async {
      final repo = QuantityPlannerRepositoryImpl(
        aiClient: fixture.Client([water(2), water(2)]),
      );
      final first = await repo.analyzeTurn('Acqua');
      await store.save(ComparablePrice.fromAnalysis(first));
      final next = await repo.analyzeTurn('Confermo', previous: first);
      expect(
        const PriceComparisonService()
            .compare(ComparablePrice.fromAnalysis(next), await store.read())
            .count,
        0,
      );
      expect(
        (await store.save(ComparablePrice.fromAnalysis(next))).alreadySaved,
        isTrue,
      );
      expect(await store.read(), hasLength(1));
    },
  );

  test('distinct concurrent observations retain all values', () async {
    final first = await priced(2);
    final second = await priced(4);
    await Future.wait([
      store.save(first),
      const VerifiedPriceStore().save(second),
    ]);
    expect(await store.read(), hasLength(2));
  });

  test('stored revision cannot be overwritten with different facts', () async {
    final first = await priced(2);
    await store.save(first);
    final changed = await priced(4);
    final conflicting = ComparablePrice.fromAnalysis(
      PlannerAnalysis(
        id: first.analysis.id,
        revision: first.analysis.revision,
        plan: changed.analysis.plan,
        schema: changed.analysis.schema,
        result: changed.analysis.result,
        userTurns: const [],
      ),
    );
    await expectLater(store.save(conflicting), throwsStateError);
    expect((await store.read()).single.price.totalPrice, 2);
  });

  test('saved unknown schema is reused after repository recreation', () async {
    await store.save(await priced(2));
    final payload = water(3);
    payload['category'] = {'key': 'water'};
    final client = fixture.Client([payload]);
    final analysis = await QuantityPlannerRepositoryImpl(
      aiClient: client,
    ).analyzeTurn('Acqua 3 euro');
    expect(analysis.result.quantity, 1);
    expect(
      client.catalogs.single['categories'].any(
        (dynamic c) => c['key'] == 'water',
      ),
      isTrue,
    );
  });

  test(
    'M5C.1 saved price survives simulated storage and notifier recreation',
    () async {
      final first = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: QuantityPlannerRepositoryImpl(
          aiClient: fixture.Client([water(2)]),
        ),
        priceHistory: VerifiedPriceStore(),
      );
      await first.analyzeShoppingPrompt('Acqua 1 L 2 euro');
      expect(first.priceComparison!.position, PricePosition.noHistory);
      await first.saveCurrentPrice();
      expect(first.priceSaved, isTrue);
      final savedId = first.comparablePrice!.observationId;
      final prefs = await SharedPreferences.getInstance();
      final persisted = <String, Object>{
        for (final key in prefs.getKeys()) key: prefs.get(key)!,
      };
      first.dispose();

      // Recreate the preferences mock from serialized data, not from domain objects.
      // This exercises reconstruction in one process, not smartphone restart durability.
      SharedPreferences.setMockInitialValues(persisted);
      final restoredStore = VerifiedPriceStore();
      final payload = water(3);
      payload['category'] = {
        'key': 'water',
      }; // Must reuse the persisted schema.
      final second = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: QuantityPlannerRepositoryImpl(
          aiClient: fixture.Client([payload]),
        ),
        priceHistory: restoredStore,
      );
      addTearDown(second.dispose);
      final restored = await restoredStore.read();
      expect(restored, hasLength(1));
      expect(restored.single.price.observationId, savedId);
      expect(restored.single.price.unitCost, 2);
      await second.analyzeShoppingPrompt('Acqua 1 L 3 euro');
      expect(second.errorMessage, isNull);
      expect(second.comparablePrice!.unitCost, 3);
      expect(second.priceComparison!.count, 1);
      expect(second.priceComparison!.previousMinimum, 2);
      expect(second.priceComparison!.previousAverage, 2);
      expect(second.priceComparison!.position, PricePosition.aboveAverage);
      expect(second.priceSaved, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString(
          VerifiedPriceStore.storageKey,
        ),
        persisted[VerifiedPriceStore.storageKey],
      );
    },
  );

  test('history corruption is not silently reset on save', () async {
    final price = await priced(2);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(VerifiedPriceStore.storageKey, '{broken');
    await expectLater(store.read(), throwsFormatException);
    await expectLater(store.save(price), throwsFormatException);
    expect(prefs.getString(VerifiedPriceStore.storageKey), '{broken');
  });

  test('stored cost tampering is rejected by recalculation', () async {
    await store.save(await priced(2));
    final prefs = await SharedPreferences.getInstance();
    final raw =
        jsonDecode(prefs.getString(VerifiedPriceStore.storageKey)!)
            as Map<String, dynamic>;
    raw['observations'][0]['unit_cost'] = 0.001;
    await prefs.setString(VerifiedPriceStore.storageKey, jsonEncode(raw));
    await expectLater(store.read(), throwsFormatException);
  });

  test(
    'comparison does not cross categories or metrics and excludes same saved revision',
    () async {
      final current = await priced(2);
      final saved = SavedPrice(current, DateTime.now());
      expect(const PriceComparisonService().compare(current, [saved]).count, 0);
      final foreign = fixture.plan(key: 'other_water', metric: 'liter');
      final analysis = await QuantityPlannerRepositoryImpl(
        aiClient: fixture.Client([foreign]),
      ).analyzeTurn('Altro');
      expect(
        const PriceComparisonService().compare(
          ComparablePrice.fromAnalysis(analysis),
          [saved],
        ).count,
        0,
      );
      final wrongMetric = fixture.plan(key: 'water', metric: 'kilogram');
      final different = await QuantityPlannerRepositoryImpl(
        aiClient: fixture.Client([wrongMetric]),
      ).analyzeTurn('Altro');
      expect(
        const PriceComparisonService().compare(
          ComparablePrice.fromAnalysis(different),
          [saved],
        ).count,
        0,
      );
    },
  );

  test(
    'save double click blocked; failure can be retried and result remains',
    () async {
      final history = DelayedHistory()..fail = true;
      final notifier = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        priceHistory: history,
        planner: QuantityPlannerRepositoryImpl(
          aiClient: fixture.Client([water(2)]),
        ),
      );
      await notifier.analyzeShoppingPrompt('Acqua');
      final saving = notifier.saveCurrentPrice();
      await notifier.saveCurrentPrice();
      notifier.startNewAnalysis();
      expect(notifier.comparablePrice, isNotNull);
      expect(history.writes, 1);
      history.gate.complete();
      await saving;
      expect(notifier.priceSaved, isFalse);
      expect(notifier.canSavePrice, isTrue);
      expect(notifier.saveMessage, contains('non riuscito'));
      history.fail = false;
      await notifier.saveCurrentPrice();
      expect(notifier.priceSaved, isTrue);
      expect(notifier.comparablePrice!.unitCost, 2);
      notifier.dispose();
    },
  );

  testWidgets(
    'UI saves only on explicit action and preserves displayed result',
    (tester) async {
      final notifier = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: QuantityPlannerRepositoryImpl(
          aiClient: fixture.Client([water(2)]),
        ),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: notifier,
          child: const MaterialApp(home: SavingsCheckerPage()),
        ),
      );
      await tester.runAsync(() => notifier.analyzeShoppingPrompt('Acqua'));
      await tester.pump();
      expect(find.textContaining('convenienza non valutabile'), findsOneWidget);
      expect(await tester.runAsync(store.read), isEmpty);
      final button = find.widgetWithText(FilledButton, 'Salva questo prezzo');
      await tester.ensureVisible(button);
      await tester.runAsync(() async {
        await tester.tap(button);
        while (notifier.isSaving) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pump();
      expect(find.text('Prezzo salvato'), findsOneWidget);
      expect(find.text('2 €/liter'), findsOneWidget);
      expect(await tester.runAsync(store.read), hasLength(1));
      expect(notifier.priceComparison!.count, 0);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Archivio'));
        await tester.pump();
        await store.read();
      });
      await tester.pumpAndSettle();
      expect(find.byType(VerifiedPricesPage), findsOneWidget);
      expect(find.text('Prezzi salvati'), findsOneWidget);
      expect(find.text('water'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      notifier.dispose();
    },
  );
}
