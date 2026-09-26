import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:risparmiai/savings_checker/data/datasources/ai_response_parser.dart';
import 'package:risparmiai/savings_checker/data/datasources/ai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/category_reference_data_source.dart';
import 'package:risparmiai/savings_checker/data/datasources/category_reference_store.dart';
import 'package:risparmiai/savings_checker/data/matchers/category_matcher.dart';
import 'package:risparmiai/savings_checker/data/models/category_reference_model.dart';
import 'package:risparmiai/savings_checker/data/repositories/savings_repository_impl.dart';
import 'package:risparmiai/savings_checker/domain/entities/required_attribute.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';

const archiveKey = 'flutter.user_custom_categories';
const channel = MethodChannel('plugins.flutter.io/shared_preferences');
CategoryReferenceModel category([String key = 'sample']) =>
    CategoryReferenceModel(
      key: key,
      displayName: 'Sample',
      primaryUnit: 'unit',
      averageUnitCost: 2,
      requiredAttributes: const [
        RequiredAttribute(key: 'roll_count', label: 'Numero rotoli'),
      ],
    );
Map<String, dynamic> payload() => {
  'product': <String, dynamic>{
    'category_key': 'sample',
    'brand': 'Example',
    'total_price': 10,
    'units_per_package': 2,
    'primary_unit_name': 'unit',
    'specific_attributes': <String, dynamic>{},
  },
  'category_match': {'category': category().toJson()},
};

class Client implements AiSavingsClient {
  Client(this.response);
  final Future<Map<String, dynamic>> Function() response;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> analyzeProductWithCatalog(
    String prompt,
    String catalog,
  ) {
    calls++;
    return response();
  }
}

class Defaults extends CategoryReferenceDataSource {
  @override
  Future<List<CategoryReferenceModel>> loadDefaultCategories() async => [
    category(),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Object> disk;
  late int writes;
  late bool failWrite;
  late bool throwWrite;
  Completer<void>? started;
  Completer<void>? release;
  final store = CategoryReferenceStore(defaultDataSource: Defaults());
  SavingsRepositoryImpl repository(Client client) =>
      SavingsRepositoryImpl(aiClient: client, categoryStore: store);
  setUp(() {
    disk = {};
    writes = 0;
    failWrite = false;
    throwWrite = false;
    started = null;
    release = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAll') return Map<String, Object>.from(disk);
          if (call.method == 'setString') {
            writes++;
            if (started != null && !started!.isCompleted) started!.complete();
            if (release != null) await release!.future;
            if (throwWrite) throw PlatformException(code: 'write_failed');
            if (failWrite) return false;
            final args = call.arguments as Map;
            disk[args['key'] as String] = args['value'] as String;
            return true;
          }
          throw StateError('Unexpected preference method');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('valid direct and multiplied quantities retain the formula', () async {
    final data = payload();
    final repo = repository(Client(() async => data));
    expect(
      (await repo.analyzeProducts(
        userPrompt: 'Prodotto 10 euro',
      )).single.unitCost,
      5,
    );
    data['product']['sub_units_per_package'] = '2,5';
    expect(
      (await repo.analyzeProducts(
        userPrompt: 'Prodotto 10 euro',
      )).single.unitCost,
      2,
    );
    final saved = (await store.loadCustomCategories()).single;
    expect(saved.entriesCount, 2);
    expect(saved.sumOfUnitCosts, 7);
    expect(saved.averageUnitCost, 2);
  });
  for (final field in [
    'units_per_package',
    'sub_units_per_package',
    'total_price',
  ]) {
    final values = <Object?>[
      null,
      '',
      'abc',
      true,
      double.nan,
      double.infinity,
      -1,
    ];
    if (field != 'total_price') values.add(0);
    if (field == 'sub_units_per_package') values.remove(null);
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      test('invalid $field case $i never mutates history', () async {
        await store.upsertCategoryWithObservedUnitCost(
          category(),
          3,
          observationMetric: 'unit',
        );
        final original = disk[archiveKey];
        final before = writes;
        final data = payload();
        data['product'][field] = value;
        await expectLater(
          repository(
            Client(() async => data),
          ).analyzeProducts(userPrompt: 'Prodotto 10 euro'),
          throwsFormatException,
        );
        expect(disk[archiveKey], original);
        expect(writes, before);
      });
    }
  }
  for (final field in [
    'units_per_package',
    'total_price',
    'primary_unit_name',
    'category_key',
  ]) {
    test('missing $field never persists', () async {
      final data = payload();
      (data['product'] as Map).remove(field);
      await expectLater(
        repository(
          Client(() async => data),
        ).analyzeProducts(userPrompt: 'Prodotto 10 euro'),
        throwsFormatException,
      );
      expect(writes, 0);
      expect(disk, isEmpty);
    });
  }
  test('zero price remains analyzable without updating aggregates', () async {
    final data = payload();
    data['product']['total_price'] = 0;
    expect(
      (await repository(
        Client(() async => data),
      ).analyzeProducts(userPrompt: 'Prodotto 0 euro')).single.unitCost,
      0,
    );
    expect(writes, 0);
  });
  test('numeric overflow and underflow cannot persist', () async {
    for (final values in [
      [10.0, 1e308, 1e308],
      [1e308, 1e-308, 1.0],
      [1e-308, 1e308, 1.0],
    ]) {
      final data = payload();
      data['product']['total_price'] = values[0];
      data['product']['units_per_package'] = values[1];
      data['product']['sub_units_per_package'] = values[2];
      await expectLater(
        repository(
          Client(() async => data),
        ).analyzeProducts(userPrompt: 'Prodotto 10 euro'),
        throwsFormatException,
      );
    }
    expect(writes, 0);
  });
  test('explicit demo never calls AI or persists', () async {
    final client = Client(() => throw StateError('must not call'));
    expect(
      await SavingsRepositoryImpl(
        useMockData: true,
        aiClient: client,
        categoryStore: store,
      ).analyzeProducts(userPrompt: 'Pastiglie lavastoviglie 14 euro'),
      isNotEmpty,
    );
    expect(client.calls, 0);
    expect(writes, 0);
  });
  test('missing provider is not demo', () async {
    await expectLater(
      SavingsRepositoryImpl(
        categoryStore: store,
      ).analyzeProducts(userPrompt: 'Prodotto 10 euro'),
      throwsStateError,
    );
    expect(writes, 0);
  });
  for (final error in [
    StateError('HTTP error'),
    Exception('transport error'),
    const FormatException('bad JSON'),
  ]) {
    test('provider/parser error $error propagates without mock', () async {
      await expectLater(
        repository(
          Client(() => Future.error(error)),
        ).analyzeProducts(userPrompt: 'Prodotto 10 euro'),
        throwsA(same(error)),
      );
      expect(writes, 0);
    });
  }
  test('actual parser failure is not demo', () async {
    await expectLater(
      repository(
        Client(() async => AiResponseParser.parseModelResponse('not json')),
      ).analyzeProducts(userPrompt: 'Prodotto 10 euro'),
      throwsFormatException,
    );
    expect(writes, 0);
  });
  test('missing archive and empty list allow upsert', () async {
    expect(await store.loadCustomCategories(), isEmpty);
    disk[archiveKey] = '[]';
    await store.upsertCategoryWithObservedUnitCost(
      category(),
      3,
      observationMetric: 'unit',
    );
    expect((await store.loadCustomCategories()).single.entriesCount, 1);
  });
  for (final corrupt in [
    '{',
    '',
    '{}',
    '[null]',
    '[{}]',
    '{"categories": []}',
  ]) {
    test('corrupt archive $corrupt stays untouched', () async {
      disk[archiveKey] = corrupt;
      await expectLater(
        store.upsertCategoryWithObservedUnitCost(
          category(),
          3,
          observationMetric: 'unit',
        ),
        throwsFormatException,
      );
      expect(disk[archiveKey], corrupt);
      expect(writes, 0);
    });
  }
  test('legacy schema is readable without rewriting aggregates', () async {
    final entry = category().toJson()
      ..remove('sum_of_unit_costs')
      ..remove('entries_count');
    entry['required_attributes'] = ['legacy_attribute'];
    disk[archiveKey] = jsonEncode([entry]);
    final original = disk[archiveKey];
    expect(
      (await store.loadCustomCategories()).single.requiredAttributes.single.key,
      'legacy_attribute',
    );
    expect(disk[archiveKey], original);
    expect(writes, 0);
  });
  test('invalid aggregate is not silently reset', () async {
    final entry = category().toJson()..['sum_of_unit_costs'] = 'broken';
    disk[archiveKey] = jsonEncode([entry]);
    final original = disk[archiveKey];
    await expectLater(
      store.upsertCategoryWithObservedUnitCost(
        category(),
        3,
        observationMetric: 'unit',
      ),
      throwsFormatException,
    );
    expect(disk[archiveKey], original);
    expect(writes, 0);
  });
  for (final platformError in [false, true]) {
    test(
      'write failure $platformError propagates and queue/cache recover',
      () async {
        await store.upsertCategoryWithObservedUnitCost(
          category(),
          3,
          observationMetric: 'unit',
        );
        final original = disk[archiveKey];
        failWrite = !platformError;
        throwWrite = platformError;
        await expectLater(
          repository(
            Client(() async => payload()),
          ).analyzeProducts(userPrompt: 'Prodotto 10 euro'),
          throwsA(platformError ? isA<PlatformException>() : isA<StateError>()),
        );
        expect(disk[archiveKey], original);
        failWrite = false;
        throwWrite = false;
        await store.upsertCategoryWithObservedUnitCost(
          category(),
          2,
          observationMetric: 'unit',
        );
        final saved = (await store.loadCustomCategories()).single;
        expect(saved.entriesCount, 2);
        expect(saved.sumOfUnitCosts, 5);
      },
    );
  }
  test('concurrent upserts across instances preserve every update', () async {
    started = Completer<void>();
    release = Completer<void>();
    final first = store.upsertCategoryWithObservedUnitCost(
      category(),
      3,
      observationMetric: 'unit',
    );
    await started!.future;
    final other = CategoryReferenceStore(defaultDataSource: Defaults());
    final second = other.upsertCategoryWithObservedUnitCost(
      category(),
      2,
      observationMetric: 'unit',
    );
    final third = other.upsertCategoryWithObservedUnitCost(
      category('other'),
      7,
      observationMetric: 'unit',
    );
    await Future<void>.delayed(Duration.zero);
    expect(writes, 1);
    release!.complete();
    await Future.wait([first, second, third]);
    final saved = await store.loadCustomCategories();
    expect(saved.length, 2);
    final sample = saved.firstWhere((c) => c.key == 'sample');
    expect(sample.entriesCount, 2);
    expect(sample.sumOfUnitCosts, 5);
    expect(sample.averageUnitCost, 2);
  });
  test('delete waits for the in-flight upsert', () async {
    started = Completer<void>();
    release = Completer<void>();
    final first = store.upsertCategoryWithObservedUnitCost(
      category(),
      3,
      observationMetric: 'unit',
    );
    await started!.future;
    final deletion = store.removeCategory('sample');
    release!.complete();
    await Future.wait([first, deletion]);
    expect(await store.loadCustomCategories(), isEmpty);
  });
  test('notifier blocks double analysis and reports error', () async {
    final pending = Completer<Map<String, dynamic>>();
    final client = Client(() => pending.future);
    final notifier = SavingsChatNotifier(repository: repository(client));
    final first = notifier.analyzeShoppingPrompt('Prodotto 10 euro');
    expect(notifier.isLoading, isTrue);
    await notifier.analyzeShoppingPrompt('Prodotto 20 euro');
    // Let the first request reach the provider before completing its future.
    while (client.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    pending.completeError(StateError('unavailable'));
    await first;
    expect(client.calls, 1);
    expect(notifier.isLoading, isFalse);
    expect(notifier.errorMessage, contains('Analisi non riuscita'));
    expect(notifier.analyzedProducts, isEmpty);
    notifier.dispose();
  });
  test('formatter preserves integer zeros and marks non-finite values', () {
    for (final entry in {
      10.0: '10',
      10.50: '10.5',
      1.00: '1',
      0.00185: '0.00185',
      100.0: '100',
    }.entries) {
      expect(SavingsChatNotifier.formatUnitCost(entry.key), entry.value);
    }
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(SavingsChatNotifier.formatUnitCost(value), 'N/D');
    }
  });
  test('matcher accepts attribute key and label', () async {
    final matcher = CategoryMatcher(dataSource: Defaults());
    for (final input in ['roll_count', 'Numero rotoli']) {
      expect((await matcher.match(input)).defaultCategory?.key, 'sample');
    }
  });
}
