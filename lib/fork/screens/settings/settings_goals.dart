part of 'settings_screen.dart';

/// "Carbs 60% · Fat 25%": a unit on each number, so a lone "%" never wraps
/// onto a line of its own at large text, and no-break spaces inside each
/// "Carbs 60%" and before each dot, so a line breaks only after a dot.
String percentsLine(List<(String, int)> parts) =>
    [for (final (label, n) in parts) '$label\u00a0$n%'].join('\u00a0· ');

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
      // What sets the target, then what splits it, then the day it counts
      _categoryHeader(context, palette, 'Calorie Target'),
      _SettingsGroup(
        palette: palette,
        tiles: [
          _GoalPlannerTile(palette: palette, unit: state.bodyWeightUnit),
          const AdaptiveSettingsTile(),
          // The weigh-in and
          // check-in reminders are under Reminders
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
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
      _categoryHeader(context, palette, 'Nutrition'),
      _SettingsGroup(
        palette: palette,
        tiles: [
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
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
      // Not "Day Start", which the row under it already says
      _categoryHeader(context, palette, 'Diary'),
      _SettingsGroup(
        palette: palette,
        tiles: [
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
    if (kcal != 0 &&
        adjustmentOverridden(
          AdaptiveStore.settings.value,
          hasCheckIn: _hasCheckIn,
        )) {
      return '${energyText(context, kcal, signed: true)}. $_notUsed';
    }
    return kcal == 0 ? 'None' : energyText(context, kcal, signed: true);
  }

  /// "Carbs 60% · Fat 25% · Protein 15%", in the user's macro order.
  String? _macroSplitText() {
    final config = _goalsConfig;
    if (config == null) return null;
    int pct(double? fraction, int fallback) =>
        ((fraction ?? fallback / 100) * 100).round();
    final split = percentsLine(
      inMacroOrder(
        carbs: ('Carbs', pct(config.userCarbGoalPct, 60)),
        fat: ('Fat', pct(config.userFatGoalPct, 25)),
        protein: ('Protein', pct(config.userProteinGoalPct, 15)),
      ),
    );
    return splitOverridden(AdaptiveStore.settings.value)
        ? '$split. $_notUsed'
        : split;
  }

  String? _mealSharesText() {
    final shares = _goalsConfig?.mealKcalSharesPct;
    if (shares == null) return null;
    return percentsLine([
      ('Breakfast', shares[ConfigEntity.mealKeyBreakfast] ?? 0),
      ('Lunch', shares[ConfigEntity.mealKeyLunch] ?? 0),
      ('Dinner', shares[ConfigEntity.mealKeyDinner] ?? 0),
      ('Snack', shares[ConfigEntity.mealKeySnack] ?? 0),
    ]);
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

const _notUsed = 'Not used: your target sets this';

/// Whether a target of the fork's stands in for the kcal adjustment: the
/// adaptive one only from its first check-in, until then the formula's goal
/// stands, adjustment and all.
bool adjustmentOverridden(
  AdaptiveSettings settings, {
  required bool hasCheckIn,
}) => settings.fixedTarget || (settings.adaptiveTarget && hasCheckIn);

/// Whether grams of the fork's stand in for the macro split.
bool splitOverridden(AdaptiveSettings settings) =>
    settings.macroProgram != null ||
    (settings.fixedTarget && settings.fixedMacros != null);

/// The Goal planner row: the goal running, or what the planner does.
class _GoalPlannerTile extends StatefulWidget {
  final AppPalette palette;
  final BodyWeightUnit unit;

  const _GoalPlannerTile({required this.palette, required this.unit});

  @override
  State<_GoalPlannerTile> createState() => _GoalPlannerTileState();
}

class _GoalPlannerTileState extends State<_GoalPlannerTile> {
  PhasePlan? _plan;

  Future<void> _read() async {
    PhasePlan? plan;
    try {
      plan = await PhaseStore().plan();
    } catch (_) {
      // No store in a test: no plan.
    }
    if (mounted) setState(() => _plan = plan);
  }

  @override
  void initState() {
    super.initState();
    _read();
    PhaseStore.changes.addListener(_read);
  }

  @override
  void dispose() {
    PhaseStore.changes.removeListener(_read);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final until = plan == null
        ? null
        : DateFormat.MMMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).format(plan.end.subtract(const Duration(hours: 12)));
    return _SettingsTile(
      identifier: 'settings-goal-planner',
      palette: widget.palette,
      icon: Icons.flag_rounded,
      title: 'Goal planner',
      subtitle: plan == null
          ? 'A cut, maintenance or bulk, step by step'
          : '${goalTitle(plan, widget.unit)} · '
                '${DateTime.now().isBefore(plan.end) ? 'until' : 'ended'} '
                '$until',
      showChevron: true,
      onTap: () => openGoalPlanner(context),
    );
  }
}
