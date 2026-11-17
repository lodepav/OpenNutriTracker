import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_bmi_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_target_weight_dialog.dart';
import 'package:opennutritracker/fork/you/you_widgets.dart';
import 'package:opennutritracker/fork/screens/profile/profile_page.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart'
    show keepUnits;
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/ux_checks.dart';

// Seam S121: the You tab as MacroFactor's; every setting it had stays.

class _FakeProfileBloc extends Bloc<ProfileEvent, ProfileState>
    implements ProfileBloc {
  _FakeProfileBloc(super.initialState) {
    on<LoadProfileEvent>((event, emit) => emit(state));
  }

  @override
  Future<UserEntity> getUser() async =>
      (state as ProfileLoadedState).userEntity;

  @override
  Future<void> setCaloriesTaperEnabled(bool enabled) async {}

  @override
  Future<void> updateUser(UserEntity userEntity) async {}
}

class _Home extends Fake implements HomeBloc {
  @override
  final HomeState state;

  _Home(this.state);

  @override
  Stream<HomeState> get stream => const Stream.empty();
}

class _Profiles implements GetProfilesUsecase {
  static final _profile = ProfileEntity(
    id: 'p1',
    name: 'Alex',
    createdAt: DateTime(2026, 1, 1),
    boxSuffix: '',
  );

  @override
  List<ProfileEntity> getProfiles() => [_profile];

  @override
  String get activeProfileId => 'p1';

  @override
  ProfileEntity? getActiveProfile() => _profile;
}

UserEntity _user({
  UserGenderEntity gender = UserGenderEntity.male,
  double? targetKg,
}) {
  final now = DateTime.now();
  return UserEntity(
    birthday: DateTime(now.year - 29, now.month, now.day - 1),
    heightCM: 178,
    weightKG: 87.1,
    gender: gender,
    goal: UserWeightGoalEntity.loseWeight,
    pal: UserPALEntity.active,
    weeklyWeightGoalKg: -0.4,
    targetWeightKg: targetKg,
  );
}

void _register(UserEntity user) {
  final bloc = _FakeProfileBloc(
    ProfileLoadedState(
      userBMI: const UserBMIEntity(
        bmiValue: 27.49,
        nutritionalStatus: UserNutritionalStatus.preObesity,
      ),
      userEntity: user,
      bodyWeightUnit: BodyWeightUnit.kg,
      usesImperialHeightUnits: false,
      effectiveWaterGoalMl: 1900,
    ),
  );
  locator.registerSingleton<ProfileBloc>(bloc);
  locator.registerSingleton<GetProfilesUsecase>(_Profiles());
  addTearDown(bloc.close);
}

Future<List<String?>> _pump(WidgetTester tester, UserEntity user) async {
  _register(user);
  final pushed = <String?>[];
  await tester.binding.setSurfaceSize(const Size(400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: const Scaffold(body: ProfilePage()),
      onGenerateRoute: (settings) {
        pushed.add(settings.name);
        return MaterialPageRoute<void>(builder: (_) => const SizedBox());
      },
    ),
  );
  await tester.pumpAndSettle();
  return pushed;
}

void main() {
  // Water and fasting are off until switched on; these tests show them.
  setUp(() {
    DisplayPrefs.showWater.value = true;
    DisplayPrefs.showFasting.value = true;
  });
  tearDown(() {
    DisplayPrefs.showWater.value = false;
    DisplayPrefs.showFasting.value = false;
  });

  tearDown(() => GetIt.instance.reset());

  testWidgets('who is active, with a Switch button', (tester) async {
    await _pump(tester, _user());
    expect(find.text('Alex'), findsOneWidget);
    // The body facts are BODY's rows, not repeated here.
    expect(find.text('29 · 178 cm · Male'), findsNothing);
    expect(find.bySemanticsIdentifier('profile-switcher'), findsOneWidget);
  });

  testWidgets('every setting of the old You tab is still here', (tester) async {
    await _pump(
      tester,
      _user(gender: UserGenderEntity.nonBinary, targetKg: 80),
    );
    for (final id in [
      'profile-activity',
      'profile-goal',
      'profile-weekly-goal',
      'profile-target-weight',
      'profile-calorie-taper',
      'profile-weight',
      'profile-height',
      'profile-age',
      'profile-gender',
      'profile-calories-profile',
      'profile-weight-history',
      'profile-fasting-entry',
      'profile-water-goal',
      'profile-recipes',
      'profile-sources',
      'profile-settings',
      'profile-bmi',
    ]) {
      expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
    }
  });

  testWidgets('water and fasting hidden in Settings: their tools go', (
    tester,
  ) async {
    await _pump(tester, _user(gender: UserGenderEntity.nonBinary));
    final fasting = find.bySemanticsIdentifier('profile-fasting-entry');
    final water = find.bySemanticsIdentifier('profile-water-goal');
    DisplayPrefs.showFasting.value = false;
    await tester.pumpAndSettle();
    expect(fasting, findsNothing);
    expect(water, findsOneWidget);
    DisplayPrefs.showWater.value = false;
    await tester.pumpAndSettle();
    expect(water, findsNothing);
    expect(
      find.bySemanticsIdentifier('profile-weight-history'),
      findsOneWidget,
    );
  });

  testWidgets('the taper and the calories profile only when they apply', (
    tester,
  ) async {
    await _pump(tester, _user());
    expect(find.bySemanticsIdentifier('profile-calorie-taper'), findsNothing);
    expect(
      find.bySemanticsIdentifier('profile-calories-profile'),
      findsNothing,
    );
  });

  testWidgets('the goal and BMI tiles', (tester) async {
    await _pump(tester, _user(targetKg: 80));
    expect(find.text(keepUnits('Lose 0.4 kg a week')), findsOneWidget);
    expect(find.text(keepUnits('Target 80 kg')), findsOneWidget);
    expect(find.textContaining('27.5'), findsOneWidget);
    // Before Home has loaded the budget is a dash.
    expect(find.text('— kcal'), findsOneWidget);
  });

  testWidgets('a target not set says so', (tester) async {
    await _pump(tester, _user());
    // The Target weight row (JC5); the goal tile offers to set one.
    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('Set'), findsNothing);
  });

  testWidgets('the weight tile and Weight history open the history; '
      'Settings opens its screen', (tester) async {
    final pushed = await _pump(tester, _user());
    await tester.tap(find.bySemanticsIdentifier('profile-weight-trend'));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('profile-settings'));
    await tester.pumpAndSettle();
    expect(pushed, [
      NavigationOptions.weightHistoryRoute,
      NavigationOptions.settingsRoute,
    ]);
  });

  testWidgets('at 2x text on a phone the tiles are one column, '
      'nothing cut, no word broken', (tester) async {
    _register(_user());
    await pumpOnPhone(tester, const ProfilePage());
    tester.view.physicalSize = const Size(1080, 7020);
    await tester.pumpAndSettle();
    final weight = tester.getRect(
      find.bySemanticsIdentifier('profile-weight-trend'),
    );
    final bmi = tester.getRect(find.bySemanticsIdentifier('profile-bmi'));
    final goal = tester.getRect(
      find.bySemanticsIdentifier('profile-goal-tile'),
    );
    expect(goal.left, weight.left);
    expect(goal.top, greaterThan(weight.bottom));
    expect(bmi.width, weight.width);
    expect(cutText(tester), isEmpty);
    _whole(tester, 'Pre-obesity');
    _whole(tester, '0.4 kg');
  });

  testWidgets('at 1x two to a row, nothing cut, units kept with numbers', (
    tester,
  ) async {
    _register(_user());
    await pumpOnPhone(tester, const ProfilePage(), textScale: 1);
    tester.view.physicalSize = const Size(1080, 7020);
    await tester.pumpAndSettle();
    final weight = tester.getRect(
      find.bySemanticsIdentifier('profile-weight-trend'),
    );
    final goal = tester.getRect(
      find.bySemanticsIdentifier('profile-goal-tile'),
    );
    expect(goal.top, weight.top);
    expect(cutText(tester), isEmpty);
    _whole(tester, 'Pre-obesity');
    _whole(tester, '0.4 kg');
  });

  testWidgets('each tile says what it is once, and its one action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _user());
    SemanticsData node(String id) =>
        tester.getSemantics(find.bySemanticsIdentifier(id)).getSemanticsData();
    final bmi = node('profile-bmi');
    expect(bmi.label, 'BMI, 27.5, Pre-obesity');
    expect(bmi.hint, 'How it is worked out');
    final goal = node('profile-goal-tile');
    expect(goal.label, 'Goal, Losing 0.4 kg a week');
    expect(goal.hint, 'Set a target weight');
    final budget = node('profile-budget');
    expect(budget.label, 'Daily budget');
    expect(budget.hint, 'How it is worked out');
    expect(node('profile-weight-trend').hint, 'Open the weight history');
    semantics.dispose();
  });

  testWidgets('with a target the goal tile says it once, and opens the goal', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _user(targetKg: 80));
    final goal = tester
        .getSemantics(find.bySemanticsIdentifier('profile-goal-tile'))
        .getSemanticsData();
    expect(goal.label, 'Goal, Lose 0.4 kg a week, Target 80 kg');
    expect(goal.hint, 'Open the goal');
    semantics.dispose();
  });

  testWidgets('the budget, loaded, spoken in words', (tester) async {
    final semantics = tester.ensureSemantics();
    locator.registerSingleton<HomeBloc>(
      _Home(
        const HomeLoadedState(
          showDisclaimerDialog: false,
          totalKcalDaily: 2400.4,
          totalKcalLeft: 0,
          totalKcalSupplied: 0,
          totalKcalBurned: 0,
          totalCarbsIntake: 0,
          totalFatsIntake: 0,
          totalProteinsIntake: 0,
          totalCarbsGoal: 250,
          totalFatsGoal: 80,
          totalProteinsGoal: 150,
          userActivityList: [],
          breakfastIntakeList: [],
          lunchIntakeList: [],
          dinnerIntakeList: [],
          snackIntakeList: [],
          usesImperialUnits: false,
          bodyWeightUnit: BodyWeightUnit.kg,
          userWeightKg: 87,
          breakfastKcalTarget: 0,
          lunchKcalTarget: 0,
          dinnerKcalTarget: 0,
          snackKcalTarget: 0,
          breakfastSharePct: 25,
          lunchSharePct: 25,
          dinnerSharePct: 25,
          snackSharePct: 25,
          userGender: UserGenderEntity.male,
          userCaloriesProfile: null,
          waterMlToday: 0,
          waterGoalMl: 2000,
          waterIntakes: [],
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BudgetTile(onTap: () {})),
      ),
    );
    final data = tester
        .getSemantics(find.bySemanticsIdentifier('profile-budget'))
        .getSemanticsData();
    expect(data.label, startsWith('Daily budget, 2400 kcal, '));
    for (final part in [
      '250 grams carbs',
      '80 grams fat',
      '150 grams protein',
    ]) {
      expect(data.label, contains(part));
    }
    expect(data.hint, 'How it is worked out');
    semantics.dispose();
  });

  testWidgets('with no target, the goal tile\'s tap sets one, as it says', (
    tester,
  ) async {
    await _pump(tester, _user());
    await tester.tap(find.bySemanticsIdentifier('profile-goal-tile'));
    await tester.pumpAndSettle();
    expect(find.byType(SetTargetWeightDialog), findsOneWidget);
  });

  testWidgets('section titles are headings in Title Case, '
      'their rows buttons of their own', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _user());
    for (final title in ['Plan', 'Body', 'Tools', 'App']) {
      expect(find.text(title.toUpperCase()), findsNothing);
      final heading = tester.getSemantics(find.text(title));
      // Its own node, not one holding the card's rows.
      expect(heading.hasChildren, isFalse, reason: title);
      final data = heading.getSemanticsData();
      expect(data.label, title);
      expect(data.flagsCollection.isHeader, isTrue, reason: title);
    }
    final activity = tester
        .getSemantics(find.bySemanticsIdentifier('profile-activity'))
        .getSemanticsData();
    expect(activity.flagsCollection.isButton, isTrue);
    expect(activity.label, startsWith('Activity'));
    semantics.dispose();
  });

  testWidgets('with no target weight the goal tile names the plan\'s rate', (
    tester,
  ) async {
    await _pump(tester, _user());
    expect(
      find.text(keepUnits('Losing 0.4 kg a week'), findRichText: true),
      findsOne,
    );
    expect(find.text('Set a target weight'), findsOneWidget);
    expect(find.text('No goal'), findsNothing);
  });

  testWidgets('the weekly rate in one form, spoken in words', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _user());
    expect(find.text('−0.4\u00A0kg a\u00A0week'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsIdentifier('profile-weekly-goal'))
          .getSemanticsData()
          .label,
      contains('down 0.4 kg a week'),
    );
    semantics.dispose();
  });

  testWidgets('the profile weight is named apart from the trend; '
      'Data sources', (tester) async {
    await _pump(tester, _user());
    expect(find.text('Profile weight'), findsOneWidget);
    expect(find.text('Data sources'), findsOneWidget);
    expect(find.text('View sources'), findsNothing);
  });
}

/// Every box of [word] on one line, wherever it is shown.
void _whole(WidgetTester tester, String word) {
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.byType(RichText),
  )) {
    final text = paragraph.text.toPlainText().replaceAll(' ', ' ');
    final start = text.indexOf(word);
    if (start < 0) continue;
    final tops = {
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + word.length),
      ))
        box.top,
    };
    expect(tops, hasLength(1), reason: '"$word" split in "$text"');
    return;
  }
  fail('"$word" not shown');
}
