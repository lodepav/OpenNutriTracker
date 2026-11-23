// Sources after the round-3 settings critique (2026-11-21, G6): the intro
// claims only what is listed, the adaptive expenditure and trend have an
// entry, and a citation is printed once, not inline and again in italics.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/sources_screen.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    await pumpOnPhone(tester, const SourcesScreen(), textScale: 1);
    tester.view.physicalSize = const Size(1080, 9360);
    await tester.pumpAndSettle();
  }

  testWidgets('the intro does not claim every calculation', (tester) async {
    await open(tester);

    expect(find.text(l10nEn.sourcesScreenIntro), findsNothing);
    expect(find.textContaining('every calculation'), findsNothing);
    expect(
      find.textContaining('Each calculation with the sources'),
      findsOneWidget,
    );
  });

  testWidgets('the adaptive expenditure and trend have an entry', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Expenditure and weight trend'), findsOneWidget);
    expect(find.textContaining("the app's own method"), findsOneWidget);
    expect(find.textContaining('How your goal is calculated'), findsOneWidget);
    expect(find.textContaining('Hall KD (2008)'), findsOneWidget);
    expect(find.textContaining('The Hacker'), findsWidgets);
  });

  testWidgets('a citation is not repeated inline as "Source:"', (
    tester,
  ) async {
    await open(tester);

    expect(find.textContaining('Source: '), findsNothing);
    // What only the inline copy said moves into the citation
    expect(find.textContaining('Chapter 5 and Table 5-5'), findsOneWidget);
  });
}
