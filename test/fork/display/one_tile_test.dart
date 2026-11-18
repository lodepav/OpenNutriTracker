import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/fasting/presentation/bloc/fasting_bloc.dart';
import 'package:opennutritracker/fork/display/home_tiles.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart' show windowDates;
import 'package:opennutritracker/fork/trends/trends_overview.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/ux_checks.dart' show cutText, pumpOnPhone;
import '../trends/trends_harness.dart';

Widget _app(Widget child) => ChangeNotifierProvider<EnergyUnitProvider>(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: S.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

/// The tile around [title], its card's radius and its title's style.
({Widget tile, double radius, TextStyle? style}) _look(
  WidgetTester tester,
  String title,
) {
  final text = find.text(title).first;
  return (
    tile: tester.widget(
      find.ancestor(of: text, matching: find.byType(TrendTile)).first,
    ),
    radius: tester
        .widget<AppCard>(
          find.ancestor(of: text, matching: find.byType(AppCard)),
        )
        .borderRadius,
    style: tester.widget<Text>(text).style,
  );
}

void main() {
  testWidgets('Home and Trends draw the weight trend with one tile', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        HomeTiles(
          weightKg: 81,
          bodyWeightUnit: BodyWeightUnit.kg,
          waterMl: 750,
          waterGoalMl: 2000,
          loadWeights: () async => const [],
          loadExpenditure: () async => const [],
          fasting: const FastingTileView(state: FastingIdle()),
          openTrend: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final home = _look(tester, 'Weight trend');

    final state = loaded();
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Column(
            children: trendTiles(
              context,
              state,
              dates: windowDates(state.logicalToday, state.windowDays),
              history: const [],
              micros: null,
              measurements: null,
              open: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trends = _look(tester, 'Weight trend');

    expect(home.tile.runtimeType, trends.tile.runtimeType);
    expect(home.radius, trends.radius);
    expect(home.style, trends.style);
  });

  testWidgets('at 1x a long title in a half-width tile wraps, not cut', (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      Align(
        alignment: Alignment.topLeft,
        // Half a 360 phone's row, as on Home and Trends.
        child: SizedBox(
          width: 156,
          child: TrendTile(
            id: 'sides',
            label: 'Shoulders · left vs right',
            value: '1.2',
            suffix: 'cm',
            onTap: () {},
          ),
        ),
      ),
      textScale: 1,
    );
    expect(cutText(tester), isEmpty);
  });

  testWidgets('at 1.5x, two to a row, a value keeps its unit on its line', (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 156,
          child: Column(
            children: [
              TrendTile(
                id: 'w',
                label: 'Weight trend',
                value: '187.4 lb',
                suffix: '· −0.35 lb in 7 days',
                onTap: () {},
                onAction: () {},
              ),
              TrendTile(id: 'f', label: 'Fasting', value: 'Not fasting'),
              TrendTile(
                id: 'c',
                label: 'Calories · avg',
                value: '2573',
                suffix: '/ 2925 kcal',
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
      textScale: 1.5,
    );
    expect(cutText(tester), isEmpty);
    // [phrase] in one paragraph, all on one line.
    void oneLine(String phrase) {
      final paragraph = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .firstWhere((p) => p.text.toPlainText().contains(phrase));
      final start = paragraph.text.toPlainText().indexOf(phrase);
      final tops = {
        for (final box in paragraph.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + phrase.length),
        ))
          box.top,
      };
      expect(tops, hasLength(1), reason: '"$phrase" split');
    }

    oneLine('187.4 lb');
    oneLine('2573');
    oneLine('2925 kcal');
  });

  testWidgets('a chevron says a tile opens, unless its + takes the corner', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            TrendTile(id: 'a', label: 'Expenditure', value: '1', onTap: () {}),
            TrendTile(
              id: 'b',
              label: 'Water',
              value: '2',
              onTap: () {},
              onAction: () {},
            ),
            const TrendTile(id: 'c', label: 'Fasting', value: '3'),
          ],
        ),
      ),
    );
    Finder chevronIn(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(TrendTile)),
      matching: find.byIcon(Icons.chevron_right_rounded),
    );
    expect(chevronIn('Expenditure'), findsOne);
    expect(chevronIn('Water'), findsNothing);
    expect(chevronIn('Fasting'), findsNothing);
    expect(find.byKey(const Key('b-add')), findsOne);
  });
}
