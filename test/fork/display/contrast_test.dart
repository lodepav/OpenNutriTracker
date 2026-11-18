import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/weight_trend_chart.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/display/meal_macros_line.dart';
import 'package:opennutritracker/fork/display/week_bars.dart';
import 'package:opennutritracker/fork/weight/weight_history_view.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

const _palettes = {'light': AppPalette.light, 'dark': AppPalette.dark};

Widget _app(AppPalette p, Widget child) =>
    ChangeNotifierProvider<EnergyUnitProvider>(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: MaterialApp(
        theme: ThemeData(colorScheme: p.colorScheme),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('chartSafe', () {
    const yellow = Color(0xFFFDD835);
    const amber = Color(0xFFFFB300);
    const indigo = Color(0xFF3949AB);

    test('a light accent on the light card reaches 3:1', () {
      for (final c in [yellow, amber]) {
        final safe = chartSafe(c, AppPalette.light.surface);
        expect(contrastRatio(safe, AppPalette.light.surface), greaterThan(3));
        // still its hue
        expect(
          (HSLColor.fromColor(safe).hue - HSLColor.fromColor(c).hue).abs(),
          lessThan(2),
        );
      }
    });

    test('indigo on the dark card reaches 3:1', () {
      final safe = chartSafe(indigo, AppPalette.dark.surface);
      expect(contrastRatio(safe, AppPalette.dark.surface), greaterThan(3));
    });

    test('a colour that already passes is unchanged', () {
      expect(
        chartSafe(AppPalette.light.accent, AppPalette.light.surface),
        AppPalette.light.accent,
      );
      expect(
        chartSafe(AppPalette.dark.accent, AppPalette.dark.surface),
        AppPalette.dark.accent,
      );
      expect(chartSafe(indigo, AppPalette.light.surface), indigo);
    });

    testWidgets('chartAccent: the theme\'s primary, safe on the card', (
      tester,
    ) async {
      late Color got;
      await tester.pumpWidget(
        _app(
          AppPalette.light.withAccent(yellow),
          Builder(
            builder: (context) {
              got = chartAccent(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(got, chartSafe(yellow, AppPalette.light.surface));
    });
  });

  test('muted macro text reaches 4.5:1 on every background it is drawn on '
      '(D38)', () {
    for (final MapEntry(key: name, value: p) in _palettes.entries) {
      for (final (macro, c) in [
        ('carbs', p.carbsColor),
        ('fat', p.fatColor),
        ('protein', p.proteinColor),
      ]) {
        // the page, a card or row, a picked row or a header
        for (final (bg, b) in [
          ('canvas', p.canvas),
          ('surface', p.surface),
          ('surfaceMuted', p.surfaceMuted),
        ]) {
          expect(
            contrastRatio(mutedMacroColor(c, p), b),
            greaterThanOrEqualTo(4.5),
            reason: '$name $macro on $bg',
          );
        }
      }
    }
  });

  for (final MapEntry(key: name, value: p) in _palettes.entries) {
    testWidgets('$name: every week bar stands out at 3:1 on the card', (
      tester,
    ) async {
      final today = DateTime(2026, 10, 25);
      await tester.pumpWidget(
        _app(
          p,
          WeekBars(
            today: today,
            todayKcal: 1800,
            todayGoalKcal: 2500,
            load: (from, to) async => [
              for (var i = 1; i < 7; i++)
                TrackedDayEntity(
                  day: DateTime(2026, 10, 25 - i),
                  calorieGoal: 2500,
                  caloriesTracked: 2000,
                ),
            ],
          ),
        ),
      );
      await tester.pump();
      final bars = [
        for (final box in tester.widgetList<Container>(find.byType(Container)))
          if (box.decoration case BoxDecoration(:final color?)) color,
      ];
      expect(bars, hasLength(7));
      for (final bar in bars) {
        final drawn = Color.alphaBlend(bar, p.surface);
        expect(contrastRatio(drawn, p.surface), greaterThanOrEqualTo(3));
      }
      // today's bar still apart from the others
      expect(bars.last, isNot(bars.first));
    });

    testWidgets('$name: the weight chart\'s target line stands out at 3:1', (
      tester,
    ) async {
      final today = DateTime.now();
      final entries = [
        for (var i = 0; i < 10; i++)
          WeightLogEntity(
            date: DateTime(today.year, today.month, today.day - i),
            weightKg: 80 + i * 0.2,
          ),
      ];
      await tester.pumpWidget(
        _app(
          p,
          WeightTrendChart(
            entries: entries,
            bodyWeightUnit: BodyWeightUnit.kg,
            targetWeightKg: 80,
            windowDays: 30,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final line = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .extraLinesData
          .horizontalLines
          .single;
      expect(contrastRatio(line.color!, p.surface), greaterThanOrEqualTo(3));
    });

    testWidgets('$name: weight history\'s target line stands out at 3:1', (
      tester,
    ) async {
      final today = DateTime(2026, 10, 25);
      await tester.pumpWidget(
        _app(
          p,
          WeightHistoryView(
            entries: [
              for (var i = 0; i < 10; i++)
                WeightLogEntity(
                  date: DateTime(2026, 10, 25 - i),
                  weightKg: 80 + i * 0.2,
                ),
            ],
            unit: BodyWeightUnit.kg,
            targetWeightKg: 80,
            onAdd: () {},
            onDelete: (_) {},
            today: today,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final line = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .extraLinesData
          .horizontalLines
          .single;
      expect(contrastRatio(line.color!, p.surface), greaterThanOrEqualTo(3));
    });
  }
}
