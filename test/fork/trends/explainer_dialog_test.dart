import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';

import '../../helpers/ux_checks.dart' show pumpOnPhone;

// An explainer at 2x on a small phone scrolls to its last words and Close,
// where it cut the text.

const _body =
    'The scale moves with water, salt and the food in you, often by '
    'a kilo (2 lb) or more from one day to the next. The trend smooths '
    'those swings out, so it shows what your weight is really doing. '
    'Each weigh-in nudges it a little, so it follows your weight '
    'closely when you weigh in often.';

void main() {
  testWidgets('at 2x on a 360x640 phone the explainer reads to its end', (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      const ExplainerLink(title: 'What is the trend weight?', body: _body),
    );
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final body = find.text(_body);
    await tester.scrollUntilVisible(
      body,
      100,
      scrollable: find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final dialog = tester.getRect(find.byType(Dialog));
    expect(tester.getRect(body).bottom, lessThanOrEqualTo(dialog.bottom));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
