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

// Seam S128: Add activity as MacroFactor's.

final _user = UserEntity(
  birthday: DateTime(1990, 1, 1),
  heightCM: 180,
  weightKG: 80,
  gender: UserGenderEntity.male,
  goal: UserWeightGoalEntity.maintainWeight,
  pal: UserPALEntity.sedentary,
);

// 4 MET: 80 kg for half an hour burns 160 kcal.
const _yoga = PhysicalActivityEntity(
  '02160',
  'yoga',
  'general',
  4,
  [],
  PhysicalActivityTypeEntity.conditioningExercise,
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

Future<void> _pump(
  WidgetTester tester, {
  UserEntity? user,
  List<PhysicalActivityEntity>? activities = const [_yoga, _cycling],
  List<UserActivityEntity> recent = const [],
  void Function(UserActivityEntity)? onLog,
  void Function(PhysicalActivityEntity)? onOpenCustom,
  void Function(String)? onSearch,
  bool kj = false,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(usesKilojoules: kj),
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
          activities: activities,
          recent: recent,
          user: user ?? _user,
          weightText: '80 kg',
          day: _day,
          today: _day,
          onSearch: onSearch ?? (_) {},
          onLog: onLog ?? (_) {},
          onOpenCustom: onOpenCustom ?? (_) {},
          onQuickAdd: () {},
          onCustom: () {},
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String id) async {
  await tester.tap(find.bySemanticsIdentifier(id));
  await tester.pumpAndSettle();
}

void main() {
  group('repeatEntry', () {
    test('the same minutes at the weight now', () {
      final recent = UserActivityEntity('a', 45, 999, DateTime(2026), _yoga);
      final again = repeatEntry(recent, _user, _day);
      expect(again.duration, 45);
      expect(again.burnedKcal, 240);
      expect(again.date, _day);
      expect(again.id, isNot('a'));
    });

    test('a Custom activity, the same energy', () {
      final custom = PhysicalActivityEntity.customNamed('Climbing');
      final recent = UserActivityEntity(
        'a',
        0,
        310,
        DateTime(2026),
        custom,
        userKcal: 310,
      );
      final again = repeatEntry(recent, _user, _day);
      expect(again.burnedKcal, 310);
      expect(again.userKcal, 310);
      expect(again.duration, 0);
      expect(again.physicalActivityEntity.getName, isNotNull);
    });
  });

  test('dayLabel', () {
    expect(dayLabel(_day, _day), 'Today');
    expect(dayLabel(DateTime(2026, 10, 24, 23), _day), 'Yesterday');
    expect(dayLabel(DateTime(2026, 10, 20), _day), 'Tue, Oct 20');
  });

  testWidgets('each row with what half an hour burns, and the weight', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Estimated for you, per 30 min'), findsOneWidget);
    expect(find.textContaining('160'), findsOneWidget);
    expect(find.textContaining('300'), findsOneWidget);
    expect(
      find.text('Based on 80 kg. Tap a row to pick the duration.'),
      findsOneWidget,
    );
  });

  testWidgets('in kJ when kJ is chosen', (tester) async {
    await _pump(tester, kj: true);
    expect(find.textContaining('669'), findsOneWidget);
    await _tap(tester, 'add-activity-row-02160');
    expect(find.text('≈ 669 kJ'), findsOneWidget);
  });

  testWidgets('a row opens the minutes; Add logs them', (tester) async {
    final logged = <UserActivityEntity>[];
    await _pump(tester, onLog: logged.add);
    await _tap(tester, 'add-activity-row-02160');
    expect(find.text('Today · 4 MET'), findsOneWidget);
    expect(find.text('≈ 160 kcal'), findsOneWidget);

    await _tap(tester, 'activity-duration-45');
    expect(find.text('≈ 240 kcal'), findsOneWidget);
    await _tap(tester, 'activity-duration-more');
    await _tap(tester, 'activity-duration-more');
    await _tap(tester, 'activity-duration-less');
    expect(find.text('50'), findsOneWidget);

    await _tap(tester, 'activity-duration-add');
    expect(logged, hasLength(1));
    expect(logged.single.duration, 50);
    expect(logged.single.burnedKcal, closeTo(266.67, 0.01));
    expect(logged.single.date, _day);
    expect(logged.single.physicalActivityEntity, _yoga);
  });

  testWidgets('down to five minutes and no lower', (tester) async {
    await _pump(tester);
    await _tap(tester, 'add-activity-row-02160');
    await _tap(tester, 'activity-duration-15');
    await _tap(tester, 'activity-duration-less');
    await _tap(tester, 'activity-duration-less');
    expect(find.text('5'), findsOneWidget);
    final less = tester.widget<IconButton>(
      find.descendant(
        of: find.bySemanticsIdentifier('activity-duration-less'),
        matching: find.byType(IconButton),
      ),
    );
    expect(less.onPressed, isNull);
  });

  testWidgets('closing the sheet logs nothing', (tester) async {
    final logged = <UserActivityEntity>[];
    await _pump(tester, onLog: logged.add);
    await _tap(tester, 'add-activity-row-02160');
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(logged, isEmpty);
  });

  testWidgets('a recent activity logs again at a tap', (tester) async {
    final logged = <UserActivityEntity>[];
    await _pump(
      tester,
      onLog: logged.add,
      recent: [UserActivityEntity('r', 45, 1, DateTime(2026), _cycling)],
    );
    expect(find.text('Recent · one tap logs it again'), findsOneWidget);
    expect(
      tester.getSemantics(
        find.bySemanticsIdentifier('add-activity-recent-01015'),
      ),
      containsSemantics(
        label: 'Log bicycling, 45 min, again',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await _tap(tester, 'add-activity-recent-01015');
    expect(logged.single.duration, 45);
    expect(logged.single.burnedKcal, 450);
  });

  testWidgets('no recents, no heading', (tester) async {
    await _pump(tester);
    expect(find.text('Recent · one tap logs it again'), findsNothing);
  });

  testWidgets('the Custom activity goes to its energy screen', (tester) async {
    final opened = <PhysicalActivityEntity>[];
    await _pump(
      tester,
      activities: const [PhysicalActivityEntity.custom],
      onOpenCustom: opened.add,
    );
    expect(find.text('Enter energy'), findsOneWidget);
    await _tap(tester, 'add-activity-row-${PhysicalActivityEntity.customCode}');
    expect(opened, [PhysicalActivityEntity.custom]);
    expect(find.byType(DurationSheet), findsNothing);
  });

  testWidgets('loading, and a search that finds nothing', (tester) async {
    await _pump(tester, activities: null, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final queries = <String>[];
    await _pump(tester, activities: const [], onSearch: queries.add);
    expect(find.text('No activity by that name'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zz');
    expect(queries, ['zz']);
  });
}
