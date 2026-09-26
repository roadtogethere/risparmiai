import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/savings_checker/data/datasources/ai_response_parser.dart';
import 'package:risparmiai/savings_checker/data/datasources/ai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/category_reference_data_source.dart';
import 'package:risparmiai/savings_checker/data/datasources/category_reference_store.dart';
import 'package:risparmiai/savings_checker/data/models/category_reference_model.dart';
import 'package:risparmiai/savings_checker/data/models/product_analysis_model.dart';
import 'package:risparmiai/savings_checker/data/repositories/savings_repository_impl.dart';
import 'package:risparmiai/savings_checker/domain/entities/category_reference.dart';
import 'package:risparmiai/savings_checker/domain/entities/required_attribute.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'package:risparmiai/savings_checker/presentation/pages/savings_checker_page.dart';

const key = 'user_custom_categories';
// Explicit test fixture codes, not a production label-to-metric fallback.
String metricCode(String unit) =>
    const {
      'litro': 'liter',
      'lavaggio': 'wash',
      'rotolo': 'roll',
      'strappo': 'sheet',
      'kg': 'kilogram',
      'g': 'gram',
      'ml': 'milliliter',
      'capsula': 'capsule',
      'confezione': 'package',
      'pezzo': 'piece',
      'unità singola': 'piece',
      'other': 'piece',
      'ai proposed unit': 'liter',
    }[unit.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')] ??
    'unknown';
CategoryReferenceModel category(String unit) => CategoryReferenceModel(
  key: 'sample',
  displayName: 'Original category',
  primaryUnit: unit,
  canonicalMetric: metricCode(unit),
  averageUnitCost: 9,
  requiredAttributes: const [
    RequiredAttribute(key: 'quantity', label: 'Quantità'),
  ],
);

class Defaults extends CategoryReferenceDataSource {
  Defaults(this.categories);
  final List<CategoryReferenceModel> categories;
  @override
  Future<List<CategoryReferenceModel>> loadDefaultCategories() async =>
      categories;
}

Map<String, dynamic> payload() => {
  'product': {
    'category_key': 'toilet_paper',
    'brand': 'Example',
    'total_price': 6,
    'units_per_package': 12,
    'primary_unit_name': 'rotolo',
    'canonical_metric': 'roll',
    'specific_attributes': {'rolls_count': 12},
  },
  'category_match': {
    'category': {
      'key': 'toilet_paper',
      'display_name': 'Carta igienica',
      'primary_unit': 'strappo',
      'canonical_metric': 'sheet',
      'required_attributes': ['rolls_count', 'sheets_per_roll'],
    },
  },
};

class Client implements AiSavingsClient {
  @override
  Future<Map<String, dynamic>> analyzeProductWithCatalog(
    String prompt,
    String catalog,
  ) async => AiResponseParser.parseModelResponse(jsonEncode(payload()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final metric in ['litro', ' Litro ', 'LITRO']) {
    test('same metric after lexical normalization: $metric', () async {
      final store = CategoryReferenceStore(defaultDataSource: Defaults([]));
      await store.upsertCategoryWithObservedUnitCost(
        category('litro'),
        3,
        observationMetric: 'litro',
        observationCanonicalMetric: metricCode('litro'),
        observedAttributes: {'quantity': 1},
      );
      await store.upsertCategoryWithObservedUnitCost(
        category('AI proposed unit'),
        2,
        observationMetric: metric,
        observationCanonicalMetric: metricCode(metric),
        observedAttributes: {'quantity': 1},
      );
      final saved = (await store.loadCustomCategories()).single;
      expect(saved.entriesCount, 2);
      expect(saved.sumOfUnitCosts, 5);
      expect(saved.averageUnitCost, 2);
      expect(saved.averageOfAllEntries, 2.5);
      expect(saved.primaryUnit, 'litro');
    });
  }

  test(
    'internal whitespace normalization never rewrites stored labels',
    () async {
      final store = CategoryReferenceStore(defaultDataSource: Defaults([]));
      await store.upsertCategoryWithObservedUnitCost(
        category('unità  singola'),
        3,
        observationMetric: 'unità singola',
        observationCanonicalMetric: metricCode('unità singola'),
        observedAttributes: {'quantity': 1},
      );
      await store.upsertCategoryWithObservedUnitCost(
        category('other'),
        2,
        observationMetric: ' UNITÀ   SINGOLA ',
        observationCanonicalMetric: metricCode(' UNITÀ   SINGOLA '),
        observedAttributes: {'quantity': 1},
      );
      expect(
        (await store.loadCustomCategories()).single.primaryUnit,
        'unità  singola',
      );
    },
  );

  for (final pair in [
    ['litro', 'lavaggio'],
    ['lavaggio', 'litro'],
    ['rotolo', 'strappo'],
    ['kg', 'g'],
    ['ml', 'litro'],
    ['capsula', 'lavaggio'],
    ['confezione', 'pezzo'],
  ]) {
    test(
      'incompatible ${pair[0]} / ${pair[1]} preserves complete archive',
      () async {
        final store = CategoryReferenceStore(defaultDataSource: Defaults([]));
        await store.upsertCategoryWithObservedUnitCost(
          category(pair[0]),
          3,
          observationMetric: pair[0],
          observationCanonicalMetric: metricCode(pair[0]),
          observedAttributes: {'quantity': 1},
        );
        final prefs = await SharedPreferences.getInstance();
        final before = prefs.getString(key);
        await expectLater(
          store.upsertCategoryWithObservedUnitCost(
            category(
              pair[1],
            ).copyWith(displayName: 'AI replacement', requiredAttributes: []),
            1,
            observationMetric: pair[1],
            observationCanonicalMetric: metricCode(pair[1]),
            observedAttributes: {'quantity': 1},
          ),
          throwsA(isA<UnitMetricMismatch>()),
        );
        expect(prefs.getString(key), before);
        final saved = (await store.loadCustomCategories()).single;
        expect(saved.primaryUnit, pair[0]);
        expect(saved.entriesCount, 1);
        expect(saved.sumOfUnitCosts, 3);
        expect(saved.averageUnitCost, 3);
      },
    );
  }

  test(
    'default protects first observation; matching observation keeps its definition',
    () async {
      final store = CategoryReferenceStore(
        defaultDataSource: Defaults([category('strappo')]),
      );
      await expectLater(
        store.upsertCategoryWithObservedUnitCost(
          category('rotolo'),
          1,
          observationMetric: 'rotolo',
          observationCanonicalMetric: metricCode('rotolo'),
          observedAttributes: {'quantity': 1},
        ),
        throwsA(isA<UnitMetricMismatch>()),
      );
      expect((await SharedPreferences.getInstance()).getString(key), isNull);
      await store.upsertCategoryWithObservedUnitCost(
        category(
          'strappo',
        ).copyWith(displayName: 'AI name', requiredAttributes: []),
        2,
        observationMetric: 'strappo',
        observationCanonicalMetric: metricCode('strappo'),
        observedAttributes: {'quantity': 1},
      );
      final saved = (await store.loadCustomCategories()).single;
      expect(saved.displayName, 'Original category');
      expect(saved.requiredAttributes.single.key, 'quantity');
      expect(saved.entriesCount, 1);
      expect(saved.sumOfUnitCosts, 2);
      expect(saved.averageUnitCost, 2);
    },
  );

  test(
    'unknown category with explicit valid metric can still be created',
    () async {
      final store = CategoryReferenceStore(defaultDataSource: Defaults([]));
      await store.upsertCategoryWithObservedUnitCost(
        category('pezzo'),
        2,
        observationMetric: 'pezzo',
        observationCanonicalMetric: metricCode('pezzo'),
        observedAttributes: {'quantity': 1},
      );
      expect((await store.loadCustomCategories()).single.primaryUnit, 'pezzo');
    },
  );

  for (final metric in ['', '   ', '\t\n']) {
    test('empty metric is never persisted: ${jsonEncode(metric)}', () async {
      final store = CategoryReferenceStore(defaultDataSource: Defaults([]));
      await expectLater(
        store.upsertCategoryWithObservedUnitCost(
          category('pezzo'),
          2,
          observationMetric: metric,
          observationCanonicalMetric: metricCode(metric),
          observedAttributes: {'quantity': 1},
        ),
        throwsFormatException,
      );
      expect((await SharedPreferences.getInstance()).getString(key), isNull);
    });
  }

  test('unknown category cannot silently relabel the observation', () async {
    final store = CategoryReferenceStore(defaultDataSource: Defaults([]));
    await expectLater(
      store.upsertCategoryWithObservedUnitCost(
        category('strappo'),
        2,
        observationMetric: 'rotolo',
        observationCanonicalMetric: metricCode('rotolo'),
        observedAttributes: {'quantity': 1},
      ),
      throwsA(isA<UnitMetricMismatch>()),
    );
    expect((await SharedPreferences.getInstance()).getString(key), isNull);
  });

  test(
    'competing first observations are checked inside the write queue',
    () async {
      final first = CategoryReferenceStore(defaultDataSource: Defaults([]));
      final second = CategoryReferenceStore(defaultDataSource: Defaults([]));
      final a = first.upsertCategoryWithObservedUnitCost(
        category('litro'),
        3,
        observationMetric: 'litro',
        observationCanonicalMetric: metricCode('litro'),
        observedAttributes: {'quantity': 1},
      );
      final b = expectLater(
        second.upsertCategoryWithObservedUnitCost(
          category('lavaggio'),
          2,
          observationMetric: 'lavaggio',
          observationCanonicalMetric: metricCode('lavaggio'),
          observedAttributes: {'quantity': 1},
        ),
        throwsA(isA<UnitMetricMismatch>()),
      );
      await Future.wait([a, b]);
      final saved = (await first.loadCustomCategories()).single;
      expect(saved.entriesCount, 1);
      expect(saved.primaryUnit, 'litro');
    },
  );

  test(
    'legacy custom definition remains authoritative and is not migrated',
    () async {
      final legacy = category('lavaggio').toJson()
        ..remove('canonical_metric')
        ..remove('sum_of_unit_costs')
        ..remove('entries_count');
      final raw = jsonEncode([legacy]);
      SharedPreferences.setMockInitialValues({key: raw});
      final store = CategoryReferenceStore(
        defaultDataSource: Defaults([category('litro')]),
      );
      await expectLater(
        store.upsertCategoryWithObservedUnitCost(
          category('litro'),
          2,
          observationMetric: 'litro',
          observationCanonicalMetric: metricCode('litro'),
          observedAttributes: {'quantity': 1},
        ),
        throwsA(isA<UnitMetricMismatch>()),
      );
      expect((await SharedPreferences.getInstance()).getString(key), raw);
    },
  );

  test('parser preserves 12 rolls instead of relabeling them as sheets', () {
    final parsed = AiResponseParser.parseModelResponse(jsonEncode(payload()));
    expect(parsed['product']['units_per_package'], 12);
    expect(parsed['product']['primary_unit_name'], 'rotolo');
    expect(parsed['category_match']['category']['primary_unit'], 'strappo');
  });

  test(
    'legacy product mapper does not infer sheets from name or attributes',
    () {
      for (final unit in ['rotolo', 'confezione']) {
        final product = ProductAnalysisModel.fromJson({
          'productName': 'Carta igienica',
          'totalPrice': 6,
          'totalUnitsCount': 12,
          'primaryUnitName': unit,
          'specificAttributes': {'sheets_per_roll': 500},
        });
        expect(product.primaryUnitName, unit);
        expect(product.totalUnitsCount, 12);
      }
    },
  );

  testWidgets(
    'chat explains mismatch without provider error, demo or convenience card',
    (tester) async {
      final notifier = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(aiClient: Client()),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: notifier,
          child: const MaterialApp(home: SavingsCheckerPage()),
        ),
      );
      await tester.runAsync(
        () => notifier.analyzeShoppingPrompt('Carta igienica 12 rotoli 6 euro'),
      );
      await tester.pump();
      expect(find.textContaining('non confrontabili'), findsOneWidget);
      expect(find.text('Migliore convenienza'), findsNothing);
      expect(find.textContaining('Analisi non riuscita'), findsNothing);
      expect(notifier.analyzedProducts, isEmpty);
      expect((await SharedPreferences.getInstance()).getString(key), isNull);
      await tester.pumpWidget(const SizedBox());
      notifier.dispose();
    },
  );
}
