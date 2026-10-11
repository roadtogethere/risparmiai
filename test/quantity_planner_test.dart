import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/main.dart';
import 'package:risparmiai/savings_checker/data/datasources/ai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/category_reference_data_source.dart';
import 'package:risparmiai/savings_checker/data/datasources/category_reference_store.dart';
import 'package:risparmiai/savings_checker/data/datasources/gemini_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/openai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/models/category_reference_model.dart';
import 'package:risparmiai/savings_checker/data/models/quantity_plan_parser.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/data/repositories/savings_repository_impl.dart';
import 'package:risparmiai/savings_checker/domain/entities/quantity_plan.dart';
import 'package:risparmiai/savings_checker/domain/entities/required_attribute.dart';
import 'package:risparmiai/savings_checker/domain/services/comparable_quantity_resolver.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'package:risparmiai/savings_checker/presentation/pages/savings_checker_page.dart';

Map<String, dynamic> fact(
  num value,
  String unit, {
  String? per,
  String source = 'user_input',
}) => {'value': value, 'unit': unit, 'per': ?per, 'source': source};

Map<String, dynamic> plan({
  String key = 'water',
  String metric = 'liter',
  String type = 'direct',
  double value = 1.5,
  String? observed,
}) => {
  'status': 'sufficient',
  'category': {
    'key': key,
    'proposal': {
      'display_name': key,
      'canonical_metric': metric,
      'primary_unit': metric,
      'required_attributes': <dynamic>[],
    },
  },
  'facts': <String, dynamic>{
    'price': fact(0.75, 'EUR'),
    'quantity': fact(value, observed ?? metric),
  },
  'operation': <String, dynamic>{'type': type, 'operand': 'quantity'},
};

Map<String, dynamic> paper({bool complete = true}) => {
  'status': complete ? 'sufficient' : 'needs_information',
  'category': <String, dynamic>{'key': 'toilet_paper'},
  'facts': <String, dynamic>{
    'price': fact(5, 'EUR'),
    'rolls_count': fact(12, 'roll'),
    if (complete) 'sheets_per_roll': fact(200, 'sheet', per: 'roll'),
  },
  'operation': {
    'type': 'multiply',
    'operands': ['rolls_count', 'sheets_per_roll'],
  },
  if (!complete) 'missing': ['sheets_per_roll'],
  if (!complete) 'question': 'Quanti strappi contiene ciascun rotolo?',
};

const paperSchema = CategoryReferenceModel(
  key: 'toilet_paper',
  displayName: 'Carta igienica',
  primaryUnit: 'strappo',
  canonicalMetric: 'sheet',
  averageUnitCost: 0,
  requiredAttributes: [
    RequiredAttribute(key: 'rolls_count', label: 'Rotoli'),
    RequiredAttribute(key: 'sheets_per_roll', label: 'Strappi per rotolo'),
  ],
);

class Defaults extends CategoryReferenceDataSource {
  Defaults(this.items);
  final List<CategoryReferenceModel> items;
  @override
  Future<List<CategoryReferenceModel>> loadDefaultCategories() async => items;
}

class Client implements AiSavingsClient {
  Client(this.responses);
  final List<Map<String, dynamic>> responses;
  final List<Map<String, dynamic>> requests = [];
  final List<Map<String, dynamic>> catalogs = [];
  @override
  Future<Map<String, dynamic>> analyzeProductWithCatalog(
    String input,
    String catalog,
  ) async {
    requests.add(jsonDecode(input) as Map<String, dynamic>);
    catalogs.add(jsonDecode(catalog) as Map<String, dynamic>);
    return responses.removeAt(0);
  }
}

class PendingClient implements AiSavingsClient {
  final response = Completer<Map<String, dynamic>>();
  int calls = 0;
  @override
  Future<Map<String, dynamic>> analyzeProductWithCatalog(
    String input,
    String catalog,
  ) {
    calls++;
    return response.future;
  }
}

ComparableQuantityResult resolve(Map<String, dynamic> json) {
  final parsed = QuantityPlanParser.parse(json);
  return const ComparableQuantityResolver().resolve(
    parsed,
    parsed.categoryKey == 'toilet_paper' ? paperSchema : parsed.proposal!,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'recorded Gemini omission is visible; Dart never reconstructs price or plies',
    () async {
      final recorded = <String, dynamic>{
        'status': 'needs_information',
        'category': {'key': 'toilet_paper', 'proposal': null},
        'facts': {'rolls_count': fact(12, 'roll')},
        'operation': null,
        'missing': ['sheets_per_roll'],
        'question': 'Quanti strappi ci sono per ogni rotolo?',
      };
      final repo = QuantityPlannerRepositoryImpl(aiClient: Client([recorded]));
      final result = await repo.analyzeTurn(
        'carta igienica 12 rotolo 5 euro 3 veli',
      );
      expect(result.result.missing, containsAll(['price', 'sheets_per_roll']));
      expect(result.plan.facts.containsKey('price'), isFalse);
      expect(result.plan.facts.containsKey('plies_count'), isFalse);
      expect(result.result.quantity, isNull);
      expect(result.userTurns.single, contains('5 euro 3 veli'));
    },
  );

  test(
    'null operation preserves question and all supplied facts through 500 and correction',
    () async {
      final incomplete = paper(complete: false)..['operation'] = null;
      incomplete['facts']['plies_count'] = fact(3, 'ply');
      final completed = paper();
      completed['facts'] = {'sheets_per_roll': fact(500, 'sheet', per: 'roll')};
      final corrected = paper();
      corrected['facts'] = {
        'rolls_count': fact(10, 'roll'),
        'price': fact(6, 'EUR'),
      };
      final client = Client([incomplete, completed, corrected]);
      final notifier = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: QuantityPlannerRepositoryImpl(aiClient: client),
      );
      await notifier.analyzeShoppingPrompt(
        'carta igienica 12 rotolo 5 euro 3 veli',
      );
      final first = notifier.plannerAnalysis!;
      expect(first.result.missing, ['sheets_per_roll']);
      expect(
        notifier.messages.last.text,
        'Quanti strappi contiene ciascun rotolo?',
      );
      expect(first.plan.facts['price']!.value, 5);
      expect(first.plan.facts['plies_count']!.value, 3);
      expect(first.result.quantity, isNull);
      await notifier.analyzeShoppingPrompt('500');
      final second = notifier.plannerAnalysis!;
      expect(second.id, first.id);
      expect(second.result.quantity, 6000);
      expect(second.plan.facts['price']!.value, 5);
      expect(second.plan.facts['rolls_count']!.value, 12);
      expect(second.plan.facts['plies_count']!.value, 3);
      expect(
        client.requests[1]['current_analysis']['facts']['plies_count']['value'],
        3,
      );
      await notifier.analyzeShoppingPrompt(
        'Correzione: sono 10 rotoli e costano 6 euro',
      );
      final third = notifier.plannerAnalysis!;
      expect(third.id, first.id);
      expect(third.result.quantity, 5000);
      expect(third.plan.facts['price']!.value, 6);
      expect(third.plan.facts['rolls_count']!.value, 10);
      expect(third.plan.facts['plies_count']!.value, 3);
      expect(third.plan.facts['sheets_per_roll']!.value, 500);
      expect(first.plan.facts['price']!.value, 5);
      expect(client.requests.last['user_turns'], hasLength(3));
      expect(notifier.errorMessage, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'user_custom_categories',
        ),
        isNull,
      );
      notifier.dispose();
    },
  );

  test(
    'correction while incomplete preserves unrelated facts and still asks for sheets',
    () async {
      final initial = paper(complete: false)..['operation'] = null;
      initial['facts']['plies_count'] = fact(3, 'ply');
      final corrected = paper(complete: false)..['operation'] = null;
      corrected['facts'] = {'price': fact(4.5, 'EUR')};
      final repo = QuantityPlannerRepositoryImpl(
        aiClient: Client([initial, corrected]),
      );
      final first = await repo.analyzeTurn('Carta 12 rotoli 5 euro 3 veli');
      final next = await repo.analyzeTurn(
        'Il prezzo corretto è 4,50 euro',
        previous: first,
      );
      expect(next.id, first.id);
      expect(next.plan.facts['price']!.value, 4.5);
      expect(next.plan.facts['rolls_count']!.value, 12);
      expect(next.plan.facts['plies_count']!.value, 3);
      expect(next.result.missing, ['sheets_per_roll']);
      expect(next.result.quantity, isNull);
    },
  );

  test('planner notifier blocks duplicate submits', () async {
    final client = PendingClient();
    final notifier = SavingsChatNotifier(
      repository: SavingsRepositoryImpl(),
      planner: QuantityPlannerRepositoryImpl(
        aiClient: client,
        categoryStore: CategoryReferenceStore(defaultDataSource: Defaults([])),
      ),
    );
    final pending = notifier.analyzeShoppingPrompt('Acqua 1.5 L');
    await notifier.analyzeShoppingPrompt('Acqua 1.5 L');
    while (client.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    client.response.complete(plan());
    await pending;
    expect(client.calls, 1);
    expect(notifier.plannerAnalysis!.result.quantity, 1.5);
    expect(notifier.messages.length, 2);
    notifier.dispose();
  });
  test(
    'needs_information never calculates even when facts appear complete',
    () {
      final json = plan()..['status'] = 'needs_information';
      expect(resolve(json).quantity, isNull);
      expect(resolve(json).status, QuantityResolutionStatus.needsInformation);
    },
  );
  test(
    'session schema is reused; AI cannot redefine metric on next analysis',
    () async {
      final second = plan(metric: 'milliliter');
      final client = Client([plan(), second]);
      final repo = QuantityPlannerRepositoryImpl(
        aiClient: client,
        categoryStore: CategoryReferenceStore(defaultDataSource: Defaults([])),
      );
      final first = await repo.analyzeTurn('Acqua 1.5 L');
      final next = await repo.analyzeTurn('Acqua 500 ml');
      expect(first.id, isNot(next.id));
      expect(
        client.catalogs.last['categories'][0]['canonical_metric'],
        'liter',
      );
      expect(next.schema.canonicalMetric, 'liter');
      expect(next.result.reason, 'category_schema_conflict');
    },
  );
  test(
    'existing economic archive stays byte-identical on incomplete and complete plans',
    () async {
      final raw = jsonEncode([
        paperSchema.toJson()..addAll({
          'average_unit_cost': 0.01,
          'sum_of_unit_costs': 0.03,
          'entries_count': 2,
        }),
      ]);
      SharedPreferences.setMockInitialValues({'user_custom_categories': raw});
      final repo = QuantityPlannerRepositoryImpl(
        aiClient: Client([paper(complete: false), paper()]),
      );
      final first = await repo.analyzeTurn('Carta 12 rotoli 5 euro');
      expect(
        (await SharedPreferences.getInstance()).getString(
          'user_custom_categories',
        ),
        raw,
      );
      await repo.analyzeTurn('200', previous: first);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'user_custom_categories',
        ),
        raw,
      );
    },
  );
  test(
    'existing capsule schema is not migrated to tablet by default change',
    () async {
      final legacySchema = CategoryReferenceModel(
        key: 'dishwasher_tabs',
        displayName: 'Pastiglie',
        primaryUnit: 'capsula',
        canonicalMetric: 'capsule',
        averageUnitCost: 0.2,
        requiredAttributes: const [],
      );
      final raw = jsonEncode([legacySchema.toJson()]);
      SharedPreferences.setMockInitialValues({'user_custom_categories': raw});
      final result = await QuantityPlannerRepositoryImpl(
        aiClient: Client([
          plan(key: 'dishwasher_tabs', metric: 'tablet', value: 85),
        ]),
      ).analyzeTurn('85 pastiglie');
      expect(result.schema.canonicalMetric, 'capsule');
      expect(result.result.reason, 'category_schema_conflict');
      expect(
        (await SharedPreferences.getInstance()).getString(
          'user_custom_categories',
        ),
        raw,
      );
    },
  );
  test('unknown schema must be present and valid', () async {
    final json = plan()..['category'] = {'key': 'water'};
    await expectLater(
      QuantityPlannerRepositoryImpl(
        aiClient: Client([json]),
        categoryStore: CategoryReferenceStore(defaultDataSource: Defaults([])),
      ).analyzeTurn('Acqua'),
      throwsA(isA<Exception>()),
    );
    final broken = plan();
    broken['category']['proposal']['required_attributes'] = [
      {'key': 'x', 'label': 'X'},
      {'key': 'x', 'label': 'X'},
    ];
    expect(() => QuantityPlanParser.parse(broken), throwsFormatException);
  });
  test('null operation preserves facts without inventing a quantity', () {
    final json = plan()..['operation'] = null;
    expect(resolve(json).missing, ['operation']);
    expect(resolve(json).quantity, isNull);
  });

  test(
    'A: default dishwasher tablets resolve DIRECT with no question',
    () async {
      final json = plan(key: 'dishwasher_tabs', metric: 'tablet', value: 85);
      json['facts']['price'] = fact(12, 'EUR');
      json['category'] = {'key': 'dishwasher_tabs'};
      final result = await QuantityPlannerRepositoryImpl(
        aiClient: Client([json]),
      ).analyzeTurn('Pastiglie lavastoviglie, 85, 12 euro');
      expect(result.result.quantity, 85);
      expect(result.result.canonicalMetric, 'tablet');
      expect(result.needsInformation, isFalse);
    },
  );
  test('B: paper MULTIPLY 12 roll x 200 sheet/roll = 2400 sheet', () {
    final result = resolve(paper());
    expect(result.quantity, 2400);
    expect(result.canonicalMetric, 'sheet');
  });
  test('C: incomplete paper is normal domain state without quantity', () {
    final result = resolve(paper(complete: false));
    expect(result.status, QuantityResolutionStatus.needsInformation);
    expect(result.missing, ['sheets_per_roll']);
    expect(result.quantity, isNull);
  });
  test(
    'D: water DIRECT is 1.5 liter',
    () => expect(resolve(plan()).quantity, 1.5),
  );
  test('E: water CONVERT 500 ml is 0.5 liter', () {
    final json = plan(type: 'convert', value: 500, observed: 'milliliter');
    json['facts']['price'] = fact(0.40, 'EUR');
    expect(resolve(json).quantity, 0.5);
  });
  test('F: unknown freezer labels DIRECT without category code', () async {
    final store = CategoryReferenceStore(defaultDataSource: Defaults([]));
    final repo = QuantityPlannerRepositoryImpl(
      aiClient: Client([
        plan(key: 'freezer_labels', metric: 'label', value: 120),
      ]),
      categoryStore: store,
    );
    final result = await repo.analyzeTurn('Etichette freezer 120, 3 euro');
    expect(result.result.quantity, 120);
    expect(result.result.canonicalMetric, 'label');
    expect(await store.loadCustomCategories(), isEmpty);
  });
  test('G: unknown food bags MULTIPLY without category code', () async {
    final json = plan(key: 'food_storage_bags', metric: 'bag');
    json['facts'] = {
      'price': fact(3, 'EUR'),
      'rolls': fact(3, 'roll'),
      'bags_per_roll': fact(20, 'bag', per: 'roll'),
    };
    json['operation'] = {
      'type': 'multiply',
      'operands': ['rolls', 'bags_per_roll'],
    };
    final result = await QuantityPlannerRepositoryImpl(
      aiClient: Client([json]),
      categoryStore: CategoryReferenceStore(defaultDataSource: Defaults([])),
    ).analyzeTurn('Sacchetti alimentari 3 rotoli da 20, 3 euro');
    expect(result.result.quantity, 60);
    expect(result.result.canonicalMetric, 'bag');
  });
  test(
    'DIRECT declared sheets bypasses recipe attributes without weakening M3',
    () {
      final json = plan(key: 'toilet_paper', metric: 'sheet', value: 6000);
      json['category'] = {'key': 'toilet_paper'};
      expect(resolve(json).quantity, 6000);
      expect(
        () => paperSchema.validateObservation(unit: 'strappo', metric: 'sheet'),
        throwsA(isA<Exception>()),
      );
    },
  );
  test('sufficient does not authorize a missing operand', () {
    final json = paper(complete: false)..['status'] = 'sufficient';
    expect(resolve(json).missing, ['sheets_per_roll']);
    expect(resolve(json).quantity, isNull);
  });
  test('multiply validates dimensions, not merely two numbers', () {
    final json = paper();
    json['facts']['sheets_per_roll'] = fact(200, 'liter');
    expect(resolve(json).reason, 'incompatible_dimensions');
  });
  test('reversed operands retain dimensional meaning', () {
    final json = paper();
    json['operation']['operands'] = ['sheets_per_roll', 'rolls_count'];
    expect(resolve(json).quantity, 2400);
  });
  for (final source in ['ai_suggestion', 'external_lookup']) {
    test('$source cannot authorize calculation', () {
      final json = paper();
      json['facts']['sheets_per_roll']['source'] = source;
      expect(resolve(json).status, QuantityResolutionStatus.needsInformation);
      expect(resolve(json).quantity, isNull);
    });
  }
  test('unsupported conversion is not a semantic conversion', () {
    expect(
      resolve(plan(type: 'convert', observed: 'bottle')).reason,
      'unsupported_conversion',
    );
    expect(
      resolve(plan(type: 'convert', observed: 'gram')).reason,
      'unsupported_conversion',
    );
  });
  test(
    'unknown operation is rejected',
    () => expect(resolve(plan(type: 'divide')).reason, 'unsupported_operation'),
  );
  for (final value in [0.0, -1.0, double.nan, double.infinity]) {
    test('invalid quantity $value has no fallback', () {
      expect(
        resolve(plan(value: value)).status,
        QuantityResolutionStatus.rejected,
      );
      expect(resolve(plan(value: value)).quantity, isNull);
    });
  }
  test('missing price differs from zero price', () {
    final json = plan();
    json['facts'].remove('price');
    expect(resolve(json).missing, ['price']);
    json['facts']['price'] = fact(0, 'EUR');
    expect(resolve(json).quantity, 1.5);
  });
  for (final price in [-1.0, double.nan, double.infinity]) {
    test('invalid price $price cannot calculate', () {
      final json = plan();
      json['facts']['price'] = fact(price, 'EUR');
      expect(resolve(json).status, QuantityResolutionStatus.rejected);
    });
  }
  test('known category canonical proposal cannot overwrite local schema', () {
    final json = paper();
    json['category']['proposal'] = plan(metric: 'roll')['category']['proposal'];
    expect(resolve(json).reason, 'category_schema_conflict');
  });
  for (final field in [
    'comparableQuantity',
    'comparable_quantity',
    'unitCost',
    'unit_cost',
    'comparison',
    'average_unit_cost',
    'units_per_package',
    'specific_attributes',
  ]) {
    test('AI business/legacy field $field is not authoritative', () {
      final json = plan()..[field] = 6000;
      expect(() => QuantityPlanParser.parse(json), throwsFormatException);
    });
  }
  test('AI conversion factor is rejected', () {
    final json = plan(type: 'convert');
    json['operation']['factor'] = 0.001;
    expect(() => QuantityPlanParser.parse(json), throwsFormatException);
  });
  test('missing provenance cannot silently become user input', () {
    final json = plan();
    json['facts']['quantity'].remove('source');
    expect(() => QuantityPlanParser.parse(json), throwsFormatException);
  });
  test('overflow/underflow and division guardrails retained', () {
    final json = paper();
    json['facts']['rolls_count']['value'] = 1e308;
    expect(resolve(json).reason, 'invalid_quantity');
    json['facts']['rolls_count']['value'] = 1e-300;
    json['facts']['sheets_per_roll']['value'] = 1e-300;
    expect(resolve(json).reason, 'invalid_quantity');
    expect(resolve(plan(value: 5e-324)).reason, 'invalid_unit_cost');
  });
  for (final conversion in [
    ('gram', 'kilogram', 750.0, 0.75),
    ('kilogram', 'gram', 0.75, 750.0),
    ('liter', 'milliliter', 0.5, 500.0),
  ]) {
    test('physical conversion ${conversion.$1} to ${conversion.$2}', () {
      expect(
        resolve(
          plan(
            type: 'convert',
            observed: conversion.$1,
            metric: conversion.$2,
            value: conversion.$3,
          ),
        ).quantity,
        closeTo(conversion.$4, 1e-10),
      );
    });
  }
  test(
    'legacy canonical null is not inferred from label or proposal',
    () async {
      final store = CategoryReferenceStore(
        defaultDataSource: Defaults([
          const CategoryReferenceModel(
            key: 'water',
            displayName: 'Water',
            primaryUnit: 'liter',
            averageUnitCost: 2,
            requiredAttributes: [],
          ),
        ]),
      );
      final result = await QuantityPlannerRepositoryImpl(
        aiClient: Client([plan()]),
        categoryStore: store,
      ).analyzeTurn('Water 1.5 L');
      expect(result.result.reason, 'unverified_legacy_metric');
    },
  );
  testWidgets(
    'C continuation: bare 500 completes same local analysis, never writes history',
    (tester) async {
      final completed = paper();
      completed['facts'] = {
        'sheets_per_roll': fact(
          500,
          'sheet',
          per: 'roll',
          source: 'user_confirmation',
        ),
      };
      final client = Client([paper(complete: false), completed]);
      final repo = QuantityPlannerRepositoryImpl(
        aiClient: client,
        categoryStore: CategoryReferenceStore(
          defaultDataSource: Defaults([paperSchema]),
        ),
      );
      final notifier = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: repo,
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: notifier,
          child: const MaterialApp(home: SavingsCheckerPage()),
        ),
      );
      await tester.runAsync(
        () => notifier.analyzeShoppingPrompt(
          'Carta igienica Foxy Mega, 12 rotoli, 5 euro',
        ),
      );
      await tester.pump();
      final id = notifier.plannerAnalysis!.id;
      expect(notifier.errorMessage, isNull);
      expect(
        find.text('Quanti strappi contiene ciascun rotolo?'),
        findsOneWidget,
      );
      expect(find.text('Migliore convenienza'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'user_custom_categories',
        ),
        isNull,
      );
      await tester.runAsync(() => notifier.analyzeShoppingPrompt('500'));
      await tester.pump();
      expect(notifier.plannerAnalysis!.id, id);
      expect(notifier.plannerAnalysis!.result.quantity, 6000);
      expect(notifier.plannerAnalysis!.plan.facts['price']!.value, 5);
      expect(client.requests.last['user_turns'], [
        'Carta igienica Foxy Mega, 12 rotoli, 5 euro',
        '500',
      ]);
      expect(client.requests.last['current_analysis']['missing'], [
        'sheets_per_roll',
      ]);
      expect(find.textContaining('6000.0 strappo'), findsOneWidget);
      expect(find.text('Migliore convenienza'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'user_custom_categories',
        ),
        isNull,
      );
      client.responses.add(completed);
      final repeated = await repo.analyzeTurn(
        '500',
        previous: notifier.plannerAnalysis,
      );
      expect(repeated.id, id);
      expect(repeated.result.quantity, 6000);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'user_custom_categories',
        ),
        isNull,
      );
      await tester.tap(find.byTooltip('Nuova analisi'));
      expect(notifier.plannerAnalysis, isNull);
      await tester.pumpWidget(const SizedBox());
      notifier.dispose();
    },
  );
  testWidgets('MainApp wires the planner for live providers', (tester) async {
    final client = Client([plan()]);
    await tester.pumpWidget(MainApp(useMockData: false, aiClient: client));
    await tester.enterText(find.byType(TextField), 'Acqua 1,5 L 0,75 euro');
    // Access the notifier through the actual application wiring.
    final context = tester.element(find.byType(SavingsCheckerPage));
    await tester.runAsync(
      () => context.read<SavingsChatNotifier>().analyzeShoppingPrompt(
        'Acqua 1,5 L 0,75 euro',
      ),
    );
    await tester.pump();
    expect(find.textContaining('1.5 liter'), findsOneWidget);
    expect(find.text('Migliore convenienza'), findsNothing);
  });
  test(
    'provider requests share the M4A protocol, legacy parser remains separate',
    () {
      final openai = OpenAiSavingsClient().buildRequestPayload('500');
      final gemini = GeminiSavingsClient().buildRequestPayload('500', null);
      expect(
        openai['messages'][0]['content'],
        gemini['system_instruction']['parts'][0]['text'],
      );
      expect(openai['messages'][0]['content'], contains('user_confirmation'));
      expect(
        QuantityPlanParser.decode(jsonEncode(plan()))['status'],
        'sufficient',
      );
      expect(
        () => QuantityPlanParser.decode('{"product":{}}'),
        throwsFormatException,
      );
    },
  );
}
