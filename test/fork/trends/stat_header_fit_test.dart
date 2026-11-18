import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';

import '../../helpers/ux_checks.dart' show pumpOnPhone;

// Every detail page's StatHeader on a 360 dp phone, its widest figures, at
// the text sizes between 1x and 2x: no label or figure cut.

typedef _Stat = ({String label, String value, String? unit});

/// Each page's header as it builds it, with wide values.
Map<String, List<_Stat>> _headers(String w) => {
  'Weight ($w)': [
    (label: 'Trend weight', value: '288.8', unit: w),
    (label: 'Change', value: '−18.0', unit: w),
    (label: 'Per week', value: '−1.40', unit: w),
  ],
  'Goal progress ($w)': [
    (label: 'Start · Mar 11', value: '288.8', unit: w),
    (label: 'Trend now', value: '270.8', unit: w),
    (label: 'Target', value: '220.5', unit: w),
  ],
};

final _energy = <String, List<_Stat>>{
  'Trend': [
    (label: 'Average', value: '2850', unit: 'kcal'),
    (label: 'Goal', value: '2500', unit: 'kcal'),
    (label: 'Change', value: '+350', unit: 'kcal'),
  ],
  'Calories': [
    (label: 'Average', value: '11925', unit: 'kJ'),
    (label: 'Goal', value: '10460', unit: 'kJ'),
  ],
  'Balance': [
    (label: 'Average', value: '−500', unit: 'kcal a day'),
    (label: 'Total', value: '−15000', unit: 'kcal'),
    (label: 'Logged', value: '30', unit: 'days'),
  ],
  'Expenditure': [
    (label: 'Now', value: '3050', unit: 'kcal'),
    (label: 'Change', value: '+120', unit: 'kcal'),
    (label: 'Average', value: '2990', unit: 'kcal'),
  ],
  'Nutrient': [
    (label: 'Average', value: '1450', unit: 'mg'),
    (label: 'Limit', value: '2300', unit: 'mg'),
    (label: 'Under it', value: '25', unit: 'of 30 days'),
  ],
  'Waist': [
    (label: 'Waist to height', value: '0.52', unit: null),
    (label: 'Waist', value: '101.5', unit: 'cm'),
    (label: 'Waist to hips', value: '0.95', unit: null),
  ],
  'Sides': [
    (label: 'Left', value: '38.5', unit: 'cm'),
    (label: 'Right', value: '38.0', unit: 'cm'),
    (label: 'Difference', value: '0.5', unit: 'cm'),
  ],
};

/// [cutText], within [of].
List<String> _cut(WidgetTester tester, Finder of) => [
  for (final e
      in find.descendant(of: of, matching: find.byType(RichText)).evaluate())
    if (e.renderObject! case final RenderParagraph p
        when p.didExceedMaxLines ||
            (!p.softWrap &&
                p.size.width + 0.5 < p.getMaxIntrinsicWidth(double.infinity)))
      p.text.toPlainText(),
];

void main() {
  final headers = {
    for (final w in ['kg', 'lbs', 'st']) ..._headers(w),
    ..._energy,
  };
  for (final scale in [1.0, 1.3, 1.4, 1.5, 2.0]) {
    testWidgets('at ${scale}x no detail page\'s header is cut on a 360 dp '
        'phone', (tester) async {
      await pumpOnPhone(
        tester,
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final MapEntry(key: name, value: stats) in headers.entries)
              Padding(
                key: ValueKey(name),
                padding: const EdgeInsets.only(bottom: 16),
                child: StatHeader(stats: stats),
              ),
          ],
        ),
        textScale: scale,
      );
      tester.view
        ..physicalSize = const Size(360, 6000)
        ..devicePixelRatio = 1;
      await tester.pumpAndSettle();
      expect(find.byType(StatHeader), findsNWidgets(headers.length));
      final cut = <String>[
        for (final name in headers.keys)
          for (final t in _cut(tester, find.byKey(ValueKey(name)))) '$name: $t',
      ];
      expect(cut, isEmpty);
    });
  }

  // Stacking is for when columns don't fit: a header that fits keeps them.
  testWidgets('at 1x the Weight header in kg keeps its three columns', (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      ListView(
        padding: const EdgeInsets.all(16),
        children: [StatHeader(stats: _headers('kg')['Weight (kg)']!)],
      ),
      textScale: 1,
    );
    tester.view
      ..physicalSize = const Size(360, 2000)
      ..devicePixelRatio = 1;
    await tester.pumpAndSettle();
    final tops = {
      for (final label in ['Trend weight', 'Change', 'Per week'])
        tester.getTopLeft(find.text(label)).dy,
    };
    expect(tops, hasLength(1));
  });
}
