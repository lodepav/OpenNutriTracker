import 'package:flutter/material.dart';
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
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/profile/profile_page.dart';
import 'package:opennutritracker/generated/l10n.dart';

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

Future<List<String?>> _pump(WidgetTester tester, UserEntity user) async {
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
  tearDown(() => GetIt.instance.reset());

  testWidgets('who is active, with a Switch button', (tester) async {
    await _pump(tester, _user());
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('29 · 178 cm · Male'), findsOneWidget);
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
    expect(find.text('Lose 0.40 kg/wk'), findsOneWidget);
    expect(find.text('Target 80 kg'), findsOneWidget);
    expect(find.textContaining('27.5'), findsOneWidget);
    // Before Home has loaded the budget is a dash.
    expect(find.text('— kcal'), findsOneWidget);
  });

  testWidgets('a target not set says so', (tester) async {
    await _pump(tester, _user());
    // The goal tile's line and the Target weight row (JC5).
    expect(find.text('Not set'), findsNWidgets(2));
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
}
