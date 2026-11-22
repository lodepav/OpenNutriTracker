import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/activity/activity_picker.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// The Compendium's names are lowercase ("bicycling"); the picker shows them
// with a capital, a name the user typed as they typed it.

final _user = UserEntity(
  birthday: DateTime(1990, 1, 1),
  heightCM: 180,
  weightKG: 80,
  gender: UserGenderEntity.male,
  goal: UserWeightGoalEntity.maintainWeight,
  pal: UserPALEntity.sedentary,
);

const _cycling = PhysicalActivityEntity(
  '01015',
  'bicycling',
  'general',
  7.5,
  [],
  PhysicalActivityTypeEntity.bicycling,
);

final _day = DateTime(2026, 10, 25);

Future<void> _pump(WidgetTester tester, List<UserActivityEntity> recent) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: ActivityPickerView(
          title: 'Add activity',
          activities: const [_cycling],
          recent: recent,
          user: _user,
          weightText: '80 kg',
          day: _day,
          today: _day,
          onSearch: (_) {},
          onLog: (_) {},
          onOpenCustom: (_) {},
          onQuickAdd: () {},
          onCustom: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a Compendium name starts with a capital in the row and sheet', (
    tester,
  ) async {
    await _pump(tester, const []);
    expect(find.text('Bicycling'), findsOneWidget);
    expect(find.text('bicycling'), findsNothing);

    await tester.tap(find.text('Bicycling'));
    await tester.pumpAndSettle();
    expect(find.text('Bicycling'), findsNWidgets(2));
    // Mid-sentence it stays lowercase.
    expect(find.text('Add 30 min bicycling'), findsOneWidget);
    // and said in words, not "min" (audit G2 a3)
    expect(
      tester.widget<Text>(find.text('Add 30 min bicycling')).semanticsLabel,
      'Add 30 minutes bicycling',
    );
  });

  testWidgets(
    'a recent chip capitalises the Compendium name, not a typed one',
    (tester) async {
      await _pump(tester, [
        UserActivityEntity('a', 30, 250, _day, _cycling),
        UserActivityEntity(
          'b',
          0,
          300,
          _day,
          PhysicalActivityEntity.customNamed('evening climb'),
          userKcal: 300,
        ),
      ]);
      expect(
        find.textContaining('Bicycling ', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('evening climb ', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets('the app bar "+" says it adds a custom activity', (tester) async {
    await _pump(tester, const []);
    expect(find.byTooltip('Custom activity'), findsOneWidget);
  });
}
