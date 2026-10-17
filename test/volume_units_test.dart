// Simulated planner JSON: no remote requests or claim about Android's AI reply.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/data/repositories/savings_repository_impl.dart';
import 'package:risparmiai/savings_checker/domain/entities/quantity_plan.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'quantity_planner_test.dart' as fixture;

Map<String, dynamic> bottles({bool complete = true}) {
  final payload = fixture.plan(key: 'beer', metric: 'liter');
  payload['category']['proposal']['display_name'] = 'Birra';
  payload['facts'] = {
    'price': fixture.fact(4, 'EUR'),
    'bottle_count': fixture.fact(6, 'bottle'),
    if (complete)
      'volume_per_bottle': fixture.fact(66, 'centiliter', per: 'bottle'),
  };
  payload['operation'] = {
    'type': 'multiply',
    'operands': ['bottle_count', 'volume_per_bottle'],
  };
  if (!complete) {
    payload['status'] = 'needs_information';
    payload['missing'] = ['volume_per_bottle'];
    payload['question'] = 'Qual è il volume per bottiglia?';
  }
  return payload;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final conversion in [
    ('centiliter', 'liter', 66.0, 0.66),
    ('milliliter', 'liter', 660.0, 0.66),
    ('liter', 'centiliter', 0.66, 66.0),
    ('centiliter', 'milliliter', 66.0, 660.0),
    ('milliliter', 'centiliter', 660.0, 66.0),
    ('liter', 'milliliter', 0.66, 660.0),
    ('gram', 'kilogram', 660.0, 0.66),
    ('kilogram', 'gram', 0.66, 660.0),
  ]) {
    test(
      'physical conversion ${conversion.$3} ${conversion.$1} to ${conversion.$2}',
      () {
        final result = fixture.resolve(
          fixture.plan(
            type: 'convert',
            observed: conversion.$1,
            metric: conversion.$2,
            value: conversion.$3,
          ),
        );
        expect(result.status, QuantityResolutionStatus.calculable);
        expect(result.quantity, closeTo(conversion.$4, 1e-12));
      },
    );
  }

  test(
    '6 times 66 cl becomes 3.96 liters and 4 EUR costs 1.0101 EUR/liter',
    () {
      final payload = bottles();
      final result = fixture.resolve(payload);
      expect(result.status, QuantityResolutionStatus.calculable);
      expect(result.quantity, closeTo(3.96, 1e-12));
      payload['operation']['operands'] = ['volume_per_bottle', 'bottle_count'];
      expect(fixture.resolve(payload).quantity, closeTo(3.96, 1e-12));
    },
  );

  for (final target in [('centiliter', 396.0), ('milliliter', 3960.0)]) {
    test('derived volume converts to canonical ${target.$1}', () {
      final payload = bottles();
      payload['category']['proposal']['canonical_metric'] = target.$1;
      payload['category']['proposal']['primary_unit'] = target.$1;
      expect(fixture.resolve(payload).quantity, closeTo(target.$2, 1e-9));
    });
  }

  test(
    '66cl continuation preserves facts and enables cost without implicit saving',
    () async {
      final firstPayload = bottles(complete: false)..['intent'] = 'new_product';
      final completion = bottles();
      completion['category'] = {'key': 'beer'};
      completion['facts'].remove('price');
      completion['facts'].remove('bottle_count');
      final client = fixture.Client([firstPayload, completion]);
      final notifier = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: QuantityPlannerRepositoryImpl(aiClient: client),
      );
      addTearDown(notifier.dispose);
      await notifier.analyzeShoppingPrompt('birra 4 euro 6 bottiglie');
      expect(notifier.comparablePrice, isNull);
      final first = notifier.plannerAnalysis!;
      expect(first.result.missing, ['volume_per_bottle']);
      await notifier.analyzeShoppingPrompt('66cl');
      final analysis = notifier.plannerAnalysis!;
      expect(analysis.id, first.id);
      expect(analysis.revision, first.revision + 1);
      expect(analysis.schema.canonicalMetric, 'liter');
      expect(analysis.plan.operation!.type, 'multiply');
      expect(analysis.plan.facts['bottle_count']!.unit, 'bottle');
      expect(analysis.plan.facts['bottle_count']!.value, 6);
      expect(analysis.plan.facts['volume_per_bottle']!.unit, 'centiliter');
      expect(analysis.plan.facts['volume_per_bottle']!.per, 'bottle');
      expect(analysis.plan.facts['volume_per_bottle']!.value, 66);
      final price = notifier.comparablePrice!;
      expect(price.quantity, closeTo(3.96, 1e-12));
      expect(price.unitCost, closeTo(4 / 3.96, 1e-12));
      expect(price.unitCost, closeTo(1.0101010101, 1e-10));
      expect(notifier.canSavePrice, isTrue);
      expect(client.requests.last['current_user_input'], '66cl');
      expect(
        client.requests.last['current_analysis']['question'],
        first.message,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('verified_price_observations_v1'), isNull);
      expect(prefs.getString('user_custom_categories'), isNull);
    },
  );

  test('unknown units and incompatible dimensions remain rejected', () {
    for (final target in ['kilogram', 'tablet']) {
      expect(
        fixture
            .resolve(
              fixture.plan(
                type: 'convert',
                observed: 'centiliter',
                metric: target,
                value: 66,
              ),
            )
            .reason,
        'unsupported_conversion',
      );
    }
    for (final unit in ['gram', 'bottle', 'unknown_volume']) {
      final payload = bottles();
      payload['facts']['volume_per_bottle']['unit'] = unit;
      expect(fixture.resolve(payload).reason, 'incompatible_dimensions');
    }
    final wrongDenominator = bottles();
    wrongDenominator['facts']['volume_per_bottle']['per'] = 'can';
    expect(fixture.resolve(wrongDenominator).reason, 'incompatible_dimensions');
    final wrongDirect = fixture.plan(
      type: 'direct',
      observed: 'centiliter',
      value: 66,
    );
    expect(fixture.resolve(wrongDirect).reason, 'incompatible_metric');
  });

  test('unconfirmed centiliters do not authorize calculation', () {
    final payload = bottles();
    payload['facts']['volume_per_bottle']['source'] = 'ai_suggestion';
    final result = fixture.resolve(payload);
    expect(result.status, QuantityResolutionStatus.needsInformation);
    expect(result.missing, ['volume_per_bottle']);
  });
}
