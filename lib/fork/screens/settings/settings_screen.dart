// The fork's own Settings (D23): copied whole from upstream's
// lib/features/settings/settings_screen.dart at 1ab4940a, where it had become
// mostly the fork's. Upstream's changes to that file are ported here by hand
// (fork/tools/upstream-copies.sh). SettingsScreenArguments stays upstream's,
// so a caller's arguments are read here the same.
// Each section's rows and the dialogs they open are in a part of their own
// (settings_<section>.dart), the shared rows in settings_tiles.dart.
import 'dart:async';

import 'package:opennutritracker/features/settings/settings_screen.dart'
    show SettingsScreenArguments;
export 'package:opennutritracker/features/settings/settings_screen.dart'
    show SettingsScreenArguments;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/l10n/shipped_locales.dart';
import 'package:opennutritracker/core/presentation/sources_screen.dart';
import 'package:opennutritracker/core/presentation/widgets/app_banner_version.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/ai_assist_summary.dart';
import 'package:opennutritracker/core/presentation/widgets/badged_title.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/presentation/widgets/disclaimer_dialog.dart';
import 'package:opennutritracker/core/domain/usecase/delete_all_user_data_usecase.dart';
import 'package:opennutritracker/core/utils/app_const.dart';
import 'package:opennutritracker/core/utils/app_locale_service.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/utils/app_locale_sync.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/daily_reminder_scheduler.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:opennutritracker/core/utils/locale_provider.dart';
import 'package:opennutritracker/core/utils/reload_diary_and_trends.dart';
import 'package:opennutritracker/core/utils/theme_mode_provider.dart';
import 'package:opennutritracker/core/utils/url_const.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/export_import_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/import_custom_food_data_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/food_sources_screen.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/health_sync_screen.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/nutrient_visibility_screen.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/run_ai_endpoint_probe_usecase.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_assist_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/fork/leftovers/meal_photo_cache.dart';
// The trend and target switches (D13)
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';
import 'package:opennutritracker/fork/goal/goal_plan_view.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/reminders/reminders_ui.dart';
// The automatic backup's settings (phase 2)
import 'package:opennutritracker/fork/backup/auto_backup_ui.dart';
import 'package:opennutritracker/fork/history/history_import.dart';
import 'package:opennutritracker/fork/export/csv_export.dart';
// The user's Open Food Facts account
import 'package:opennutritracker/fork/off/off_contribution_ui.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/fork/brand/openbite_logo.dart';
import 'package:opennutritracker/fork/settings/settings_index.dart';
// OpenBite's version, and its update
import 'package:opennutritracker/fork/update/update_notice.dart';
import 'package:opennutritracker/fork/version.dart';
import 'package:opennutritracker/fork/report/nutrient_goals_overview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/diary_day_boundary_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_adjustment_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/macro_split_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/nutrient_goals_screen.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/per_meal_kcal_share_dialog.dart';

part 'settings_goals.dart';
part 'settings_units.dart';
part 'settings_reminders.dart';
part 'settings_food.dart';
part 'settings_data.dart';
part 'settings_appearance.dart';
part 'settings_about.dart';
part 'settings_tiles.dart';

/// What the settings route was opened *for*.
///
/// This screen is long enough that "go to Settings" is not an answer on its
/// own: pushed plain it lands on Units & Energy, four category groups above
/// the AI row, and a Pixel 6 pass (#830) took several attempts to scroll to
/// that row while deliberately looking for it. A caller that already knows
/// which control the user came to change says so here, and the screen opens
/// that control itself rather than leaving them to hunt for it. #852.
///
/// Arguments are optional — every other way in pushes the route without
/// them, and a null or foreign `arguments` is simply the plain screen.
class SettingsScreen extends StatefulWidget {
  /// When true, renders the settings list inline (no Scaffold/AppBar, the list
  /// shrink-wraps) so it can be hosted inside the You tab's scroll. The pushed
  /// route uses the default (full-screen) form.
  final bool embedded;

  // The section this page shows; the plain
  // route lists the sections
  final SettingsSection? section;

  const SettingsScreen({super.key, this.embedded = false, this.section});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsBloc _settingsBloc;
  late ProfileBloc _profileBloc;
  late HomeBloc _homeBloc;
  late DiaryBloc _diaryBloc;
  late CalendarDayBloc _calendarDayBloc;
  late TrendsBloc _trendsBloc;
  late AiCredentialStorage _aiCredentials;
  late AiEndpointProbeRunner _aiProbeRunner;

  /// Null until the first read completes; the tile shows no subtitle rather
  /// than briefly claiming the feature is off.
  bool? _aiConfigured;
  String? _aiEndpoint;
  bool _aiEnabled = false;

  /// What Goals & nutrition shows under its rows (H6); null until read.
  ConfigEntity? _goalsConfig;

  /// Null when the stored name is unrecognised — see #753.
  AiProvider? _aiProvider;

  /// Whether the route's arguments have been acted on.
  ///
  /// `didChangeDependencies` runs again for anything this screen depends on —
  /// a theme change, a locale change, the keyboard, and the dialog's own
  /// route going up — so an unguarded read reopens a dialog that is already
  /// open, and closing it leaves a second behind.
  bool _routeRequestHandled = false;

  @override
  void initState() {
    _aiCredentials = locator<AiCredentialStorage>();
    _aiProbeRunner = locator<AiEndpointProbeRunner>();
    _settingsBloc = locator<SettingsBloc>();
    _profileBloc = locator<ProfileBloc>();
    _homeBloc = locator<HomeBloc>();
    _diaryBloc = locator<DiaryBloc>();
    _calendarDayBloc = locator<CalendarDayBloc>();
    _trendsBloc = locator<TrendsBloc>();
    super.initState();
    _refreshAiAssistState();
    _refreshGoalsConfig();
    // SettingsBloc is registered as a singleton so the previous
    // SettingsLoadedState survives across screen visits. The cache
    // count and on-disk size in particular are written in the
    // background by search and barcode-scan flows, so reading them
    // once at the bloc's first transition out of SettingsInitial
    // leaves stale values on the screen for the rest of the session.
    // Refresh on every entry instead.
    _settingsBloc.add(LoadSettingsEvent());
  }

  /// Whether a route was covering this screen's own the last time we looked.
  bool _wasCovered = false;

  /// Reloads when the user comes back to this screen from a route pushed
  /// over it.
  ///
  /// `initState` covers the pushed form, which is built fresh on every visit,
  /// but the embedded form lives on in the You tab: the search and scan
  /// screens that fill the cache are pushed over it and popped, and nothing
  /// rebuilt it, so the "Clear cached items" count stayed at what it was
  /// when Settings was first expanded (#1368). `isCurrentOf` makes this run
  /// again whenever the route stops or starts being the top one.
  void _reloadOnReturn() {
    final isCurrent = ModalRoute.isCurrentOf(context) ?? true;
    if (isCurrent && _wasCovered) _settingsBloc.add(LoadSettingsEvent());
    _wasCovered = !isCurrent;
  }

  /// Acts on what the caller asked the settings route for — see
  /// [SettingsScreenArguments].
  ///
  /// The embedded form is skipped: it has no route of its own, so what it
  /// would read is the host route's arguments, which are not addressed to it.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reloadOnReturn();
    if (_routeRequestHandled || widget.embedded) return;
    _routeRequestHandled = true;
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is! SettingsScreenArguments || !arguments.openAiAssist) {
      return;
    }
    // After the frame, not during it: this runs inside a build, and
    // `showDialog` pushes a route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openAiAssistDialog(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = BlocBuilder<SettingsBloc, SettingsState>(
      bloc: _settingsBloc,
      // Every save and toggle reloads, and the reload starts with a loading
      // state. Swapping the list for a spinner then threw its scroll position
      // away and put the user back at the top, out of sight of the row they
      // just changed (#1368). Only the first load shows the spinner; a reload
      // keeps the list until the fresh values arrive.
      buildWhen: (previous, current) =>
          !(previous is SettingsLoadedState && current is SettingsLoadingState),
      builder: (context, state) {
        if (state is SettingsInitial) {
          _settingsBloc.add(LoadSettingsEvent());
        } else if (state is SettingsLoadingState) {
          return const Center(child: CircularProgressIndicator());
        } else if (state is SettingsLoadedState) {
          final palette = paletteOf(context);
          // The sections, each a page
          if (!widget.embedded && widget.section == null) {
            return SettingsIndex(
              summaries: _forkSummaries(context, state),
              onOpen: _forkOpen,
              footer: AppBannerVersion(versionNumber: state.versionNumber),
            );
          }
          // Built once, then wrapped in one of two shapes — because the
          // embedded form is not a scrollable and should not pretend to be.
          //
          // It used to be a `ListView` either way, `shrinkWrap` with
          // `NeverScrollableScrollPhysics` when embedded: a viewport that
          // cannot scroll, nested inside the You tab's viewport that can.
          // Rows outside the outer viewport are marked `isHidden`, and which
          // of them cleared was decided by that outer list's offset — flung,
          // it moves in large non-overlapping jumps, and a band in the middle
          // was never uncovered. Four rows (the food databases, Health
          // Connect, AI Assist, custom food import) could not be reached by a
          // screen reader at all. #974.
          //
          // A `Column` has no viewport, so nothing here hides anything and
          // the outer list alone decides what is on screen, exactly as it
          // does for every other row of the You tab. It renders the same: a
          // shrink-wrapped, unscrollable list of fixed children *is* a
          // Column, with a viewport in the way.
          final children = <Widget>[
            // A page for each section
            if (_forkShows(SettingsSection.goals))
              ..._goalsRows(context, state, palette),
            if (_forkShows(SettingsSection.units))
              ..._unitsRows(context, state, palette),
            if (_forkShows(SettingsSection.reminders))
              ..._remindersRows(context, state, palette),
            if (_forkShows(SettingsSection.food))
              ..._foodRows(context, state, palette),
            if (_forkShows(SettingsSection.data))
              ..._dataRows(context, state, palette),
            if (_forkShows(SettingsSection.appearance))
              ..._appearanceRows(context, state, palette),
            if (_forkShows(SettingsSection.about))
              ..._aboutRows(context, state, palette),
          ];

          if (widget.embedded) {
            return Column(mainAxisSize: MainAxisSize.min, children: children);
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(
              Dimens.spacing16,
              Dimens.spacing16,
              Dimens.spacing16,
              Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
            ),
            children: children,
          );
        }
        return const SizedBox();
      },
    );
    if (widget.embedded) return body;
    return Scaffold(
      // A section's page is titled with it;
      // the list of them can be searched
      appBar: AppBar(
        title: Text(widget.section?.title ?? S.of(context).settingsLabel),
        actions: [
          if (widget.section == null)
            Semantics(
              identifier: 'settings-search',
              child: IconButton(
                tooltip: 'Search settings',
                icon: const Icon(Icons.search_rounded),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsSearchPage(
                      entries: _forkEntries(context),
                      onOpen: (section) => _forkOpen(section, replace: true),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: body,
    );
  }

  /// The embedded form shows every section, as it did.
  bool _forkShows(SettingsSection section) =>
      widget.embedded || widget.section == section;

  void _forkOpen(SettingsSection section, {bool replace = false}) {
    final route = MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(section: section),
    );
    final navigator = Navigator.of(context);
    replace ? navigator.pushReplacement(route) : navigator.push(route);
  }

  /// What is set in each section now, under its name.
  Map<SettingsSection, String> _forkSummaries(
    BuildContext context,
    SettingsLoadedState state,
  ) {
    final s = S.of(context);
    return {
      SettingsSection.goals: 'Energy, macros, meals, nutrients, day start',
      SettingsSection.units: [
        state.bodyWeightUnit.getLabel(context),
        state.usesKilojoules ? 'kJ' : 'kcal',
        state.usesImperialFoodUnits ? 'imperial' : 'metric',
      ].join(' · '),
      SettingsSection.reminders: state.notificationsEnabled
          ? s.settingsNotificationsTimeLabel(
              _formatNotificationTime(
                state.notificationHour,
                state.notificationMinute,
              ),
            )
          : 'Daily reminder off · weigh-in and check-in',
      SettingsSection.food: 'Food sources, Open Food Facts, AI assist',
      SettingsSection.data: 'Backup, $healthPlatformName, import, export',
      SettingsSection.appearance: 'Theme, colour, language, what screens show',
      SettingsSection.about:
          'OpenBite ${state.versionNumber} · privacy · sources',
    };
  }

  /// Every row by its name, for the search.
  List<SettingsEntry> _forkEntries(BuildContext context) {
    final s = S.of(context);
    SettingsEntry e(
      String label,
      SettingsSection section, [
      String also = '',
    ]) => (label: label, section: section, also: also);
    const goals = SettingsSection.goals;
    const units = SettingsSection.units;
    const reminders = SettingsSection.reminders;
    const food = SettingsSection.food;
    const data = SettingsSection.data;
    const appearance = SettingsSection.appearance;
    const about = SettingsSection.about;
    return [
      e(s.settingsKcalGoalInfoLabel, goals),
      e(s.settingsKcalAdjustmentLabel, goals),
      e(
        'Trend and calorie target',
        goals,
        'expenditure adaptive formula fixed check-in activity steps',
      ),
      e(s.settingsMacroSplitLabel, goals),
      e(s.settingsPerMealKcalShareLabel, goals),
      e(s.settingsNutrientGoalsLabel, goals),
      e(s.settingsDayStartLabel, goals),
      e(s.settingsFoodUnitsLabel, units),
      e(s.settingsHeightUnitsLabel, units),
      e(s.settingsBodyWeightUnitLabel, units),
      e(s.settingsEnergyUnitLabel, units, 'kcal kJ calories joules'),
      e(s.settingsDefaultToRawFoodUnitsLabel, units),
      e(s.settingsNotificationsLabel, reminders),
      e('Weigh-in and check-in reminders', reminders),
      e('Search sources', food, 'food databases'),
      e(s.settingsAiAssistLabel, food),
      e('Open Food Facts account', food),
      e(healthPlatformName, data, 'sync workouts weight steps'),
      e('Import history', data),
      e(s.importCustomFoodDataLabel, data),
      e(s.exportImportAppDataLabel, data, 'backup restore json'),
      e('Automatic backup', data, 'restore'),
      e('Export diary as CSV', data, 'spreadsheet'),
      e(s.clearOffCacheLabel, data),
      e(s.manageProfilesLabel, data, 'profiles switch'),
      e(s.settingsDeleteAllDataLabel, data),
      e(s.settingsThemeLabel, appearance, 'dark light'),
      e(s.settingsAccentColourTitle, appearance, 'color'),
      e(s.settingsLanguageLabel, appearance),
      e(s.settingsShowActivityTracking, appearance),
      e(s.settingsShowMealMacros, appearance),
      e(s.settingsShowMicronutrientsLabel, appearance),
      e(s.settingsNutrientsLabel, appearance),
      e('Macro order', appearance),
      e('Diary by the hour', appearance),
      e('Show water', appearance),
      e('Show fasting', appearance),
      e(s.settingsPrivacySettings, about),
      e(s.settingsDisclaimerLabel, about),
      e(s.settingsSourcesLabel, about),
      e(s.settingsReportErrorLabel, about),
      e('Updates', about),
      e('About OpenBite', about, 'licences version'),
    ];
  }

  Widget _categoryHeader(
    BuildContext context,
    AppPalette palette,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing12,
        Dimens.spacing4,
        Dimens.spacing12,
        Dimens.spacing8,
      ),
      // A heading TalkBack can jump between
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _refreshGoalsConfig() async {
    if (!locator.isRegistered<GetConfigUsecase>()) return; // widget tests
    final config = await locator<GetConfigUsecase>().getConfig();
    if (mounted) setState(() => _goalsConfig = config);
  }

  Future<void> _refreshAiAssistState() async {
    final summary = await _aiCredentials.readSummary();
    if (!mounted) return;
    setState(() {
      _aiConfigured = summary.configured;
      _aiEnabled = summary.enabled;
      _aiEndpoint = summary.endpoint;
      _aiProvider = summary.provider;
    });
  }

  /// [setState] for the parts' extensions, which can not call it.
  void _update(VoidCallback fn) => setState(fn);
}
