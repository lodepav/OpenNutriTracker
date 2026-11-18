import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/weight_trend_chart.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/generated/l10n.dart';

// The weight chart's line in the accent as every Trends chart draws it
// (S270), and still while animations are off (S271).

const _yellow = Color(0xFFFDD835);

Future<LineChart> _pump(WidgetTester tester, {bool noMotion = false}) async {
  final today = DateTime.now();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: AppPalette.light.withAccent(_yellow).colorScheme,
      ),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: noMotion),
          child: Scaffold(
            body: WeightTrendChart(
              entries: [
                for (var i = 0; i < 10; i++)
                  WeightLogEntity(
                    date: DateTime(today.year, today.month, today.day - i),
                    weightKg: 80 + i * 0.2,
                  ),
              ],
              bodyWeightUnit: BodyWeightUnit.kg,
              targetWeightKg: null,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<LineChart>(find.byType(LineChart));
}

void main() {
  testWidgets('a yellow accent draws the line at 3:1 on the card', (
    tester,
  ) async {
    final chart = await _pump(tester);
    // the trend; the weigh-ins are muted dots
    final trend = chart.data.lineBarsData.last.color!;
    expect(trend, chartSafe(_yellow, AppPalette.light.surface));
    expect(
      contrastRatio(trend, AppPalette.light.surface),
      greaterThanOrEqualTo(3),
    );
  });

  testWidgets('moves at once while animations are off', (tester) async {
    expect((await _pump(tester)).duration, isNot(Duration.zero));
    expect((await _pump(tester, noMotion: true)).duration, Duration.zero);
  });

  testWidgets('the target line is the palette\'s muted text, as on Weight '
      'history', (tester) async {
    final today = DateTime.now();
    // a theme whose onSurfaceVariant is not the palette's muted text
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: WeightTrendChart(
            entries: [
              for (var i = 0; i < 10; i++)
                WeightLogEntity(
                  date: DateTime(today.year, today.month, today.day - i),
                  weightKg: 80 + i * 0.2,
                ),
            ],
            bodyWeightUnit: BodyWeightUnit.kg,
            targetWeightKg: 80.5,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final target = chart.data.extraLinesData.horizontalLines.single;
    expect(target.color, AppPalette.light.textMuted);
  });
}
