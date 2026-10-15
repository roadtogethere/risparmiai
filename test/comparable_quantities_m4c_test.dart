// Deterministic planner replies only: no remote model or semantic accuracy claim.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/domain/entities/price_analysis.dart';
import 'package:risparmiai/savings_checker/domain/entities/quantity_plan.dart';

import 'quantity_planner_test.dart' as fixture;

Map<String, dynamic> multipack({
  bool complete = true,
  String unit = 'milliliter',
  String metric = 'liter',
  String source = 'user_input',
  double volume = 330,
  double count = 6,
}) {
  final json = fixture.plan(key: 'new_beverage', metric: metric);
  json['facts'] = {
    'price': fixture.fact(3, 'EUR'),
    'container_count': fixture.fact(count, 'can'),
    if (complete)
      'volume_per_container': fixture.fact(
        volume,
        unit,
        per: 'can',
        source: source,
      ),
  };
  json['operation'] = {
    'type': 'multiply',
    'operands': ['container_count', 'volume_per_container'],
  };
  if (!complete) {
    json['status'] = 'needs_information';
    json['missing'] = ['volume_per_container'];
    json['question'] = 'Qual è il volume di ciascuna lattina?';
  }
  return json;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('new mass category: 750 g at 3 EUR costs 4 EUR/kg', () async {
    final json = fixture.plan(
      key: 'new_vegetable',
      metric: 'kilogram',
      type: 'convert',
      observed: 'gram',
      value: 750,
    );
    json['facts']['price'] = fixture.fact(3, 'EUR');
    final analysis = await QuantityPlannerRepositoryImpl(
      aiClient: fixture.Client([json]),
    ).analyzeTurn('Fagiolini, 750 g, 3 euro');
    expect(analysis.needsInformation, isFalse);
    final price = ComparablePrice.fromAnalysis(analysis);
    expect(price.quantity, 0.75);
    expect(price.unitCost, 4);
    expect(price.canonicalMetric, 'kilogram');
  });

  test(
    'missing capacity then 330 ml completes the same volume analysis',
    () async {
      final completion = multipack();
      completion['category'] = {'key': 'new_beverage'};
      // The repository must preserve price/count even when omitted on completion.
      completion['facts'].remove('price');
      completion['facts'].remove('container_count');
      final client = fixture.Client([multipack(complete: false), completion]);
      final repo = QuantityPlannerRepositoryImpl(aiClient: client);
      final first = await repo.analyzeTurn('Coca-Cola, 6 lattine, 3 euro');
      expect(first.needsInformation, isTrue);
      expect(first.result.quantity, isNull);
      expect(first.result.missing, ['volume_per_container']);
      expect(first.message, 'Qual è il volume di ciascuna lattina?');
      expect(first.plan.facts.containsKey('volume_per_container'), isFalse);
      final next = await repo.analyzeTurn('330 ml', previous: first);
      expect(next.id, first.id);
      expect(next.revision, first.revision + 1);
      expect(next.plan.facts['container_count']!.value, 6);
      expect(next.plan.facts['volume_per_container']!.value, 330);
      expect(next.plan.facts['volume_per_container']!.per, 'can');
      expect(next.plan.facts['price']!.value, 3);
      final price = ComparablePrice.fromAnalysis(next);
      expect(price.quantity, closeTo(1.98, 1e-12));
      expect(price.unitCost, closeTo(1.51515151515, 1e-10));
      expect(price.canonicalMetric, 'liter');
      expect(client.requests.last['user_turns'], [
        'Coca-Cola, 6 lattine, 3 euro',
        '330 ml',
      ]);
      expect(
        client.requests.last['current_analysis']['question'],
        first.message,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('verified_price_observations_v1'), isNull);
      expect(prefs.getString('user_custom_categories'), isNull);
    },
  );

  test(
    'declared multipack calculates immediately for a new volume category',
    () async {
      final analysis = await QuantityPlannerRepositoryImpl(
        aiClient: fixture.Client([multipack()]),
      ).analyzeTurn('Coca-Cola, 6 lattine da 330 ml, 3 euro');
      expect(analysis.needsInformation, isFalse);
      final price = ComparablePrice.fromAnalysis(analysis);
      expect(price.quantity, closeTo(1.98, 1e-12));
      expect(price.unitCost, closeTo(3 / 1.98, 1e-12));
    },
  );

  test('85 discrete tablets at 12 EUR require no extra attributes', () async {
    final json = fixture.plan(
      key: 'dishwasher_tabs',
      metric: 'tablet',
      value: 85,
    );
    json['category'] = {'key': 'dishwasher_tabs'};
    json['facts']['price'] = fixture.fact(12, 'EUR');
    final analysis = await QuantityPlannerRepositoryImpl(
      aiClient: fixture.Client([json]),
    ).analyzeTurn('Pastiglie lavastoviglie, 85 pezzi, 12 euro');
    expect(analysis.needsInformation, isFalse);
    expect(
      ComparablePrice.fromAnalysis(analysis).unitCost,
      closeTo(12 / 85, 1e-12),
    );
  });

  test('established schema prevails over a different AI proposal', () async {
    final repo = QuantityPlannerRepositoryImpl(
      aiClient: fixture.Client([multipack(), multipack(metric: 'milliliter')]),
    );
    await repo.analyzeTurn('6 lattine da 330 ml, 3 euro');
    final conflicting = await repo.analyzeTurn('6 lattine da 330 ml, 3 euro');
    expect(conflicting.schema.canonicalMetric, 'liter');
    expect(conflicting.result.reason, 'category_schema_conflict');
  });

  for (final source in ['ai_suggestion', 'external_lookup']) {
    test('unconfirmed capacity ($source) cannot authorize calculation', () {
      final result = fixture.resolve(multipack(source: source));
      expect(result.status, QuantityResolutionStatus.needsInformation);
      expect(result.missing, ['volume_per_container']);
      expect(result.quantity, isNull);
    });
  }

  test('multiply retains dimensional checks and rejects unknown scales', () {
    for (final unit in ['gram', 'bottle', 'EUR']) {
      expect(
        fixture.resolve(multipack(unit: unit)).reason,
        'incompatible_dimensions',
      );
    }
    final wrongDenominator = multipack();
    wrongDenominator['facts']['volume_per_container']['per'] = 'bottle';
    expect(fixture.resolve(wrongDenominator).reason, 'incompatible_dimensions');
  });

  test('physical scaling supports reversed operands and mass multipacks', () {
    final reversed = multipack();
    reversed['operation']['operands'] = [
      'volume_per_container',
      'container_count',
    ];
    expect(fixture.resolve(reversed).quantity, closeTo(1.98, 1e-12));
    expect(
      fixture
          .resolve(multipack(unit: 'gram', metric: 'kilogram', volume: 750))
          .quantity,
      4.5,
    );
    expect(
      fixture
          .resolve(multipack(unit: 'liter', metric: 'milliliter', volume: 0.33))
          .quantity,
      closeTo(1980, 1e-9),
    );
  });

  test('physical scaling retains overflow and underflow rejection', () {
    expect(
      fixture.resolve(multipack(count: 1e308, volume: 1e308)).reason,
      'invalid_quantity',
    );
    expect(
      fixture.resolve(multipack(count: 1e-300, volume: 1e-300)).reason,
      'invalid_quantity',
    );
    expect(
      fixture.resolve(multipack(count: 1, volume: 5e-324)).reason,
      'invalid_quantity',
    );
    expect(
      fixture
          .resolve(
            multipack(
              unit: 'liter',
              metric: 'milliliter',
              count: 1,
              volume: 1e308,
            ),
          )
          .reason,
      'invalid_quantity',
    );
  });
}
