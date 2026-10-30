import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_bmi_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/calories_profile_info_dialog.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/bounds/validator.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_display_format.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_gender_dialog.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_goal_dialog.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_height_dialog.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_weekly_weight_goal_dialog.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_pal_category_dialog.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_target_weight_dialog.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_weight_dialog.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/water_goal_dialog.dart';
import 'package:opennutritracker/fork/units/weight_text.dart' show bodyWeightText; // [fork] S121
import 'package:opennutritracker/fork/display/display_prefs.dart'; // [fork] S144
import 'package:opennutritracker/fork/goal/goal_progress_page.dart'; // [fork] S121
import 'package:opennutritracker/fork/goal/goal_you_tile.dart'; // [fork] S121
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S121 you-tab
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/presentation/sources_screen.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/bmi_info_screen.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/profile_switcher_sheet.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:opennutritracker/fork/display/home_tiles.dart';
import 'package:opennutritracker/fork/you/you_widgets.dart';
// [/fork]

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  /// Room below the last row for the centre-docked Add button, which rides
  /// half of its 56 dp above the bottom bar and so over the end of this list.
  /// The old 32 dp left the last row 5 dp above the button, close enough that
  /// a tap meant for it could open the Add sheet instead (#1368).
  static const double _fabClearance = 56 / 2 + Dimens.spacing32;

  late ProfileBloc _profileBloc;

  @override
  void initState() {
    _profileBloc = locator<ProfileBloc>();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      bloc: _profileBloc,
      builder: (context, state) {
        if (state is ProfileInitial) {
          _profileBloc.add(LoadProfileEvent());
          return _getLoadingContent();
        } else if (state is ProfileLoadingState) {
          return _getLoadingContent();
        } else if (state is ProfileLoadedState) {
          return _getLoadedContent(
            context,
            state.userBMI,
            state.userEntity,
            state.bodyWeightUnit,
            state.usesImperialHeightUnits,
            state.effectiveWaterGoalMl,
          );
        } else {
          return _getLoadingContent();
        }
      },
    );
  }

  Widget _getLoadingContent() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _getLoadedContent(
    BuildContext context,
    UserBMIEntity userBMIEntity,
    UserEntity user,
    BodyWeightUnit bodyWeightUnit,
    bool usesImperialHeightUnits,
    int effectiveWaterGoalMl,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing12,
        Dimens.spacing16,
        _fabClearance,
      ),
      // [fork] S121 you-tab: MacroFactor's You (YouA): who is active with a
      // Switch button, four tiles (the weight trend, the goal, the daily
      // budget, the BMI), then short lists: Plan, Body and Tools. Every
      // row of upstream's is still here; Settings opens its screen
      // (upstream: a large BMI ring, five icon groups and Settings inline)
      children: [
        YouProfileRow(
          profile: locator<GetProfilesUsecase>().getActiveProfile(),
          details: [
            '${user.age}',
            formatHeight(
              user.heightCM,
              usesImperialHeightUnits,
              cmLabel: S.of(context).cmLabel,
              ftLabel: S.of(context).ftLabel,
              inLabel: S.of(context).inLabel,
            ),
            user.gender.getName(context),
          ].join(' · '),
          onSwitch: () => showProfileSwitcherSheet(context),
        ),
        YouTiles(
          tiles: [
            WeightTile(
              key: ValueKey(user.weightKG),
              weightKg: user.weightKG,
              unit: bodyWeightUnit,
              load: () async => locator<GetWeightLogUsecase>().getAllEntries(),
              identifier: 'profile-weight-trend',
              hint: 'Open the weight history',
              onTap: () => Navigator.of(
                context,
              ).pushNamed(NavigationOptions.weightHistoryRoute),
            ),
            GoalYouTile(
              title: S.of(context).goalLabel,
              profileGoal:
                  (user.weeklyWeightGoalKg ?? 0) != 0 ||
                  user.targetWeightKg != null,
              value: switch (user.goal) {
                UserWeightGoalEntity.loseWeight => 'Lose',
                UserWeightGoalEntity.maintainWeight => 'Keep',
                UserWeightGoalEntity.gainWeight => 'Gain',
              },
              note: _forkRate(context, user, bodyWeightUnit),
              below: user.targetWeightKg == null
                  ? S.of(context).profileTargetWeightNotSetLabel
                  : 'Target ${bodyWeightText(context, user.targetWeightKg!, bodyWeightUnit)}',
              onTap: () => openGoalProgress(context, bodyWeightUnit),
            ),
            BudgetTile(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const KcalGoalInfoScreen(),
                ),
              ),
            ),
            YouTile(
              identifier: 'profile-bmi',
              title: S.of(context).bmiLabel,
              value: '${userBMIEntity.bmiValue.roundToPrecision(1)}',
              note: userBMIEntity.nutritionalStatus.getName(context),
              below: 'How it is worked out',
              hint: 'How the BMI is worked out',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BmiInfoScreen()),
              ),
            ),
          ],
        ),
        YouSection(
          title: 'Plan',
          rows: [
            YouRow(
              identifier: 'profile-activity',
              label: S.of(context).activityLabel,
              value: user.pal.getName(context),
              onTap: () => _showSetPALCategoryDialog(context, user),
            ),
            YouRow(
              identifier: 'profile-goal',
              label: S.of(context).goalLabel,
              value: user.goal.getName(context),
              onTap: () => _showSetGoalDialog(context, user),
            ),
            YouRow(
              identifier: 'profile-weekly-goal',
              label: S.of(context).weeklyWeightGoalLabel,
              value: _weeklyGoalSubtitle(context, user, bodyWeightUnit),
              onTap: () => _showSetWeeklyWeightGoalDialog(
                context,
                user,
                bodyWeightUnit,
              ),
            ),
            YouRow(
              identifier: 'profile-target-weight',
              label: S.of(context).profileTargetWeightLabel,
              value: user.targetWeightKg == null
                  ? S.of(context).profileTargetWeightNotSetLabel
                  : bodyWeightText(context, user.targetWeightKg!, bodyWeightUnit),
              onTap: () =>
                  _showSetTargetWeightDialog(context, user, bodyWeightUnit),
            ),
            // The taper scales against the target, so only with one.
            if (user.targetWeightKg != null)
              YouSwitchRow(
                identifier: 'profile-calorie-taper',
                label: S.of(context).settingsCaloriesTaperLabel,
                detail: S.of(context).settingsCaloriesTaperDescription,
                value: user.caloriesTaperEnabled,
                onChanged: (v) => _profileBloc.setCaloriesTaperEnabled(v),
              ),
          ],
        ),
        YouSection(
          title: 'Body',
          rows: [
            YouRow(
              identifier: 'profile-weight',
              label: S.of(context).weightLabel,
              value: bodyWeightText(context, user.weightKG, bodyWeightUnit),
              detail: user.targetWeightKg == null
                  ? null
                  : _targetWeightSubLabel(context, user, bodyWeightUnit),
              onTap: () => _showSetWeightDialog(context, user, bodyWeightUnit),
            ),
            YouRow(
              identifier: 'profile-height',
              label: S.of(context).heightLabel,
              value: formatHeight(
                user.heightCM,
                usesImperialHeightUnits,
                cmLabel: S.of(context).cmLabel,
                ftLabel: S.of(context).ftLabel,
                inLabel: S.of(context).inLabel,
              ),
              onTap: () =>
                  _showSetHeightDialog(context, user, usesImperialHeightUnits),
            ),
            YouRow(
              identifier: 'profile-age',
              label: S.of(context).ageLabel,
              value: S.of(context).yearsLabel(user.age),
              onTap: () => _showSetBirthdayDialog(context, user),
            ),
            YouRow(
              identifier: 'profile-gender',
              label: S.of(context).genderLabel,
              value: user.gender.getName(context),
              onTap: () => _showSetGenderDialog(context, user),
            ),
            if (user.gender == UserGenderEntity.nonBinary)
              YouRow(
                identifier: 'profile-calories-profile',
                label: S.of(context).caloriesProfileInfoTitle,
                value:
                    (user.caloriesProfile ?? CaloriesProfileEntity.averaged)
                        .getName(context),
                onTap: () => _showCaloriesProfileDialog(context, user),
              ),
          ],
        ),
        // [fork] S144 hide-features: water and fasting go when hidden
        ListenableBuilder(
          listenable: Listenable.merge([
            DisplayPrefs.showWater,
            DisplayPrefs.showFasting,
          ]),
          builder: (context, _) => YouSection(
            title: 'Tools',
            rows: [
              YouRow(
                identifier: 'profile-weight-history',
                label: S.of(context).profileWeightHistoryTitle,
                onTap: () => Navigator.of(
                  context,
                ).pushNamed(NavigationOptions.weightHistoryRoute),
              ),
              if (DisplayPrefs.showFasting.value)
                YouRow(
                  identifier: 'profile-fasting-entry',
                  label: S.of(context).profileFastingEntry,
                  onTap: () => Navigator.of(
                    context,
                  ).pushNamed(NavigationOptions.fastingRoute),
                ),
              if (DisplayPrefs.showWater.value)
                YouRow(
                  identifier: 'profile-water-goal',
                  label: S.of(context).settingsWaterGoalLabel,
                  value: '$effectiveWaterGoalMl ${S.of(context).mlLabel}',
                  onTap: () => _showWaterGoalDialog(context),
                ),
              YouRow(
                identifier: 'profile-recipes',
                label: S.of(context).recipesLabel,
                onTap: () => Navigator.of(
                  context,
                ).pushNamed(NavigationOptions.recipesRoute),
              ),
              YouRow(
                identifier: 'profile-sources',
                label: S.of(context).sourcesIconTooltip,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SourcesScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
        // [/fork]
        // S147: Settings on its own, not one of the tools
        YouSection(
          title: 'App',
          rows: [
            YouRow(
              identifier: 'profile-settings',
              label: S.of(context).settingsLabel,
              onTap: () =>
                  Navigator.of(context).pushNamed(NavigationOptions.settingsRoute),
            ),
          ],
        ),
      ],
      // [/fork]
    );
  }

  // [fork] S121 you-tab
  /// The goal tile's weekly rate, unsigned: the goal says which way.
  String? _forkRate(BuildContext context, UserEntity user, BodyWeightUnit unit) {
    final kg = user.weeklyWeightGoalKg;
    if (kg == null || kg == 0) return null;
    return switch (unit) {
      BodyWeightUnit.kg => '${kg.abs().toStringAsFixed(2)} ${S.of(context).kgLabel}/wk',
      _ => '${UnitCalc.kgToLbs(kg.abs()).toStringAsFixed(2)} ${S.of(context).lbsLabel}/wk',
    };
  }
  // [/fork]

  Future<void> _showSetPALCategoryDialog(
    BuildContext context,
    UserEntity userEntity,
  ) async {
    final selectedPalCategory = await showDialog<UserPALEntity>(
      context: context,
      builder: (BuildContext context) => const SetPALCategoryDialog(),
    );
    if (selectedPalCategory != null) {
      userEntity.pal = selectedPalCategory;
      _profileBloc.updateUser(userEntity);
    }
  }

  String _weeklyGoalSubtitle(
    BuildContext context,
    UserEntity user,
    BodyWeightUnit bodyWeightUnit,
  ) {
    final goal = user.weeklyWeightGoalKg;
    if (goal == null) return S.of(context).weeklyWeightGoalNoneLabel;
    if (goal == 0.0) return S.of(context).goalMaintainWeight;
    switch (bodyWeightUnit) {
      case BodyWeightUnit.kg:
        final sign = goal > 0 ? '+' : '';
        return S.of(context).weeklyWeightGoalKgPerWeek('$sign${goal.toStringAsFixed(2)}');
      case BodyWeightUnit.lb:
        final displayLb = goal * 2.20462;
        final sign = displayLb > 0 ? '+' : '';
        return S.of(context).weeklyWeightGoalLbsPerWeek('$sign${displayLb.toStringAsFixed(2)}');
      case BodyWeightUnit.st:
        final displaySt = goal * 2.20462 / 14;
        final sign = displaySt > 0 ? '+' : '';
        return '$sign${displaySt.toStringAsFixed(2)} ${S.of(context).stLabel}'
            '${S.of(context).trendsPerWeekSuffix}';
    }
  }

  Future<void> _showSetWeeklyWeightGoalDialog(
    BuildContext context,
    UserEntity userEntity,
    BodyWeightUnit bodyWeightUnit,
  ) async {
    final result = await showDialog<WeeklyWeightGoalResult>(
      context: context,
      builder: (context) => SetWeeklyWeightGoalDialog(
        currentGoalKg: userEntity.weeklyWeightGoalKg,
        bodyWeightUnit: bodyWeightUnit,
      ),
    );
    switch (result) {
      // null when the framework returns from a back-button pop, treated
      // as cancellation alongside the explicit Cancel case.
      case null:
      case WeeklyWeightGoalCancelled():
        return;
      case WeeklyWeightGoalCleared():
        userEntity.weeklyWeightGoalKg = null;
      case WeeklyWeightGoalSet(:final kgPerWeek):
        userEntity.weeklyWeightGoalKg = kgPerWeek;
    }
    await _profileBloc.updateUser(userEntity);
  }

  Future<void> _showSetGoalDialog(
    BuildContext context,
    UserEntity userEntity,
  ) async {
    final selectedGoal = await showDialog<UserWeightGoalEntity>(
      context: context,
      builder: (BuildContext context) => const SetWeightGoalDialog(),
    );
    if (selectedGoal != null) {
      userEntity.goal = selectedGoal;
      _profileBloc.updateUser(userEntity);
    }
  }

  Future<void> _showSetHeightDialog(
    BuildContext context,
    UserEntity userEntity,
    bool usesImperialUnits,
  ) async {
    final selectedHeightCm = await showDialog<double>(
      context: context,
      builder: (context) => SetHeightDialog(
        userHeightCm: userEntity.heightCM,
        usesImperialUnits: usesImperialUnits,
      ),
    );
    if (selectedHeightCm != null) {
      userEntity.heightCM = selectedHeightCm;
      _profileBloc.updateUser(userEntity);
    }
  }

  Future<void> _showSetWeightDialog(
    BuildContext context,
    UserEntity userEntity,
    BodyWeightUnit bodyWeightUnit,
  ) async {
    final newKg = await showDialog<double>(
      context: context,
      builder: (context) => SetWeightDialog(
        initialKg: userEntity.weightKG,
        unit: bodyWeightUnit,
      ),
    );
    if (newKg != null) {
      final now = DateTime.now();
      await locator<AddWeightLogUsecase>().addEntry(
        WeightLogEntity(
          date: DateTime(now.year, now.month, now.day),
          weightKg: newKg,
        ),
      );

      // addEntry already persisted today's weight onto the user record, so
      // reload it and route through ProfileBloc.updateUser purely so the
      // profile screen, diary, and home all refresh in one go — mirrors
      // QuickWeightWidget._showWeightDialog on the home screen.
      final updatedUser = await locator<GetUserUsecase>().getUserData();
      await _profileBloc.updateUser(updatedUser);
    }
  }

  Future<void> _showSetTargetWeightDialog(
    BuildContext context,
    UserEntity userEntity,
    BodyWeightUnit bodyWeightUnit,
  ) async {
    // Seed the picker from the existing target if set, otherwise from the
    // user's current weight so the wheel doesn't snap to a wildly different
    // value on first use. The dialog returns a TargetWeightDialogResult so
    // we can distinguish "user cancelled" (null) from "user picked a value"
    // (set) and from "user explicitly cleared the target" (clear flag).
    final seedKg = userEntity.targetWeightKg ?? userEntity.weightKG;
    final result = await showDialog<TargetWeightDialogResult>(
      context: context,
      builder: (context) => SetTargetWeightDialog(
        initialKg: seedKg,
        hasExistingTarget: userEntity.targetWeightKg != null,
        unit: bodyWeightUnit,
      ),
    );
    if (result == null) return;
    if (result.clear) {
      userEntity.targetWeightKg = null;
    } else if (result.value != null) {
      // The dialog now returns kg directly.
      userEntity.targetWeightKg = result.value;
    }
    _profileBloc.updateUser(userEntity);
  }

  Future<void> _showSetBirthdayDialog(
    BuildContext context,
    UserEntity userEntity,
  ) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDatePickerMode: DatePickerMode.year,
      // Same bounds as onboarding: without them this picker accepted a
      // birthday in 2099, which turns the age fed to the calorie
      // calculation negative. Existing values are clamped so a birthday
      // stored by an older build can still open the picker.
      initialDate: ValueValidator.clampBirthday(userEntity.birthday),
      firstDate: ValueValidator.getFirstDate(),
      lastDate: ValueValidator.getLastDate(),
    );
    if (selectedDate != null) {
      userEntity.birthday = selectedDate;
      _profileBloc.updateUser(userEntity);
    }
  }

  Future<void> _showSetGenderDialog(
    BuildContext context,
    UserEntity userEntity,
  ) async {
    final selectedGender = await showDialog<UserGenderEntity>(
      context: context,
      builder: (BuildContext context) => const SetGenderDialog(),
    );
    if (selectedGender == null) return;
    userEntity.gender = selectedGender;

    // Switching to non-binary: prompt for hormone profile and persist BOTH
    // fields in a single updateUser call. Issuing two saves (one for the
    // gender, one for the profile) used to race — by the time the home
    // recomputed kcal, only the gender write had landed and the profile
    // was still null, so every choice rendered as "averaged".
    if (selectedGender == UserGenderEntity.nonBinary) {
      if (context.mounted) {
        final selected = await showDialog<CaloriesProfileEntity>(
          context: context,
          builder: (BuildContext context) => CaloriesProfileInfoDialog(
            initialProfile:
                userEntity.caloriesProfile ?? CaloriesProfileEntity.averaged,
          ),
        );
        if (selected != null) {
          userEntity.caloriesProfile = selected;
        } else {
          // User cancelled the picker but is now non-binary — store the
          // implicit default explicitly so reads don't keep falling back.
          userEntity.caloriesProfile ??= CaloriesProfileEntity.averaged;
        }
      }
    } else {
      // Switching back to binary — drop any previously set hormone profile.
      // The field is meaningless outside of nonBinary.
      userEntity.caloriesProfile = null;
    }

    await _profileBloc.updateUser(userEntity);
  }

  void _showWaterGoalDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => WaterGoalDialog(
        settingsBloc: locator<SettingsBloc>(),
        homeBloc: locator<HomeBloc>(),
      ),
    );
  }

  Future<void> _showCaloriesProfileDialog(
    BuildContext context,
    UserEntity userEntity,
  ) async {
    final selected = await showDialog<CaloriesProfileEntity>(
      context: context,
      builder: (BuildContext context) => CaloriesProfileInfoDialog(
        initialProfile:
            userEntity.caloriesProfile ?? CaloriesProfileEntity.averaged,
      ),
    );
    if (selected == null) return;
    userEntity.caloriesProfile = selected;
    await _profileBloc.updateUser(userEntity);
  }

  String _targetWeightSubLabel(
    BuildContext context,
    UserEntity user,
    BodyWeightUnit bodyWeightUnit,
  ) {
    final target = user.targetWeightKg;
    if (target == null) return '';
    final deltaKg = (target - user.weightKG).abs();
    // Treat "close enough" as reached — under 0.1 kg the noise in body
    // weight measurements outweighs the difference and a "you've reached
    // your target" message lands better than "0.0 kg to go".
    if (deltaKg < 0.1) {
      return S.of(context).profileTargetWeightReached;
    }
    final String formatted;
    switch (bodyWeightUnit) {
      case BodyWeightUnit.kg:
        formatted = '${deltaKg.toStringAsFixed(1)} ${S.of(context).kgLabel}';
      case BodyWeightUnit.lb:
        formatted =
            '${(deltaKg * 2.20462).toStringAsFixed(1)} ${S.of(context).lbsLabel}';
      case BodyWeightUnit.st:
        // Split at the one decimal this line prints, so a remainder that
        // rounds to 14 lb lands as the next whole stone instead.
        final (stones, pounds) = UnitCalc.kgToStLb(deltaKg, poundsDecimals: 1);
        formatted =
            '$stones ${S.of(context).stLabel} ${pounds.toStringAsFixed(1)} ${S.of(context).lbsLabel}';
    }
    return S.of(context).profileTargetWeightToGo(formatted);
  }
}

/// A quiet section label that gives the grouped cards a consistent rhythm —
/// muted, lightly tracked, sitting just above the card it introduces.
// [fork] S121 you-tab: upstream's _ProfileTile, _ProfileSwitchTile and
// _IconChip went with the You rows (YouRow, YouSwitchRow).
