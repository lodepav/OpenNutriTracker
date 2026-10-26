part of 'settings_screen.dart';

/// The Goals section: its rows and the dialogs they open.
extension _GoalsSettings on _SettingsScreenState {
  List<Widget> _goalsRows(
    BuildContext context,
    SettingsLoadedState state,
    AppPalette palette,
  ) {
    return [
      if (widget.embedded)
        _categoryHeader(context, palette, S.of(context).settingsCategoryGoals),
      _SettingsGroup(
        palette: palette,
        tiles: [
          // The old Calculations dialog had grown into a wall of
          // sliders covering daily kcal, macros, per-meal split,
          // ten nutrient goals, and the diary day boundary. Each
          // is now its own focused entry so people can find the
          // setting they want and only see the controls for it.
          _SettingsTile(
            identifier: 'settings-kcal-goal-info',
            palette: palette,
            icon: Icons.functions_rounded,
            title: S.of(context).settingsKcalGoalInfoLabel,
            showChevron: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const KcalGoalInfoScreen(),
              ),
            ),
          ),
          _SettingsTile(
            identifier: 'settings-kcal-adjustment',
            palette: palette,
            icon: Icons.calculate_rounded,
            title: state.usesKilojoules
                ? S.of(context).settingsKjAdjustmentLabel
                : S.of(context).settingsKcalAdjustmentLabel,
            onTap: () => _showKcalAdjustmentDialog(context),
          ),
          const AdaptiveSettingsTile(),
          // The weigh-in and
          // check-in reminders are under Reminders
          _SettingsTile(
            identifier: 'settings-macro-split',
            palette: palette,
            icon: Icons.pie_chart_rounded,
            title: S.of(context).settingsMacroSplitLabel,
            onTap: () => _showMacroSplitDialog(context),
          ),
          _SettingsTile(
            identifier: 'settings-per-meal-share',
            palette: palette,
            icon: Icons.restaurant_menu_rounded,
            title: S.of(context).settingsPerMealKcalShareLabel,
            onTap: () => _showPerMealKcalShareDialog(context),
          ),
          _SettingsTile(
            identifier: 'settings-nutrient-goals',
            palette: palette,
            icon: Icons.spa_rounded,
            title: S.of(context).settingsNutrientGoalsLabel,
            showChevron: true,
            onTap: () => _openNutrientGoalsScreen(context),
          ),
          _SettingsTile(
            identifier: 'settings-day-boundary',
            palette: palette,
            icon: Icons.schedule_rounded,
            title: S.of(context).settingsDayStartLabel,
            onTap: () => _showDayBoundaryDialog(context),
          ),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
    ];
  }

  void _showKcalAdjustmentDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => KcalAdjustmentDialog(
        settingsBloc: _settingsBloc,
        profileBloc: _profileBloc,
        homeBloc: _homeBloc,
      ),
    );
  }

  void _showMacroSplitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) =>
          MacroSplitDialog(settingsBloc: _settingsBloc, homeBloc: _homeBloc),
    );
  }

  void _showPerMealKcalShareDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => PerMealKcalShareDialog(
        settingsBloc: _settingsBloc,
        homeBloc: _homeBloc,
        calendarDayBloc: _calendarDayBloc,
      ),
    );
  }

  void _openNutrientGoalsScreen(BuildContext context) {
    // Today's bars first, the goal list behind
    // Edit
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NutrientGoalsOverview(
          onEdit: (context) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NutrientGoalsScreen(
                settingsBloc: _settingsBloc,
                profileBloc: _profileBloc,
                diaryBloc: _diaryBloc,
                calendarDayBloc: _calendarDayBloc,
                homeBloc: _homeBloc,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDayBoundaryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => DiaryDayBoundaryDialog(
        settingsBloc: _settingsBloc,
        homeBloc: _homeBloc,
        diaryBloc: _diaryBloc,
        calendarDayBloc: _calendarDayBloc,
      ),
    );
  }
}
