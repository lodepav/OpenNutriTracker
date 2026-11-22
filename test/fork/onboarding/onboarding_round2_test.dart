import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/bounds/ranges_const.dart';
import 'package:opennutritracker/core/utils/bounds/validator.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/theme_mode_provider.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_body_measurements_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_other_options_page_body.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/feet_inches_input.dart';
import 'package:opennutritracker/fork/onboarding/birthday_input.dart';
import 'package:opennutritracker/fork/screens/onboarding/onboarding_about_you_page_body.dart';
import 'package:opennutritracker/fork/screens/onboarding/onboarding_limits.dart';
import 'package:opennutritracker/fork/settings/accent_view.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

/// The first-run critique of 2026-11-21 (G1, round 2).
void main() {
  group('birthday error', () {
    const us = BirthdayFormat(['M', 'd', 'y'], '/');
    final now = DateTime(2026, 11, 21);

    test('an impossible date says it does not exist', () {
      expect(
        birthdayError('02/31/2025', us, now: now),
        "That date doesn't exist",
      );
    });

    test('too young or in the future gives the whole years accepted', () {
      final first = ValueValidator.getFirstDate(now: now);
      final message = 'Enter a birthday between ${first.year + 1} and 2012';
      expect(birthdayError('06/01/2020', us, now: now), message);
      expect(birthdayError('06/01/2030', us, now: now), message);
      // Both named years are accepted whole.
      expect(birthdayError('01/01/${first.year + 1}', us, now: now), isNull);
      expect(birthdayError('12/31/2012', us, now: now), isNull);
    });

    test('incomplete or accepted is no error', () {
      expect(birthdayError('02/31', us, now: now), isNull);
      expect(birthdayError('01/15/1990', us, now: now), isNull);
    });

    testWidgets('the page shows which', (tester) async {
      await pumpOnPhone(
        tester,
        OnboardingAboutYouPageBody(setPageContent: (_, _, _, _) {}),
        textScale: 1,
      );
      final field = find.byType(TextFormField);
      await tester.enterText(field, '02312025');
      await tester.pump();
      expect(find.text("That date doesn't exist"), findsOneWidget);
      await tester.enterText(field, '06012030');
      await tester.pump();
      expect(find.textContaining('Enter a birthday between'), findsOneWidget);
    });
  });

  group('body limits', () {
    test('each stated height limit is accepted', () {
      expect(heightRangeText(imperial: false), 'Height between 30 and 300 cm');
      expect(ValueValidator.parseHeightInCm(30), isNotNull);
      expect(ValueValidator.parseHeightInCm(300), isNotNull);
      expect(ValueValidator.parseHeightInCm(29), isNull);
      expect(ValueValidator.parseHeightInCm(301), isNull);
      expect(heightRangeText(imperial: true), 'Height between 1 and 9 ft');
      expect(ValueValidator.parseFeetInchesHeightInCm(1, 0), isNotNull);
      expect(ValueValidator.parseFeetInchesHeightInCm(9, 0), isNotNull);
    });

    test('each stated weight limit is accepted', () {
      expect(
        weightRangeText(BodyWeightUnit.kg, 'kg'),
        'Weight between 2 and 640 kg',
      );
      expect(ValueValidator.parseWeightInKg(2), isNotNull);
      expect(ValueValidator.parseWeightInKg(640), isNotNull);
      expect(ValueValidator.parseWeightInKg(1.9), isNull);
      expect(ValueValidator.parseWeightInKg(640.1), isNull);
      expect(
        weightRangeText(BodyWeightUnit.lb, 'lbs'),
        'Weight between 5 and 1411 lbs',
      );
      expect(ValueValidator.parseWeightInKg(5, isImperial: true), isNotNull);
      expect(ValueValidator.parseWeightInKg(1411, isImperial: true), isNotNull);
      expect(ValueValidator.parseWeightInKg(4, isImperial: true), isNull);
      expect(ValueValidator.parseWeightInKg(1412, isImperial: true), isNull);
      expect(
        weightRangeText(BodyWeightUnit.st, 'st'),
        'Weight between 1 and 100 st',
      );
      expect(ValueValidator.parseStLbWeightInKg(1, 0), isNotNull);
      expect(ValueValidator.parseStLbWeightInKg(100, 0), isNotNull);
      expect(
        UnitCalc.stLbToKg(101, 0),
        greaterThan(Ranges.maxWeight),
        reason: 'the next whole stone out is refused',
      );
    });

    test('the blocked message names the one wrong field', () {
      expect(
        bodyBlockedMessage(heightOk: true, weightOk: false, targetOk: true),
        'Enter a valid weight to continue',
      );
      expect(
        bodyBlockedMessage(heightOk: false, weightOk: true, targetOk: true),
        'Enter a valid height to continue',
      );
      expect(
        bodyBlockedMessage(heightOk: true, weightOk: true, targetOk: false),
        'Enter a valid target weight, or leave it blank',
      );
      expect(
        bodyBlockedMessage(heightOk: false, weightOk: false, targetOk: true),
        isNull,
      );
    });

    Future<ValueNotifier<int>> pumpBody(
      WidgetTester tester, {
      bool heightImperial = false,
      BodyWeightUnit unit = BodyWeightUnit.kg,
      ValueNotifier<String?>? blockedMessage,
    }) async {
      final showErrors = ValueNotifier<int>(0);
      addTearDown(showErrors.dispose);
      await pumpOnPhone(
        tester,
        OnboardingBodyMeasurementsPageBody(
          setButtonContent: (_, _, _, _, _, _, _) {},
          showErrorsSignal: showErrors,
          initialHeightImperial: heightImperial,
          initialBodyWeightUnit: unit,
          blockedMessage: blockedMessage,
        ),
        textScale: 1,
      );
      return showErrors;
    }

    testWidgets('a refused weight gives the range in its unit', (tester) async {
      final showErrors = await pumpBody(tester, unit: BodyWeightUnit.lb);
      await tester.enterText(find.byType(TextFormField).at(1), '9999');
      showErrors.value++;
      await tester.pump();
      expect(find.text('Weight between 5 and 1411 lbs'), findsOneWidget);
      expect(find.text(l10nEn.onboardingWrongWeightLabel), findsOneWidget);
    });

    testWidgets('a refused height gives the range in its unit', (tester) async {
      final showErrors = await pumpBody(tester);
      await tester.enterText(find.byType(TextFormField).first, '9');
      showErrors.value++;
      await tester.pump();
      expect(find.text('Height between 30 and 300 cm'), findsOneWidget);
    });

    testWidgets('a refused target gives the range too', (tester) async {
      final showErrors = await pumpBody(tester);
      await tester.enterText(find.byType(TextFormField).at(1), '80');
      await tester.enterText(find.byType(TextFormField).at(2), '1000');
      showErrors.value++;
      await tester.pump();
      expect(find.text('Weight between 2 and 640 kg'), findsOneWidget);
    });

    testWidgets('no range line before an error shows', (tester) async {
      await pumpBody(tester);
      expect(find.textContaining('between'), findsNothing);
    });

    testWidgets('moving from feet to inches shows no height error yet', (
      tester,
    ) async {
      await pumpBody(tester, heightImperial: true);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '5');
      await tester.tap(fields.at(1));
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.onboardingWrongHeightLabel), findsNothing);
      expect(find.textContaining('Height between'), findsNothing);
    });

    testWidgets('the keyboard goes from feet on to inches, no error yet', (
      tester,
    ) async {
      await pumpBody(tester, heightImperial: true);
      final fields = find.byType(TextField);
      // The keyboard's key on feet: done left the pair half typed.
      expect(
        tester.widget<TextField>(fields.at(0)).textInputAction,
        TextInputAction.next,
      );
      await tester.enterText(fields.at(0), '5');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.onboardingWrongHeightLabel), findsNothing);
      final inches = tester.widget<EditableText>(
        find.descendant(of: fields.at(1), matching: find.byType(EditableText)),
      );
      expect(inches.focusNode.hasFocus, isTrue);
    });

    testWidgets('12 inches or more is refused', (tester) async {
      final reported = <double?>[];
      await pumpOnPhone(
        tester,
        FeetInchesInput(
          initialCm: null,
          identifierPrefix: 'h',
          onChangedCm: reported.add,
        ),
        textScale: 1,
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '5');
      await tester.enterText(fields.at(1), '11');
      expect(reported.last, isNotNull);
      await tester.enterText(fields.at(1), '40');
      expect(reported.last, isNull);
    });

    testWidgets('the page publishes which field holds Next up', (tester) async {
      final message = ValueNotifier<String?>(null);
      addTearDown(message.dispose);
      await pumpBody(tester, blockedMessage: message);
      await tester.enterText(find.byType(TextFormField).at(0), '180');
      await tester.enterText(find.byType(TextFormField).at(1), '0');
      await tester.pump();
      expect(message.value, 'Enter a valid weight to continue');
      await tester.enterText(find.byType(TextFormField).at(1), '80');
      await tester.pump();
      expect(message.value, isNull);
    });
  });

  group('other options', () {
    Future<void> pumpOptions(WidgetTester tester) => pumpOnPhone(
      tester,
      ChangeNotifierProvider<ThemeModeProvider>(
        create: (_) => ThemeModeProvider(appTheme: AppThemeEntity.system),
        child: OnboardingOtherOptionsPageBody(
          setPageContent: (_, _, _, _, _) {},
          initialTheme: AppThemeEntity.system,
          initialFoodSourceToggles: const {},
          initialDailyReminderEnabled: false,
          initialUseMaterialYou: false,
          initialAccentColor: null,
        ),
      ),
    );

    testWidgets('stacked theme choices fill the card in a rounded box', (
      tester,
    ) async {
      await pumpOptions(tester);
      final button = find.byType(SegmentedButton<AppThemeEntity>);
      final widget = tester.widget<SegmentedButton<AppThemeEntity>>(button);
      expect(widget.direction, Axis.vertical);
      expect(
        widget.style?.shape?.resolve({}),
        isA<RoundedRectangleBorder>(),
        reason: 'a stadium cuts the first and last rows at the sides',
      );
      final accentRow = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      );
      expect(
        tester.getSize(button).width,
        moreOrLessEquals(tester.getSize(accentRow).width, epsilon: 0.5),
      );
    });

    testWidgets('the last swatch scrolls fully into view', (tester) async {
      await pumpOptions(tester);
      final row = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      );
      final last = find.bySemanticsLabel(accentPresetNames.last);
      await tester.scrollUntilVisible(last, 100, scrollable: row);
      final position = tester.state<ScrollableState>(row).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(
        tester.getRect(last).right,
        lessThanOrEqualTo(tester.getRect(row).right),
      );
    });
  });
}
