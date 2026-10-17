import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:risparmiai/savings_checker/data/datasources/verified_price_store.dart';
import 'price_history_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  const store = VerifiedPriceStore();
  late Map<String, Object> disk;
  late String failure;
  late int writes;
  setUp(() {
    disk = {};
    failure = '';
    writes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAll') return Map<String, Object>.from(disk);
          if (call.method == 'setString') {
            writes++;
            if (failure == 'false') return false;
            if (failure == 'throw') {
              throw PlatformException(code: 'write_failed');
            }
            final args = call.arguments as Map;
            disk[args['key'] as String] = args['value'] as String;
            if (failure == 'after_write') {
              throw PlatformException(code: 'ack_failed');
            }
            return true;
          }
          throw StateError('Unexpected persistence call');
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  for (final mode in ['false', 'throw']) {
    test(
      'write failure $mode preserves disk; retry reloads cache and writes once',
      () async {
        final first = await fixture.priced(2);
        await store.save(first);
        final before = Map<String, Object>.from(disk);
        final second = await fixture.priced(3);
        failure = mode;
        await expectLater(
          store.save(second),
          throwsA(anyOf(isA<StateError>(), isA<PlatformException>())),
        );
        expect(disk, before);
        expect(await store.read(), hasLength(1));
        failure = '';
        await store.save(second);
        expect(await store.read(), hasLength(2));
        final priorWrites = writes;
        await store.save(second);
        expect(writes, priorWrites);
      },
    );
  }

  test('lost write acknowledgement retries without a duplicate', () async {
    final price = await fixture.priced(2);
    failure = 'after_write';
    await expectLater(store.save(price), throwsA(isA<Exception>()));
    failure = '';
    final result = await const VerifiedPriceStore().save(price);
    expect(result.alreadySaved, isTrue);
    expect(await store.read(), hasLength(1));
    expect(writes, 1);
  });

  for (final mode in ['false', 'throw']) {
    test(
      'delete and undo write failures ($mode) preserve disk and can retry',
      () async {
        final price = await fixture.priced(0.1412);
        await store.save(price);
        final before = Map<String, Object>.from(disk);
        failure = mode;
        await expectLater(
          store.delete(price.observationId),
          throwsA(anyOf(isA<StateError>(), isA<PlatformException>())),
        );
        expect(disk, before);
        expect(await store.read(), hasLength(1));
        failure = '';
        final removed = await store.delete(price.observationId);
        final empty = Map<String, Object>.from(disk);
        failure = mode;
        await expectLater(
          store.restore(removed!),
          throwsA(anyOf(isA<StateError>(), isA<PlatformException>())),
        );
        expect(disk, empty);
        expect(await store.read(), isEmpty);
        failure = '';
        await store.restore(removed);
        expect(await store.read(), hasLength(1));
      },
    );
  }

  test(
    'lost delete acknowledgement still returns the record for undo',
    () async {
      final price = await fixture.priced(0.1412);
      await store.save(price);
      failure = 'after_write';
      final removed = await store.delete(price.observationId);
      expect(removed!.price.observationId, price.observationId);
      failure = '';
      expect(await store.read(), isEmpty);
      await store.restore(removed);
      expect(await store.read(), hasLength(1));
    },
  );
}
