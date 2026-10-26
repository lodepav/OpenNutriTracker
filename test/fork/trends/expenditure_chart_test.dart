import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/trends/expenditure_detail.dart';

// The Expenditure chart's axis numbers at a large font.

/// Android's nonlinear font scaling: small text grows twice, large text
/// far less, so a constant scaled by it falls short of a label's width.
class _Nonlinear extends TextScaler {
  const _Nonlinear();

  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 2 : fontSize * 1.2;

  @override
  double get textScaleFactor => 2;
}

void main() {
  testWidgets('the axis numbers stay on one line at a large font', (
    tester,
  ) async {
    final dates = [for (var i = 0; i < 7; i++) DateTime(2026, 10, 20 + i)];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const _Nonlinear()),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ExpenditureChart(
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final labels = find.text('3000');
    expect(labels, findsOneWidget);
    // labelSmall is 11 px, 22 at this scale: one line is under 40 px.
    expect(tester.getSize(labels).height, lessThan(40));
  });
}
