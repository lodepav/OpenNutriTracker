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
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/fork/screens/profile/profile_page.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../helpers/recording_add_weight_log_usecase.dart';

// The You tab keeps its list through a profile reload: an edit used to swap
// it for a spinner, which reset the scroll and TalkBack's focus.

/// A state the page has no screen for, as an error would be.
class _OtherState extends ProfileState {
  @override
  List<Object?> get props => [];
}

/// Each load emits Loading, then the next of [loads]; a [silent] one only
/// counts.
class _FakeProfileBloc extends Bloc<ProfileEvent, ProfileState>
    implements ProfileBloc {
  final List<ProfileState> loads;
  final bool silent;
  var loadEvents = 0;

  _FakeProfileBloc(super.initialState, this.loads, {this.silent = false}) {
    on<LoadProfileEvent>((event, emit) async {
      loadEvents++;
      if (silent) return;
      emit(ProfileLoadingState());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (loads.isNotEmpty) emit(loads.removeAt(0));
    });
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

class _WeighIns extends Fake implements GetWeightLogUsecase {
  var loads = 0;

  @override
  Future<List<WeightLogEntity>> getAllEntries() async {
    loads++;
    return const [];
  }
}

/// One weigh-in today, 85 kg, each load slow, as from disk.
class _SlowWeighIns extends Fake implements GetWeightLogUsecase {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return [WeightLogEntity(date: DateTime.now(), weightKg: 85)];
  }
}

class _User extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async => _loaded(178).userEntity;
}

ProfileLoadedState _loaded(double heightCm) {
  final now = DateTime.now();
  return ProfileLoadedState(
    userBMI: const UserBMIEntity(
      bmiValue: 27.49,
      nutritionalStatus: UserNutritionalStatus.preObesity,
    ),
    userEntity: UserEntity(
      birthday: DateTime(now.year - 29, now.month, now.day - 1),
      heightCM: heightCm,
      weightKG: 87.1,
      gender: UserGenderEntity.male,
      goal: UserWeightGoalEntity.loseWeight,
      pal: UserPALEntity.active,
      weeklyWeightGoalKg: -0.4,
    ),
    bodyWeightUnit: BodyWeightUnit.kg,
    usesImperialHeightUnits: false,
    effectiveWaterGoalMl: 1900,
  );
}

Future<_FakeProfileBloc> _pump(
  WidgetTester tester,
  ProfileState initial,
  List<ProfileState> loads, {
  bool silent = false,
  GetWeightLogUsecase? weighIns,
}) async {
  final bloc = _FakeProfileBloc(initial, loads, silent: silent);
  locator.registerSingleton<ProfileBloc>(bloc);
  locator.registerSingleton<GetProfilesUsecase>(_Profiles());
  locator.registerSingleton<GetWeightLogUsecase>(weighIns ?? _WeighIns());
  addTearDown(bloc.close);
  addTearDown(GetIt.instance.reset);
  await tester.binding.setSurfaceSize(const Size(400, 700));
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
    ),
  );
  return bloc;
}

final _spinner = find.byType(CircularProgressIndicator);

void main() {
  testWidgets('the first load shows the spinner, asked for once', (
    tester,
  ) async {
    final bloc = await _pump(tester, ProfileInitial(), [_loaded(178)]);
    await tester.pump();
    expect(_spinner, findsOneWidget);
    // A rebuild while it loads asks for no second load.
    // ignore: invalid_use_of_protected_member
    tester.state(find.byType(ProfilePage)).setState(() {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(bloc.loadEvents, 1);
    expect(_spinner, findsNothing);
    expect(find.text('178 cm'), findsOneWidget);
  });

  testWidgets('the first load is asked for once, not on each build', (
    tester,
  ) async {
    final bloc = await _pump(tester, ProfileInitial(), [], silent: true);
    for (var i = 0; i < 2; i++) {
      // ignore: invalid_use_of_protected_member
      tester.state(find.byType(ProfilePage)).setState(() {});
      await tester.pump();
    }
    expect(bloc.loadEvents, 1);
  });

  testWidgets('a reload, the weight unchanged, reloads the weight trend', (
    tester,
  ) async {
    final weighIns = _WeighIns();
    final bloc = await _pump(tester, _loaded(178), [
      _loaded(178),
    ], weighIns: weighIns);
    await tester.pumpAndSettle();
    expect(weighIns.loads, 1);
    // as a weigh-in on a past day saved from Weight history
    bloc.add(LoadProfileEvent());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(weighIns.loads, 2);
  });

  testWidgets('an edit never shows the profile weight in the trend tile', (
    tester,
  ) async {
    final bloc = await _pump(tester, _loaded(178), [
      _loaded(180),
    ], weighIns: _SlowWeighIns());
    await tester.pumpAndSettle();
    final tile = find.bySemanticsIdentifier('profile-weight-trend');
    Finder shows(String text) =>
        find.descendant(of: tile, matching: find.textContaining(text));
    expect(shows('85.0'), findsOneWidget);

    bloc.add(LoadProfileEvent());
    var profileWeightShown = false;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (shows('87.1').evaluate().isNotEmpty) profileWeightShown = true;
    }
    await tester.pumpAndSettle();
    expect(profileWeightShown, isFalse);
    expect(shows('85.0'), findsOneWidget);
  });

  testWidgets('an edit reloads in place: no spinner, the scroll kept', (
    tester,
  ) async {
    final bloc = await _pump(tester, _loaded(178), [_loaded(180)]);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final offset = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(offset, greaterThan(0));

    bloc.add(LoadProfileEvent());
    await tester.pump();
    await tester.pump();
    final spinnerShown = _spinner.evaluate().isNotEmpty;
    // the load done before any expect, so no timer outlives a failure
    await tester.pump(const Duration(milliseconds: 200));
    expect(spinnerShown, isFalse);
    expect(find.text('180 cm'), findsOneWidget);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      offset,
    );
  });

  testWidgets('a state after the loaded one still shows', (tester) async {
    final bloc = await _pump(tester, _loaded(178), [_OtherState()]);
    await tester.pumpAndSettle();
    expect(_spinner, findsNothing);
    bloc.add(LoadProfileEvent());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // The page's catch-all for a state it has no screen for.
    expect(_spinner, findsOneWidget);
    expect(find.text('178 cm'), findsNothing);
  });

  testWidgets('on a tablet the list stays a phone column, centred', (
    tester,
  ) async {
    await _pump(tester, _loaded(178), []);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpAndSettle();
    for (final id in ['profile-height', 'profile-activity']) {
      final rect = tester.getRect(find.bySemanticsIdentifier(id));
      expect(rect.width, lessThanOrEqualTo(600), reason: id);
      expect(rect.center.dx, closeTo(600, 1), reason: id);
    }
  });

  // Profile weight files today's weigh-in as Home does: it says what it
  // replaces, and Undo brings that one back.
  testWidgets('a weight set on You replaces today\'s with an Undo', (
    tester,
  ) async {
    final add = RecordingAddWeightLogUsecase();
    await _pump(tester, _loaded(178), [], weighIns: _SlowWeighIns());
    locator
      ..registerSingleton<AddWeightLogUsecase>(add)
      ..registerSingleton<GetUserUsecase>(_User());
    await tester.pumpAndSettle();
    final row = find.text('Profile weight');
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(row);
    // the weigh-ins load from disk before the dialog opens
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.textContaining('Replaces today'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '84.2');
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(add.entries.single.weightKg, 84.2);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(add.entries, hasLength(2));
    expect(add.entries.last.weightKg, 85);
  });
}
