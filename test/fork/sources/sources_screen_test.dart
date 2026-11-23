import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/sources_screen.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

void main() {
  testWidgets('View source buttons are 48 dp and name their source', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpOnPhone(tester, const SourcesScreen(), textScale: 1);
    tester.view.physicalSize = const Size(1080, 7020);
    await tester.pumpAndSettle();

    final buttons = find.byWidgetPredicate((w) => w is TextButton);
    expect(buttons, findsWidgets);
    final labels = <String>[];
    for (final element in buttons.evaluate()) {
      final finder = find.byWidget(element.widget);
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
      labels.add(tester.getSemantics(finder).label);
    }
    expect(labels, contains('View source: Institute of Medicine (2005)'));
    expect(labels, contains('View source: World Health Organization'));
    expect(labels, contains('View source: Herrmann SD, et al. (2024)'));
    expect(labels.toSet(), hasLength(labels.length));
    semantics.dispose();
  });

  testWidgets('card titles are headings', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOnPhone(tester, const SourcesScreen(), textScale: 1);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text(l10nEn.sourcesEnergyTitle)),
      matchesSemantics(label: l10nEn.sourcesEnergyTitle, isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets('an initial entry opens scrolled to it', (tester) async {
    await pumpOnPhone(
      tester,
      SourcesScreen(initialEntry: l10nEn.sourcesEnergyCompensationTitle),
      textScale: 1,
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(
      find.text(l10nEn.sourcesEnergyCompensationTitle),
    );
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(rect.bottom, lessThanOrEqualTo(screen.height));
  });

  testWidgets('with none it opens at the top', (tester) async {
    await pumpOnPhone(tester, const SourcesScreen(), textScale: 1);
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(find.textContaining('Each calculation below names the sources'))
          .top,
      lessThan(kToolbarHeight + 40),
    );
  });
}
