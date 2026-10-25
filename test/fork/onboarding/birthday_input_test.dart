import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_gender_selection_entity.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_about_you_page_body.dart';
import 'package:opennutritracker/fork/onboarding/birthday_input.dart';
import 'package:opennutritracker/generated/l10n.dart';

const _german = BirthdayFormat(['d', 'M', 'y'], '.');
const _american = BirthdayFormat(['M', 'd', 'y'], '/');

/// What typing [keys] one by one leaves in the field.
String _type(BirthdayFormat format, List<String> keys) {
  final formatter = BirthdayInputFormatter(format);
  var value = TextEditingValue.empty;
  for (final key in keys) {
    final text = key == '⌫'
        ? value.text.substring(0, value.text.length - 1)
        : value.text + key;
    value = formatter.formatEditUpdate(
      value,
      TextEditingValue(text: text),
    );
  }
  return value.text;
}

void main() {
  test('separators go in as each part fills', () {
    expect(_type(_german, '2211'.split('')), '22.11.');
    expect(_type(_german, '22111990'.split('')), '22.11.1990');
    expect(_type(_american, '112219905'.split('')), '11/22/1990');
  });

  test('a backspace over a separator takes the digit before it', () {
    expect(_type(_german, ['2', '2', '⌫']), '2');
    expect(_type(_german, ['2', '2', '1', '⌫', '⌫']), '2');
  });

  test('only a complete, real date parses', () {
    expect(_german.parse('22.11.1990'), DateTime(1990, 11, 22));
    expect(_american.parse('11/22/1990'), DateTime(1990, 11, 22));
    expect(_german.parse('31.02.1990'), isNull);
    expect(_german.parse('22.11.19'), isNull);
    expect(_german.write(DateTime(1990, 1, 5)), '05.01.1990');
  });

  testWidgets('the order and separator are the locale\'s', (tester) async {
    late BirthdayFormat de, us, sv;
    Widget app(Locale locale, void Function(BirthdayFormat) read) =>
        Localizations(
          locale: locale,
          delegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          child: Builder(
            builder: (context) {
              read(BirthdayFormat.of(MaterialLocalizations.of(context)));
              return const SizedBox();
            },
          ),
        );
    await tester.pumpWidget(app(const Locale('de'), (f) => de = f));
    await tester.pumpWidget(app(const Locale('en', 'US'), (f) => us = f));
    await tester.pumpWidget(app(const Locale('sv'), (f) => sv = f));
    expect(de.hint, 'DD.MM.YYYY');
    expect(us.hint, 'MM/DD/YYYY');
    expect(sv.hint, 'YYYY-MM-DD');
  });

  testWidgets('a typed birthday completes the page, a wrong one says so', (
    tester,
  ) async {
    DateTime? birthday;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: OnboardingAboutYouPageBody(
            setPageContent: (_, _, _, date) => birthday = date,
            initialGender: UserGenderSelectionEntity.genderFemale,
            initialCaloriesProfile: CaloriesProfileEntity.values.first,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextFormField);
    await tester.enterText(field, '01151990');
    await tester.pump();
    expect(find.text('01/15/1990'), findsOneWidget);
    expect(birthday, DateTime(1990, 1, 15));

    await tester.enterText(field, '02301990');
    await tester.pump();
    expect(birthday, isNull);
    expect(find.text('Not a date in range'), findsOneWidget);
  });
}
