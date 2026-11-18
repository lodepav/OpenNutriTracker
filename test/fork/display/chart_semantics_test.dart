import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/trends/expenditure_detail.dart';
import 'package:opennutritracker/fork/weight/weight_history_view.dart';
import 'package:opennutritracker/generated/l10n.dart';

// A chart is one node: its name and range in words, not its axis ticks.

/// The node's label and every label under it, as TalkBack would read them.
String _spoken(SemanticsNode node) {
  final out = [node.label];
  node.visitChildren((child) {
    out.add(_spoken(child));
    return true;
  });
  return out.where((s) => s.isNotEmpty).join(' / ');
}

Future<void> _pump(WidgetTester tester, Widget chart) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: chart)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the weight history chart reads no axis ticks', (tester) async {
    final handle = tester.ensureSemantics();
    final today = DateTime(2026, 11, 18);
    final dates = [
      for (var i = 29; i >= 0; i--)
        DateTime(today.year, today.month, today.day - i),
    ];
    await _pump(
      tester,
      WeightHistoryChart(
        entries: [
          for (var i = 0; i < 30; i += 3)
            WeightLogEntity(date: dates[i], weightKg: 88 - i * 0.03),
        ],
        unit: BodyWeightUnit.kg,
        targetWeightKg: null,
        dates: dates,
      ),
    );
    expect(find.text('Oct 20'), findsOneWidget);
    final spoken = _spoken(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Weight over'))),
    );
    expect(spoken, isNot(contains('Oct 20')));
    expect(
      spoken,
      matches(
        RegExp(
          r'^Weight over 30 days, from \d+\.\d to '
          r'\d+\.\d kg$',
        ),
      ),
    );
    handle.dispose();
  });

  testWidgets('the expenditure chart reads no axis ticks', (tester) async {
    final handle = tester.ensureSemantics();
    final dates = [for (var i = 0; i < 7; i++) DateTime(2026, 10, 20 + i)];
    await _pump(
      tester,
      ExpenditureChart(
        history: [
          for (final (i, d) in dates.indexed)
            ExpenditureDay(
              date: d,
              expenditureKcal: 3000 + i * 50.0,
              intakeKcal: 2500,
              settled: true,
            ),
        ],
        dates: dates,
      ),
    );
    expect(find.text('3000'), findsOneWidget);
    final spoken = _spoken(
      tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Expenditure (chart|over)')),
      ),
    );
    // Merged ticks follow the name on lines of their own.
    expect(spoken, isNot(contains('\n3000')));
    expect(spoken, isNot(contains('Oct 2')));
    expect(spoken, 'Expenditure over 7 days, from 3000 to 3300 kcal');
    handle.dispose();
  });
}
