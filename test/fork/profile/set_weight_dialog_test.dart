import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_weight_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

void main() {
  Future<Object?> weighIn(
    WidgetTester tester,
    BodyWeightUnit unit,
    String typed,
  ) async {
    Object? popped;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped = await showDialog(
              context: context,
              builder: (_) => SetWeightDialog(initialKg: 87, unit: unit),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), typed);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    return popped;
  }

  testWidgets('a weigh-in can be typed, not only dragged', (tester) async {
    expect(await weighIn(tester, BodyWeightUnit.kg, '86.4'), 86.4);
  });

  testWidgets('in pounds, typed and kept in kg', (tester) async {
    expect(
      await weighIn(tester, BodyWeightUnit.lb, '190'),
      closeTo(86.18, 0.01),
    );
  });

  testWidgets('untouched, the ruler\'s weight is kept', (tester) async {
    Object? popped;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped = await showDialog(
              context: context,
              builder: (_) =>
                  const SetWeightDialog(initialKg: 87, unit: BodyWeightUnit.kg),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(popped, closeTo(87, 0.05));
  });
}
