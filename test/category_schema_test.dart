import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
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

const storageKey = 'user_custom_categories';
const known = CategoryReferenceModel(
  key: 'toilet_paper',
  displayName: 'Carta igienica',
  primaryUnit: 'strappo',
  canonicalMetric: 'sheet',
  averageUnitCost: 0.01,
  requiredAttributes: [
    RequiredAttribute(key: 'rolls_count', label: 'Rotoli'),
    RequiredAttribute(key: 'sheets_per_roll', label: 'Fogli per rotolo'),
  ],
);
const values = {'rolls_count': 12, 'sheets_per_roll': 100};

Map<String, dynamic> response() => {
  'product': <String, dynamic>{
    'category_key': known.key,
    'canonical_metric': 'sheet',
    'brand': 'Marca',
    'primary_unit_name': 'strappo',
    'total_price': 6,
    'units_per_package': 12,
    'sub_units_per_package': 100,
    'specific_attributes': <String, dynamic>{...values},
  },
  'category_match': <String, dynamic>{'category': known.toJson()},
};

class Defaults extends CategoryReferenceDataSource {
  Defaults(this.items);
  final List<CategoryReferenceModel> items;
  @override
  Future<List<CategoryReferenceModel>> loadDefaultCategories() async => items;
}

class Client implements AiSavingsClient {
  Client(this.data);
  final Map<String, dynamic> data;
  String? catalog;
  @override
  Future<Map<String, dynamic>> analyzeProductWithCatalog(
    String prompt,
    String catalogJson,
  ) async {
    catalog = catalogJson;
    return data;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CategoryReferenceStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = CategoryReferenceStore(defaultDataSource: Defaults([known]));
  });
  Future<void> seed() => store.upsertCategoryWithObservedUnitCost(
    known,
    0.01,
    observationMetric: 'strappo',
    observationCanonicalMetric: 'sheet',
    observedAttributes: values,
  );
  SavingsRepositoryImpl repository(Map<String, dynamic> data) =>
      SavingsRepositoryImpl(aiClient: Client(data), categoryStore: store);
  Future<String?> raw() async =>
      (await SharedPreferences.getInstance()).getString(storageKey);

  test('known schema is reused in catalog, result and persistence', () async {
    final client = Client(response());
    final products = await SavingsRepositoryImpl(
      aiClient: client,
      categoryStore: store,
    ).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro');
    final product = products.single;
    expect(product.categoryKey, known.key);
    expect(product.canonicalMetric, 'sheet');
    expect(product.primaryUnitName, 'strappo');
    expect(product.productName, known.displayName);
    expect(product.unitCost, 0.005);
    final saved = (await store.loadCustomCategories()).single;
    expect(saved.canonicalMetric, 'sheet');
    expect(saved.requiredAttributes.map((a) => a.key), [
      'rolls_count',
      'sheets_per_roll',
    ]);
    expect(
      jsonDecode(client.catalog!)['categories'][0]['canonical_metric'],
      'sheet',
    );
    expect(
      CategoryReferenceModel.fromJson(saved.toJson()).canonicalMetric,
      'sheet',
    );
    expect(CategoryReference.fromJson(saved.toJson()).canonicalMetric, 'sheet');
    expect(CategoryReferenceModel.fromEntity(saved).canonicalMetric, 'sheet');
  });

  for (final side in ['product', 'category']) {
    test('canonical divergence on $side never changes the archive', () async {
      await seed();
      final before = await raw();
      final data = response();
      if (side == 'product') {
        data['product']['canonical_metric'] = 'roll';
      } else {
        data['category_match']['category']['canonical_metric'] = 'roll';
      }
      await expectLater(
        repository(data).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro'),
        throwsA(
          anyOf(isA<UnitMetricMismatch>(), isA<CategorySchemaMismatch>()),
        ),
      );
      expect(await raw(), before);
    });
  }

  test(
    'store also rejects conflicting canonical schema from other callers',
    () async {
      await seed();
      final before = await raw();
      await expectLater(
        store.upsertCategoryWithObservedUnitCost(
          known.copyWith(canonicalMetric: 'roll'),
          1,
          observationMetric: 'strappo',
          observationCanonicalMetric: 'sheet',
          observedAttributes: values,
        ),
        throwsA(isA<CategorySchemaMismatch>()),
      );
      expect(await raw(), before);
    },
  );

  test(
    'changed required attributes are reported but local requirements remain authoritative',
    () async {
      final data = response();
      data['category_match']['category']['required_attributes'] = [
        {'key': 'invented', 'label': 'Inventato'},
      ];
      final product = (await repository(
        data,
      ).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro')).single;
      expect(product.analysisSummary, contains('schema locale'));
      expect(
        (await store.loadCustomCategories()).single.requiredAttributes.map(
          (a) => a.key,
        ),
        ['rolls_count', 'sheets_per_roll'],
      );
    },
  );

  test(
    'attribute label divergence is reported and preserves local labels',
    () async {
      final data = response();
      data['category_match']['category']['required_attributes'][0]['label'] =
          'Rolls';
      final product = (await repository(
        data,
      ).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro')).single;
      expect(product.analysisSummary, contains('schema locale'));
      expect(
        (await store.loadCustomCategories())
            .single
            .requiredAttributes
            .first
            .label,
        'Rotoli',
      );
    },
  );

  for (final missingValue in [null, '']) {
    test(
      'missing local attribute ($missingValue) is not invented or persisted',
      () async {
        await seed();
        final before = await raw();
        final data = response();
        data['product']['specific_attributes']['sheets_per_roll'] =
            missingValue;
        data['category_match']['category']['required_attributes'] = [];
        await expectLater(
          repository(
            data,
          ).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro'),
          throwsA(isA<CategorySchemaMismatch>()),
        );
        expect(await raw(), before);
      },
    );
  }

  test('labels do not determine key or canonical metric', () async {
    final data = response();
    data['product']['primary_unit_name'] = 'sheet';
    data['category_match']['category']['primary_unit'] = 'foglio';
    data['category_match']['category']['display_name'] = 'Paper';
    final product = (await repository(
      data,
    ).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro')).single;
    expect(product.categoryKey, known.key);
    expect(product.canonicalMetric, 'sheet');
    expect(product.primaryUnitName, 'strappo');
    final saved = (await store.loadCustomCategories()).single;
    expect(saved.displayName, known.displayName);
    expect(saved.primaryUnit, known.primaryUnit);
  });

  test(
    'valid genuinely new schema is saved and reused on the next request',
    () async {
      store = CategoryReferenceStore(defaultDataSource: Defaults([]));
      final data = response();
      data['product']['category_key'] = 'new_paper';
      data['category_match']['category']['key'] = 'new_paper';
      await repository(
        data,
      ).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro');
      data['category_match']['category']['display_name'] = 'Changed by AI';
      final result = (await repository(
        data,
      ).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro')).single;
      expect(result.productName, known.displayName);
      expect((await store.loadCustomCategories()).single.entriesCount, 2);
    },
  );

  for (final field in [
    'canonical_metric',
    'primary_unit',
    'display_name',
    'required_attributes',
  ]) {
    test('new schema missing $field cannot persist', () async {
      store = CategoryReferenceStore(defaultDataSource: Defaults([]));
      final data = response();
      (data['category_match']['category'] as Map).remove(field);
      await expectLater(
        repository(data).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro'),
        throwsFormatException,
      );
      expect(await raw(), isNull);
    });
  }
  for (final metric in ['', ' ', 'Sheet', 'per sheet']) {
    test(
      'new metric code must be nonempty machine-readable: $metric',
      () async {
        store = CategoryReferenceStore(defaultDataSource: Defaults([]));
        final data = response();
        data['category_match']['category']['canonical_metric'] = metric;
        data['product']['canonical_metric'] = metric;
        await expectLater(
          repository(
            data,
          ).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro'),
          throwsFormatException,
        );
        expect(await raw(), isNull);
      },
    );
  }
  for (final definitions in [
    [
      {'key': '', 'label': 'Missing key'},
    ],
    [
      {'key': 'rolls_count', 'label': ''},
    ],
    [
      {'key': 'rolls_count', 'label': 'A'},
      {'key': 'rolls_count', 'label': 'B'},
    ],
    [42],
  ]) {
    test(
      'invalid required attribute definitions cannot create a schema: $definitions',
      () async {
        store = CategoryReferenceStore(defaultDataSource: Defaults([]));
        final data = response();
        data['category_match']['category']['required_attributes'] = definitions;
        await expectLater(
          repository(
            data,
          ).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro'),
          throwsFormatException,
        );
        expect(await raw(), isNull);
      },
    );
  }

  test(
    'conflicting product/category keys are unresolved instead of merged',
    () async {
      final data = response();
      data['product']['category_key'] = 'other';
      await expectLater(
        repository(data).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro'),
        throwsA(isA<CategorySchemaMismatch>()),
      );
      expect(await raw(), isNull);
    },
  );

  test(
    'legacy custom wins over modern default without inferred canonical metric',
    () async {
      final legacy = known.toJson()..remove('canonical_metric');
      legacy['entries_count'] = 2;
      legacy['sum_of_unit_costs'] = 0.03;
      final original = jsonEncode([legacy]);
      SharedPreferences.setMockInitialValues({storageKey: original});
      final loaded = (await store.loadCategories()).single;
      expect(loaded.canonicalMetric, isNull);
      expect(await raw(), original);
      final data = response();
      (data['product'] as Map).remove('canonical_metric');
      (data['category_match']['category'] as Map).remove('canonical_metric');
      final result = (await repository(
        data,
      ).analyzeProducts(userPrompt: 'Carta 12 rotoli 6 euro')).single;
      expect(result.canonicalMetric, isNull);
      expect(result.analysisSummary, contains('non verificata'));
      final saved = (await store.loadCustomCategories()).single;
      expect(saved.entriesCount, 3);
      expect(saved.sumOfUnitCosts, closeTo(0.035, 1e-12));
      expect(saved.toJson().containsKey('canonical_metric'), isFalse);
    },
  );

  test('legacy still rejects differing label metrics', () async {
    final legacy = known.toJson()..remove('canonical_metric');
    final original = jsonEncode([legacy]);
    SharedPreferences.setMockInitialValues({storageKey: original});
    await expectLater(
      store.upsertCategoryWithObservedUnitCost(
        known,
        0.1,
        observationMetric: 'rotolo',
        observationCanonicalMetric: 'sheet',
        observedAttributes: values,
      ),
      throwsA(isA<UnitMetricMismatch>()),
    );
    expect(await raw(), original);
  });

  test(
    'modern record with malformed canonical metric fails closed on read',
    () async {
      final broken = known.toJson()..['canonical_metric'] = '';
      final original = jsonEncode([broken]);
      SharedPreferences.setMockInitialValues({storageKey: original});
      await expectLater(store.loadCustomCategories(), throwsFormatException);
      expect(await raw(), original);
    },
  );

  test(
    'AI parser preserves distinct observation and category canonical identifiers',
    () {
      final data = response();
      data['product']['canonical_metric'] = 'roll';
      final parsed = AiResponseParser.parseModelResponse(jsonEncode(data));
      expect(parsed['product']['canonical_metric'], 'roll');
      expect(parsed['category_match']['category']['canonical_metric'], 'sheet');
    },
  );

  test(
    'product copy and JSON mapping retain category key and canonical metric',
    () {
      final product = ProductAnalysisModel.fromJson({
        'productName': 'Carta',
        'totalPrice': 6,
        'totalUnitsCount': 1200,
        'primaryUnitName': 'strappo',
        'categoryKey': known.key,
        'canonicalMetric': 'sheet',
      });
      expect(
        product.copyWith(primaryUnitName: 'foglio').canonicalMetric,
        'sheet',
      );
      final restored = ProductAnalysisModel.fromJson(product.toJson());
      expect(restored.categoryKey, known.key);
      expect(restored.canonicalMetric, 'sheet');
    },
  );
}
