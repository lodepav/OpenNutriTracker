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
          _SettingsTile(
            identifier: 'settings-goal-planner',
            palette: palette,
            icon: Icons.flag_rounded,
            title: 'Goal planner',
            subtitle: 'A cut, maintenance or bulk, step by step',
            showChevron: true,
            onTap: () => openGoalPlanner(context),
          ),
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
            subtitle: _kcalAdjustmentText(context),
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
            subtitle: _macroSplitText(),
            onTap: () => _showMacroSplitDialog(context),
          ),
          _SettingsTile(
            identifier: 'settings-per-meal-share',
            palette: palette,
            icon: Icons.restaurant_menu_rounded,
            title: S.of(context).settingsPerMealKcalShareLabel,
            subtitle: _mealSharesText(),
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
            subtitle: _dayStartText(context, state),
            onTap: () => _showDayBoundaryDialog(context),
          ),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
    ];
  }

  String? _kcalAdjustmentText(BuildContext context) {
    final config = _goalsConfig;
    if (config == null) return null;
    final kcal = config.userKcalAdjustment ?? 0;
    return kcal == 0 ? 'None' : energyText(context, kcal, signed: true);
  }

  /// "Carbs 60 · Fat 25 · Protein 15 %", in the user's macro order.
  String? _macroSplitText() {
    final config = _goalsConfig;
    if (config == null) return null;
    String pct(double? fraction, int fallback) =>
        '${((fraction ?? fallback / 100) * 100).round()}';
    final parts = inMacroOrder(
      carbs: 'Carbs ${pct(config.userCarbGoalPct, 60)}',
      fat: 'Fat ${pct(config.userFatGoalPct, 25)}',
      protein: 'Protein ${pct(config.userProteinGoalPct, 15)}',
    );
    return '${parts.join(' · ')} %';
  }

  String? _mealSharesText() {
    final shares = _goalsConfig?.mealKcalSharesPct;
    if (shares == null) return null;
    return [
      'Breakfast ${shares[ConfigEntity.mealKeyBreakfast] ?? 0}',
      'Lunch ${shares[ConfigEntity.mealKeyLunch] ?? 0}',
      'Dinner ${shares[ConfigEntity.mealKeyDinner] ?? 0}',
      'Snack ${shares[ConfigEntity.mealKeySnack] ?? 0} %',
    ].join(' · ');
  }

  String _dayStartText(BuildContext context, SettingsLoadedState state) {
    final hour = state.dayStartOffsetHours;
    final minute = state.dayStartOffsetMinutes;
    if (hour == 0 && minute == 0) return 'Midnight';
    return TimeOfDay(hour: hour, minute: minute).format(context);
  }

  Future<void> _showKcalAdjustmentDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => KcalAdjustmentDialog(
        settingsBloc: _settingsBloc,
        profileBloc: _profileBloc,
        homeBloc: _homeBloc,
      ),
    );
    _refreshGoalsConfig();
  }

  Future<void> _showMacroSplitDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) =>
          MacroSplitDialog(settingsBloc: _settingsBloc, homeBloc: _homeBloc),
    );
    _refreshGoalsConfig();
  }

  Future<void> _showPerMealKcalShareDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => PerMealKcalShareDialog(
        settingsBloc: _settingsBloc,
        homeBloc: _homeBloc,
        calendarDayBloc: _calendarDayBloc,
      ),
    );
    _refreshGoalsConfig();
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
