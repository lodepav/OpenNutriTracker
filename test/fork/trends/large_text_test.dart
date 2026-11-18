import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/weight_trend_chart.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/ux_checks.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  home: MediaQuery(
    data: const MediaQueryData(
      size: Size(400, 800),
      textScaler: TextScaler.linear(2),
    ),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('at 200% each figure is a row: its label whole, its unit kept', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const StatHeader(
          stats: [
            (label: 'Trend weight', value: '87.1', unit: 'kg'),
            (label: 'Change', value: '-0.2', unit: 'kg'),
            (label: 'Per week', value: '-0.16', unit: 'kg'),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final label = find.text('Trend weight');
    final value = find.text('87.1 kg', findRichText: true);
    expect(value, findsOneWidget);
    // Beside each other, and the next figure below.
    expect(
      (tester.getCenter(label).dy - tester.getCenter(value).dy).abs(),
      lessThan(20),
    );
    expect(
      tester.getTopLeft(find.text('Change')).dy,
      greaterThan(tester.getBottomLeft(label).dy),
    );
  });

  testWidgets('at 200% a tile wraps its label and value, not cut them', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 180,
          child: TrendTile(
            id: 'weight',
            label: 'Weight trend',
            value: '87.1 kg',
            suffix: '-0.20/wk',
            chart: const SizedBox(height: 20),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('Weight trend')).maxLines, 2);
  });

  for (final (value, suffix, units) in [
    ('3045', 'kcal\u00A0a\u00A0day', ['kcal a day']),
    (
      '87.1',
      'kg · \u22120.16\u00A0kg\u00A0a\u00A0week',
      ['\u22120.16 kg a week'],
    ),
    ('2573', '/ 2925 kcal', ['2925 kcal']),
  ]) {
    // 200 to 250 split each unit before this, in the app's font
    for (final width in [180.0, 200.0, 220.0, 250.0]) {
      testWidgets('at 200% a $width wide tile keeps ${units.join()} whole', (
        tester,
      ) async {
        await pumpOnPhone(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: TrendTile(
                id: 'tile',
                label: 'Energy',
                value: value,
                suffix: suffix,
                chart: const SizedBox(height: 20),
                onTap: () {},
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(cutText(tester), isEmpty);
        final paragraph = tester
            .renderObjectList<RenderParagraph>(find.byType(RichText))
            .firstWhere((p) => p.text.toPlainText().contains(value));
        final plain = paragraph.text.toPlainText();
        for (final unit in units) {
          // the unit whatever joiners sit in it
          final match = RegExp(
            RegExp.escape(
              unit,
            ).replaceAll(' ', '[ \u00A0]').replaceAll('/', '/\u2060?'),
          ).firstMatch(plain)!;
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: match.start, extentOffset: match.end),
          );
          // on one line every box shares a band, whatever its font size
          final top = boxes.map((b) => b.top).reduce(math.max);
          final bottom = boxes.map((b) => b.bottom).reduce(math.min);
          expect(top, lessThan(bottom), reason: '"$unit" split in "$plain"');
        }
      });
    }
  }

  testWidgets('at 200% the weight chart axes make room for their labels', (
    tester,
  ) async {
    final today = DateTime.now();
    await tester.pumpWidget(
      _app(
        WeightTrendChart(
          entries: [
            for (var i = 0; i < 5; i++)
              WeightLogEntity(
                date: DateTime(today.year, today.month, today.day - i),
                weightKg: 87 + i * 0.1,
              ),
          ],
          bodyWeightUnit: BodyWeightUnit.kg,
          targetWeightKg: null,
          windowDays: 7,
        ),
      ),
    );
    final titles = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .titlesData;
    expect(titles.leftTitles.sideTitles.reservedSize, 80);
    expect(titles.bottomTitles.sideTitles.reservedSize, 56);
    expect(find.text('Dots: weigh-ins. Bold line: trend.'), findsOneWidget);
  });
}
