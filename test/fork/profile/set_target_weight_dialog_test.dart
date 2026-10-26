import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_target_weight_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const SetTargetWeightDialog(
                initialKg: 87.1,
                hasExistingTarget: false,
                unit: BodyWeightUnit.kg,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a target far off is typed, not dragged to', (tester) async {
    TargetWeightDialogResult? popped;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped = await showDialog(
              context: context,
              builder: (_) => const SetTargetWeightDialog(
                initialKg: 87.1,
                hasExistingTarget: false,
                unit: BodyWeightUnit.kg,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '80');
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(popped?.value, 80);
  });

  testWidgets('a typed target out of range says so; OK waits', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), '800');
    await tester.pump();
    expect(find.text('Enter correct weight'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(SetTargetWeightDialog), findsOneWidget);
  });
}
