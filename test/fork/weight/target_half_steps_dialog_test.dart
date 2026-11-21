import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizontal_picker/horizontal_picker.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_target_weight_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

void main() {
  FixedExtentScrollController ruler(WidgetTester tester) =>
      tester
              .widget<ListWheelScrollView>(find.byType(ListWheelScrollView))
              .controller!
          as FixedExtentScrollController;

  testWidgets('one tick of the target ruler is 0.5', (tester) async {
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
                initialKg: 87,
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

    // the package's grey, blue and red fail contrast on the dialog
    final scheme = Theme.of(
      tester.element(find.byType(HorizontalPicker)),
    ).colorScheme;
    final picker = tester.widget<HorizontalPicker>(
      find.byType(HorizontalPicker),
    );
    expect(picker.passiveItemsTextColor, scheme.onSurfaceVariant);
    expect(picker.activeItemTextColor, scheme.primary);
    expect(picker.cursorColor, scheme.primary);

    final controller = ruler(tester);
    controller.jumpToItem(controller.selectedItem + 1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(popped?.value, 87.5);
  });

  testWidgets('an untouched ruler saves the exact weight, not the half', (
    tester,
  ) async {
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
                initialKg: 87.3,
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
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(popped?.value, 87.3);
  });
}
