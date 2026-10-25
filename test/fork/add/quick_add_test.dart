import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/quick_add_bottom_sheet.dart';
import 'package:opennutritracker/fork/add/quick_add.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Keeps the entry; the tracked day after it fails, which the sheet logs
/// and stays open on.
class _FakeAdd extends Fake implements AddIntakeUsecase {
  IntakeEntity? added;

  @override
  Future<void> addIntake(IntakeEntity intake) async => added = intake;
}

class _FakeTracked extends Fake implements AddTrackedDayUsecase {}

Widget _app() => MaterialApp(
  localizationsDelegates: const [S.delegate],
  supportedLocales: S.supportedLocales,
  home: Scaffold(
    body: QuickAddBottomSheet(
      intakeType: IntakeTypeEntity.dinner,
      day: DateTime(2026, 10, 26),
    ),
  ),
);

Finder _field(String id) => find.descendant(
  of: find.bySemanticsIdentifier(id),
  matching: find.byType(TextField),
);

Finder _submit() => find.descendant(
  of: find.bySemanticsIdentifier('quick-add-submit'),
  matching: find.byType(FilledButton),
);

String _submitLabel(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _submit(), matching: find.byType(Text)))
    .data!;

void main() {
  test('the typed energy wins, else the macros add it up', () {
    expect(quickAddKcal(typedKcal: 300, carbs: 50), 300);
    expect(quickAddKcal(carbs: 50, fat: 10, protein: 20), 50 * 4 + 90 + 80);
    expect(quickAddKcal(typedKcal: 0, fat: 2), 18);
    expect(quickAddKcal(), isNull);
  });

  testWidgets('macros alone add up the energy on Add and in the field', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_submit()).onPressed, isNull);

    await tester.enterText(_field('quick-add-carbs'), '50');
    await tester.enterText(_field('quick-add-fat'), '10');
    await tester.enterText(_field('quick-add-protein'), '20');
    await tester.pump();

    expect(_submitLabel(tester), 'Add 370 kcal to Dinner');
    expect(
      tester.widget<TextField>(_field('quick-add-energy')).decoration!.hintText,
      '370',
    );
    expect(tester.widget<FilledButton>(_submit()).onPressed, isNotNull);

    await tester.enterText(_field('quick-add-energy'), '450');
    await tester.pump();
    expect(_submitLabel(tester), 'Add 450 kcal to Dinner');
  });

  testWidgets('the entry goes to the meal picked, named Quick add by default', (
    tester,
  ) async {
    final add = _FakeAdd();
    GetIt.I
      ..registerSingleton<AddIntakeUsecase>(add)
      ..registerSingleton<AddTrackedDayUsecase>(_FakeTracked());
    addTearDown(GetIt.I.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.enterText(_field('quick-add-energy'), '450');
    await tester.tap(find.byKey(const ValueKey('quick-add-meal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snack').last);
    await tester.pumpAndSettle();
    expect(_submitLabel(tester), 'Add 450 kcal to Snack');

    await tester.tap(_submit());
    await tester.pumpAndSettle();

    expect(add.added!.type, IntakeTypeEntity.snack);
    expect(add.added!.meal.name, 'Quick add');
    expect(add.added!.totalKcal, closeTo(450, 1e-9));
  });
}
