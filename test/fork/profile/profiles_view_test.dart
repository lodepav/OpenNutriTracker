import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_gender_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_pal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_weight_goal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/weight_log_dbo.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/fork/profile/profiles_view.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../a11y/nested_buttons.dart';

final _alex = ProfileEntity(
  id: 'alex',
  name: 'Alex',
  createdAt: DateTime(2026, 3, 2),
  boxSuffix: '',
);
final _sam = ProfileEntity(
  id: 'sam',
  name: 'Sam',
  createdAt: DateTime(2026, 8, 9),
  boxSuffix: '_sam',
);

TrackedDayDBO _day(int day, double goal, double tracked) => TrackedDayDBO(
  day: DateTime(2026, 10, day),
  calorieGoal: goal,
  caloriesTracked: tracked,
);

void main() {
  test('the latest goal up to today, the trend, the days with food', () {
    final stats = profileStats(
      UserDBO(
        birthday: DateTime(1990, 6, 15),
        heightCM: 178,
        weightKG: 88,
        gender: UserGenderDBO.male,
        goal: UserWeightGoalDBO.loseWeight,
        pal: UserPALDBO.sedentary,
      ),
      [
        _day(23, 3000, 2900),
        _day(25, 3097, 1200),
        _day(24, 3050, 0),
        // Tomorrow's row, made ahead: not yet the goal, not a day logged.
        _day(26, 3200, 0),
      ],
      [WeightLogDBO(date: DateTime(2026, 10, 25), weightKg: 87.1)],
      DateTime(2026, 10, 25, 20),
    );
    expect(stats.goal, UserWeightGoalEntity.loseWeight);
    expect(stats.kcalGoal, 3097);
    expect(stats.trendKg, 87.1);
    expect(stats.daysLogged, 2);
  });

  test('a profile with nothing yet has no figures', () {
    final stats = profileStats(
      null,
      const [],
      const [],
      DateTime(2026, 10, 25),
    );
    expect(stats.goal, isNull);
    expect(stats.kcalGoal, isNull);
    expect(stats.trendKg, isNull);
    expect(stats.daysLogged, 0);
  });

  group('the cards', () {
    late List<String> calls;

    Future<void> pump(WidgetTester tester, List<ProfileEntity> profiles) async {
      calls = [];
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => EnergyUnitProvider(),
          child: MaterialApp(
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: ProfilesView(
                profiles: profiles,
                activeId: 'alex',
                stats: {
                  'alex': (
                    goal: UserWeightGoalEntity.loseWeight,
                    kcalGoal: 3097,
                    trendKg: 87.1,
                    daysLogged: 41,
                  ),
                },
                weightUnit: BodyWeightUnit.kg,
                onEdit: (p) => calls.add('edit ${p.id}'),
                onSwitch: (p) => calls.add('switch ${p.id}'),
                onDelete: (p) => calls.add('delete ${p.id}'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the active one is marked; the other has Switch', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, [_alex, _sam]);
      expect(tapsInTaps(tester), isEmpty);
      // The name and status first, then the figures, each as one.
      final card = tester.getSemantics(
        find.bySemanticsIdentifier('profile-card-alex'),
      );
      final read = <String>[];
      card.visitChildren((n) {
        read.add(n.label);
        return true;
      });
      expect(card.label, isEmpty);
      expect(read.first, startsWith('Alex'));
      expect(read.first, contains('Active'));
      expect(read, contains('3097\nkcal goal'));
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Lose weight · since Mar 2026'), findsOneWidget);
      expect(find.text('3097'), findsOneWidget);
      expect(find.text('87.1 kg'), findsOneWidget);
      expect(find.text('41'), findsOneWidget);
      // Sam's figures are not read yet: dashes, and since when.
      expect(find.text('since Aug 2026'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(3));

      expect(find.bySemanticsIdentifier('profile-switch-alex'), findsNothing);
      await tester.tap(find.bySemanticsIdentifier('profile-switch-sam'));
      await tester.tap(find.byTooltip('Edit Sam'));
      await tester.tap(find.byTooltip('Delete Alex'));
      expect(calls, ['switch sam', 'edit sam', 'delete alex']);
      handle.dispose();
    });

    testWidgets('the last profile can not be deleted', (tester) async {
      await pump(tester, [_alex]);
      expect(
        find.bySemanticsIdentifier('manage-profiles-delete'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('manage-profiles-edit'),
        findsOneWidget,
      );
    });
  });
}
