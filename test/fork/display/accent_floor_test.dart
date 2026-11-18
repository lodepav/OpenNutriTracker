import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/styles/accent_colors.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/activity_credit.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/display/home_tiles.dart';
import 'package:opennutritracker/fork/display/week_bars.dart';
import 'package:opennutritracker/fork/screens/home/dashboard_widget.dart';
import 'package:opennutritracker/fork/trends/expenditure_detail.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/weight/weight_history_view.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';

import '../trends/trends_harness.dart' show loaded;

// The picked accent's floors (S233): 4.5:1 as text, 3:1 as a chart mark,
// and today's week bar apart from the past days, for every preset.

const _yellow = Color(0xFFFDD835);
const _palettes = {'light': AppPalette.light, 'dark': AppPalette.dark};
final _accents = [
  ...accentPresetColors,
  AppPalette.light.accent,
  AppPalette.dark.accent,
];

Widget _app(AppPalette p, Widget child) =>
    ChangeNotifierProvider<EnergyUnitProvider>(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: MaterialApp(
        theme: buildAppTheme(p),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

String _hex(Color c) => c.toARGB32().toRadixString(16);

void main() {
  for (final MapEntry(key: name, value: base) in _palettes.entries) {
    test('$name: every accent reaches 4.5:1 as text on the canvas and the '
        'card', () {
      for (final accent in _accents) {
        final p = base.withAccent(accent);
        final text = textAccentOf(p);
        for (final bg in [p.canvas, p.surface]) {
          expect(
            contrastRatio(text, bg),
            greaterThanOrEqualTo(4.5),
            reason: '${_hex(accent)} on ${_hex(bg)}',
          );
        }
        expect(
          contrastRatio(chartSafe(accent, p.surface), p.surface),
          greaterThanOrEqualTo(3),
          reason: _hex(accent),
        );
      }
    });

    test('$name: today\'s week bar stands apart from the past days, both at '
        '3:1 on the card', () {
      for (final accent in _accents) {
        final (:today, :past) = weekBarColors(accent, base.surface);
        final why = _hex(accent);
        expect(
          contrastRatio(today, base.surface),
          greaterThanOrEqualTo(3),
          reason: why,
        );
        expect(
          contrastRatio(past, base.surface),
          greaterThanOrEqualTo(3),
          reason: why,
        );
        // apart by lightness, not only by hue
        expect(
          contrastRatio(today, past),
          greaterThanOrEqualTo(1.5),
          reason: why,
        );
      }
    });
  }

  test('an accent that already reads is unchanged as text', () {
    expect(textAccentOf(AppPalette.light), AppPalette.light.accent);
    expect(textAccentOf(AppPalette.dark), AppPalette.dark.accent);
  });

  group('with a yellow accent in light', () {
    final p = AppPalette.light.withAccent(_yellow);

    test('text buttons draw in the text-safe accent', () {
      final fg = buildAppTheme(
        p,
      ).textButtonTheme.style!.foregroundColor!.resolve(const {})!;
      expect(fg, textAccentOf(p));
      expect(contrastRatio(fg, p.canvas), greaterThanOrEqualTo(4.5));
    });

    testWidgets('the weight history\'s trend line is chart-safe', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          p,
          SizedBox(
            height: 2000,
            child: WeightHistoryView(
              entries: [
                for (var i = 0; i < 10; i++)
                  WeightLogEntity(
                    date: DateTime(2026, 10, 25 - i),
                    weightKg: 80 + i * 0.2,
                  ),
              ],
              unit: BodyWeightUnit.kg,
              targetWeightKg: null,
              onAdd: () {},
              onDelete: (_) {},
              today: DateTime(2026, 10, 25),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bars = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .lineBarsData;
      for (final bar in bars.where((b) => b.color != null)) {
        expect(contrastRatio(bar.color!, p.surface), greaterThanOrEqualTo(3));
      }
    });

    testWidgets('the weight and expenditure sparklines are chart-safe', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          p,
          Column(
            children: [
              WeightTile(
                weightKg: 80,
                unit: BodyWeightUnit.kg,
                load: () async => [
                  for (var i = 0; i < 10; i++)
                    WeightLogEntity(
                      date: DateTime(2026, 10, 25 - i),
                      weightKg: 80 + i * 0.2,
                    ),
                ],
              ),
              ExpenditureTile(
                load: () async => [
                  for (var i = 0; i < 10; i++)
                    ExpenditureDay(
                      date: DateTime(2026, 10, 25 - i),
                      expenditureKcal: 2500 + i * 2.0,
                      intakeKcal: 2300,
                      settled: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final lines = tester.widgetList<Sparkline>(find.byType(Sparkline));
      expect(lines, hasLength(2));
      for (final s in lines) {
        expect(contrastRatio(s.color, p.surface), greaterThanOrEqualTo(3));
      }
    });

    testWidgets('Home\'s kcal ring is chart-safe', (tester) async {
      await tester.pumpWidget(
        _app(
          p,
          DashboardWidget(
            totalKcalSupplied: 1000,
            totalKcalBurned: 0,
            totalKcalDaily: 2500,
            totalKcalLeft: 1500,
            totalCarbsIntake: 100,
            totalFatsIntake: 30,
            totalProteinsIntake: 60,
            totalCarbsGoal: 375,
            totalFatsGoal: 69,
            totalProteinsGoal: 93,
            loadCredit: () async => ActivityCredit.added,
            homeLoads: const Stream.empty(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ring = tester.widget<CircularPercentIndicator>(
        find.byType(CircularPercentIndicator),
      );
      expect(
        contrastRatio(ring.progressColor, p.surface),
        greaterThanOrEqualTo(3),
      );
    });

    testWidgets('the "expenditure a day" figure reads at 4.5:1', (
      tester,
    ) async {
      final today = DateTime(2026, 10, 25);
      final history = [
        for (var i = -30; i <= 0; i++)
          ExpenditureDay(
            date: DateTime(2026, 10, 25 + i),
            expenditureKcal: 3000 + i * 2.0,
            intakeKcal: 2500,
            settled: true,
          ),
      ];
      tester.view.physicalSize = const Size(1080, 7020);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          p,
          Builder(
            builder: (context) => Column(
              children: expenditureBody(
                context,
                loaded(),
                history,
                dates: [
                  for (var i = 6; i >= 0; i--)
                    DateTime(today.year, today.month, today.day - i),
                ],
                pills: const SizedBox(),
                loadIntakes: (_, _) async => const [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final figure = find.ancestor(
        of: find.text('expenditure a day'),
        matching: find.byType(Column),
      );
      final value = tester
          .widgetList<Text>(
            find.descendant(of: figure.first, matching: find.byType(Text)),
          )
          .first;
      expect(
        contrastRatio(value.style!.color!, p.surface),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
