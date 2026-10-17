import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/main.dart';
import 'package:risparmiai/privacy/data/asset_privacy_repository.dart';
import 'package:risparmiai/privacy/domain/privacy_repository.dart';
import 'package:risparmiai/privacy/presentation/privacy_notice_gate.dart';
import 'package:risparmiai/privacy/presentation/privacy_policy_page.dart';

class MemoryPrivacy implements PrivacyRepository {
  bool viewed = false;
  bool failWrite = false;
  bool failRead = false;
  bool failLoad = false;
  int writes = 0;
  final languages = <String>[];
  @override
  Future<bool> hasViewedCurrentNotice() async {
    if (failRead) throw StateError('Read failed');
    return viewed;
  }

  @override
  Future<void> markCurrentNoticeViewed() async {
    if (failWrite) throw StateError('Write failed');
    writes++;
    viewed = true;
  }

  @override
  Future<String> loadNotice(String languageCode) async {
    if (failLoad) throw StateError('Load failed');
    languages.add(languageCode);
    return languageCode == 'it' ? '# Testo italiano' : '# English notice';
  }
}

Widget host(Widget child) => MaterialApp(
  locale: const Locale('it'),
  supportedLocales: const [Locale('it'), Locale('en')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: child,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'only current version skips notice and unrelated data is preserved',
    () async {
      SharedPreferences.setMockInitialValues({
        AssetPrivacyRepository.viewedVersionKey: 'previous-version',
        'verified_price_observations_v1': 'existing prices',
      });
      final repository = AssetPrivacyRepository();
      expect(await repository.hasViewedCurrentNotice(), isFalse);
      await repository.markCurrentNoticeViewed();
      expect(await AssetPrivacyRepository().hasViewedCurrentNotice(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('verified_price_observations_v1'),
        'existing prices',
      );
      for (final language in ['it', 'en']) {
        final document = await repository.loadNotice(language);
        expect(document, contains('RisparmiAi'));
        expect(document, contains(privacyNoticeVersion));
        expect(document, contains('OpenAI'));
        expect(document, contains('Gemini'));
        expect(document, contains('AdMob'));
        expect(document, isNot(contains('SpliGo')));
      }
    },
  );

  testWidgets(
    'notice precedes chat; full notice switches languages and remains reopenable',
    (tester) async {
      final repository = MemoryPrivacy();
      await tester.pumpWidget(
        MainApp(useMockData: true, privacyRepository: repository),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Invia'), findsNothing);
      // Default test locale is English, matching the selected app locale.
      await tester.tap(find.text('Read the full notice · IT / EN'));
      await tester.pumpAndSettle();
      expect(find.text('English notice'), findsOneWidget);
      await tester.tap(find.text('Italiano'));
      await tester.pumpAndSettle();
      expect(find.text('Testo italiano'), findsOneWidget);
      expect(repository.writes, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final continueButton = find.text("I've read it, continue");
      await tester.scrollUntilVisible(continueButton, 200);
      await tester.pumpAndSettle();
      await tester.tap(continueButton);
      await tester.pumpAndSettle();
      expect(repository.writes, 1);
      expect(find.byTooltip('Invia'), findsOneWidget);
      await tester.tap(find.byTooltip('Informativa privacy'));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyPolicyPage), findsOneWidget);
    },
  );

  testWidgets('failed acknowledgement blocks startup callbacks until retry', (
    tester,
  ) async {
    final repository = MemoryPrivacy()..failWrite = true;
    var initializations = 0;
    await tester.pumpWidget(
      host(
        PrivacyNoticeGate(
          repository: repository,
          onReady: () => initializations++,
          child: const Scaffold(body: Text('Chat pronta')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.text('Ho letto, continua');
    await tester.scrollUntilVisible(button, 200);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(initializations, 0);
    expect(find.text('Chat pronta'), findsNothing);
    expect(
      find.text('Impossibile salvare la presa visione. Riprova.'),
      findsOneWidget,
    );
    repository.failWrite = false;
    await tester.scrollUntilVisible(button, 200);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(initializations, 1);
    expect(find.text('Chat pronta'), findsOneWidget);
  });

  testWidgets('returning user skips notice without a new acknowledgement', (
    tester,
  ) async {
    final repository = MemoryPrivacy()..viewed = true;
    var initializations = 0;
    await tester.pumpWidget(
      host(
        PrivacyNoticeGate(
          repository: repository,
          onReady: () => initializations++,
          child: const Scaffold(body: Text('Chat pronta')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chat pronta'), findsOneWidget);
    expect(repository.writes, 0);
    expect(initializations, 1);
  });

  testWidgets(
    'failed version read shows notice and compact enlarged layout scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = MemoryPrivacy()..failRead = true;
      await tester.pumpWidget(
        host(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 600),
              textScaler: TextScaler.linear(1.6),
            ),
            child: PrivacyNoticeGate(
              repository: repository,
              child: const Text('Chat pronta'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('La tua privacy, in breve'), findsOneWidget);
      final button = find.text('Ho letto, continua');
      await tester.scrollUntilVisible(button, 200);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Chat pronta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('document load failure has a working retry', (tester) async {
    final repository = MemoryPrivacy()..failLoad = true;
    await tester.pumpWidget(host(PrivacyPolicyPage(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Caricamento non riuscito. Riprova'), findsOneWidget);
    repository.failLoad = false;
    await tester.tap(find.text('Caricamento non riuscito. Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Testo italiano'), findsOneWidget);
  });
}
