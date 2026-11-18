import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/weight_detail.dart';

import '../../helpers/ux_checks.dart';
import '../weight/weight_history_view_test.dart' show brokenInWords;
import 'trends_harness.dart';

// The Weight page's weigh-in rows on a 360 dp phone: the date beside its
// figures while they fit, over them when not, never cut or broken in a word.

/// A fixed week of heavy weigh-ins, so the widest dates ("Wed, Mar 11")
/// and figures ("288.8 lbs") show whatever the day the test runs.
final _last = DateTime(2026, 3, 11);
DateTime _day(int offset) =>
    DateTime(_last.year, _last.month, _last.day + offset);

Widget _page(BodyWeightUnit unit) => Builder(
  builder: (context) => ListView(
    padding: const EdgeInsets.all(16),
    children: weightDetailBody(
      context,
      loaded(
        unit: unit,
        weight: [
          for (var i = -30; i <= 0; i++)
            WeightLogEntity(date: _day(i), weightKg: 131 - i * 0.2),
        ],
      ),
      windowDates(_last, 7),
      TrendsDeps(
        expenditure: ValueNotifier(Future.value(const <ExpenditureDay>[])),
        weightCard: (_) => const SizedBox(),
        waterCard: (_) => const SizedBox(),
        loadIntakes: (_, _) async => const [],
      ),
      const SizedBox(),
    ),
  ),
);

void main() {
  for (final unit in BodyWeightUnit.values) {
    for (final scale in [1.0, 1.3, 1.4, 1.5, 2.0]) {
      testWidgets('at ${scale}x text in ${unit.name} no weigh-in row is cut '
          'or broken inside a word', (tester) async {
        await pumpOnPhone(tester, _page(unit), textScale: scale);
        // 360 dp wide, tall enough to build every row
        tester.view
          ..physicalSize = const Size(360, 6000)
          ..devicePixelRatio = 1;
        await tester.pumpAndSettle();
        final rows = find.ancestor(
          of: find.textContaining(RegExp(r'^trend \d')),
          matching: find.byType(MergeSemantics),
        );
        expect(rows, findsNWidgets(7));
        expect(brokenInWords(tester, within: rows), isEmpty);
        // cutText, in the rows only
        final cut = [
          for (final e
              in find
                  .descendant(of: rows, matching: find.byType(RichText))
                  .evaluate())
            if ((e.renderObject! as RenderParagraph).didExceedMaxLines)
              (e.renderObject! as RenderParagraph).text.toPlainText(),
        ];
        expect(cut, isEmpty);
      });
    }
  }
}
