import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/fork/launch/quick_actions.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => _ImperialOff();
}

class _ImperialOff extends Fake implements ConfigEntity {
  @override
  bool get usesImperialFoodUnits => false;
}

class _Ai extends Fake implements AiCredentialStorage {
  final bool on;
  _Ai(this.on);

  @override
  Future<bool> isEnabled() async => on;
}

void main() {
  tearDown(GetIt.instance.reset);

  Future<List<String>> pump(WidgetTester tester, {bool ai = false}) async {
    final opened = <String>[];
    GetIt.instance
      ..registerSingleton<GetConfigUsecase>(_Config())
      ..registerSingleton<AiCredentialStorage>(_Ai(ai));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        onGenerateRoute: (settings) {
          opened.add(settings.name!);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: QuickActions()),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    opened.clear();
    return opened;
  }

  testWidgets('no Photo log while AI meal assistance is off', (tester) async {
    await pump(tester);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Weigh in'), findsOneWidget);
    expect(find.text('Photo log'), findsNothing);
  });

  testWidgets('Photo log while AI meal assistance is on', (tester) async {
    await pump(tester, ai: true);
    expect(find.text('Photo log'), findsOneWidget);
  });

  testWidgets('each opens straight away, without the + sheet', (tester) async {
    final opened = await pump(tester);
    await tester.tap(find.bySemanticsIdentifier('home-quick-scan'));
    await tester.pump();
    await tester.pump();
    expect(opened, [NavigationOptions.scannerRoute]);
  });

  testWidgets('search opens the food search', (tester) async {
    final opened = await pump(tester);
    await tester.tap(find.bySemanticsIdentifier('home-quick-search'));
    await tester.pump();
    await tester.pump();
    expect(opened, [NavigationOptions.addMealRoute]);
  });

  testWidgets('the meal plan is a tile away', (tester) async {
    await pump(tester);
    expect(find.bySemanticsIdentifier('home-quick-meal-plan'), findsOneWidget);
    expect(find.text('Meal plan'), findsOneWidget);
  });

  testWidgets('at 200% text the tiles fit', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pump(tester, ai: true);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 780),
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: const Scaffold(body: QuickActions()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
