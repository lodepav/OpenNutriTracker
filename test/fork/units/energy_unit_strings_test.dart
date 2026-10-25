import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/daily_kcal_overview.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

Widget _app(bool kj, Widget child, {Locale locale = const Locale('en')}) =>
    ChangeNotifierProvider(
      // A new provider for each unit, not the one already pumped.
      key: ValueKey(kj),
      create: (_) => EnergyUnitProvider(usesKilojoules: kj),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ru'), Locale('zh')],
        home: Scaffold(body: child),
      ),
    );

void main() {
  for (final (locale, kcal, kj) in [
    (const Locale('en'), '0 / 2330 kcal', '0 / 2330 kJ'),
    (const Locale('ru'), '0 / 2330 ккал', '0 / 2330 кДж'),
    (const Locale('zh'), '0 / 2330 千卡', '0 / 2330 千焦'),
  ]) {
    testWidgets(
      'a meal header names the chosen unit (${locale.languageCode})',
      (tester) async {
        for (final (useKj, expected) in [(false, kcal), (true, kj)]) {
          late String text;
          await tester.pumpWidget(
            _app(
              useKj,
              locale: locale,
              Builder(
                builder: (context) {
                  text = inEnergyUnit(
                    context,
                    S.of(context).diaryMealKcalConsumedOfTarget('0', '2330'),
                  );
                  return const SizedBox();
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(text, expected);
        }
      },
    );
  }

  testWidgets('the meal detail\'s day total reads in kJ', (tester) async {
    await tester.pumpWidget(
      _app(
        true,
        const DailyKcalOverview(
          dayKcalConsumed: 1000,
          dayKcalGoal: 2000,
          currentSelectionKcal: 100,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Day total: 4602 / 8368 kJ'), findsOneWidget);
    expect(find.text('(+418 kJ current selection)'), findsOneWidget);
  });

  testWidgets('the day total names the unit as the language does', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        true,
        locale: const Locale('ru'),
        const DailyKcalOverview(
          dayKcalConsumed: 1000,
          dayKcalGoal: 2000,
          currentSelectionKcal: 100,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Итого за день: 4602 / 8368 кДж'), findsOneWidget);
    expect(find.text('(+418 кДж текущий выбор)'), findsOneWidget);
  });
}
