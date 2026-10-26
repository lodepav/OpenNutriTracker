part of 'settings_screen.dart';

/// The Appearance section: theme, colour, language and what screens show.
extension _AppearanceSettings on _SettingsScreenState {
  List<Widget> _appearanceRows(
    BuildContext context,
    SettingsLoadedState state,
    AppPalette palette,
  ) {
    return [
      // The page's own title already says it
      if (widget.embedded)
        _categoryHeader(
          context,
          palette,
          S.of(context).settingsCategoryAppearance,
        ),
      _SettingsGroup(
        palette: palette,
        tiles: [
          _SettingsTile(
            palette: palette,
            icon: Icons.brightness_medium_rounded,
            title: S.of(context).settingsThemeLabel,
            // The row says what is set
            subtitle: switch (state.appTheme) {
              AppThemeEntity.light => S.of(context).settingsThemeLightLabel,
              AppThemeEntity.dark => S.of(context).settingsThemeDarkLabel,
              AppThemeEntity.system =>
                S.of(context).settingsThemeSystemDefaultLabel,
            },
            onTap: () => _showThemeDialog(context, state.appTheme),
          ),
          _SettingsTile(
            identifier: 'settings-accent-colour',
            palette: palette,
            icon: Icons.palette_rounded,
            title: S.of(context).settingsAccentColourTitle,
            subtitle: _accentSubtitle(
              context,
              useMaterialYou: state.useMaterialYou,
              accentColor: state.accentColor,
            ),
            trailing: _AccentTrailingSwatch(
              useMaterialYou: state.useMaterialYou,
              accentColor: state.accentColor,
            ),
            onTap: () => Navigator.of(
              context,
            ).pushNamed(NavigationOptions.accentColourRoute),
          ),
          _SettingsTile(
            palette: palette,
            icon: Icons.language_rounded,
            title: S.of(context).settingsLanguageLabel,
            subtitle:
                _localeDisplayName(state.selectedLocale) ??
                S.of(context).settingsThemeSystemDefaultLabel,
            onTap: () => _showLanguageDialog(context, state.selectedLocale),
          ),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
      _categoryHeader(context, palette, S.of(context).settingsCategoryDisplay),
      _SettingsGroup(
        palette: palette,
        tiles: [
          _SettingsSwitchTile(
            palette: palette,
            icon: Icons.directions_run_rounded,
            title: S.of(context).settingsShowActivityTracking,
            value: state.showActivityTracking,
            onChanged: (bool value) {
              _settingsBloc.setShowActivityTracking(value);
              _settingsBloc.add(LoadSettingsEvent());
              _homeBloc.add(LoadItemsEvent());
              // DiaryBloc is a lazy singleton so its loaded state
              // survives navigation. Without an explicit reload here
              // the diary keeps the stale flag and the per-day
              // Activity section stays visible after toggling off.
              _diaryBloc.add(const LoadDiaryYearEvent());
            },
          ),
          _SettingsSwitchTile(
            palette: palette,
            icon: Icons.bar_chart_rounded,
            title: S.of(context).settingsShowMealMacros,
            value: state.showMealMacros,
            onChanged: (bool value) async {
              // Every reload below reads the flag back, so it must
              // be stored first.
              await _settingsBloc.setShowMealMacros(value);
              _settingsBloc.add(LoadSettingsEvent());
              _homeBloc.add(LoadItemsEvent());
              // The Diary's meal headers read the flag from
              // DiaryBloc, which keeps it until reloaded.
              reloadDiaryAndTrends();
            },
          ),
          _SettingsSwitchTile(
            palette: palette,
            icon: Icons.science_rounded,
            title: S.of(context).settingsShowMicronutrientsLabel,
            value: state.showMicronutrients,
            onChanged: (bool value) {
              _settingsBloc.setShowMicronutrients(value);
              _settingsBloc.add(LoadSettingsEvent());
            },
          ),
          // #160 follow-up: lets the user pick which nutrients show
          // on the diary's daily nutrient panel. Lives next to the
          // meal-detail micronutrient toggle above; both shape what
          // the user sees from the same underlying nutrient data.
          _SettingsTile(
            identifier: 'settings-nutrient-visibility',
            palette: palette,
            icon: Icons.tune_rounded,
            title: S.of(context).settingsNutrientsLabel,
            subtitle: S.of(context).settingsNutrientsSubtitle,
            onTap: () => _openNutrientVisibilityScreen(context),
          ),
          // The macros' order everywhere, and
          // the Diary by the hour
          const MacroOrderTile(),
          const DiaryByHourTile(),
          // Water and fasting can go
          ShowFeatureTile.water(),
          ShowFeatureTile.fasting(),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
    ];
  }

  void _openNutrientVisibilityScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NutrientVisibilityScreen()),
    );
  }

  void _showThemeDialog(BuildContext context, AppThemeEntity currentAppTheme) {
    AppThemeEntity selectedTheme = currentAppTheme;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          title: Text(S.of(context).settingsThemeLabel),
          content: StatefulBuilder(
            builder:
                (
                  BuildContext context,
                  void Function(void Function()) setState,
                ) {
                  return RadioGroup(
                    groupValue: selectedTheme,
                    onChanged: (value) {
                      setState(() {
                        selectedTheme = value as AppThemeEntity;
                      });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile(
                          title: Text(
                            S.of(context).settingsThemeSystemDefaultLabel,
                          ),
                          value: AppThemeEntity.system,
                        ),
                        RadioListTile(
                          title: Text(S.of(context).settingsThemeLightLabel),
                          value: AppThemeEntity.light,
                        ),
                        RadioListTile(
                          title: Text(S.of(context).settingsThemeDarkLabel),
                          value: AppThemeEntity.dark,
                        ),
                      ],
                    ),
                  );
                },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(S.of(context).dialogCancelLabel),
            ),
            TextButton(
              onPressed: () async {
                _settingsBloc.setAppTheme(selectedTheme);
                _settingsBloc.add(LoadSettingsEvent());
                _update(() {
                  // Update Theme
                  Provider.of<ThemeModeProvider>(
                    context,
                    listen: false,
                  ).updateTheme(selectedTheme);
                });
                Navigator.of(context).pop();
              },
              child: Text(S.of(context).dialogOKLabel),
            ),
          ],
        );
      },
    );
  }

  String? _localeDisplayName(String? code) => shippedLocales[code];

  void _showLanguageDialog(BuildContext context, String? currentLocale) {
    String selectedCode = currentLocale ?? _systemLocale;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          title: Text(S.of(context).settingsLanguageLabel),
          content: StatefulBuilder(
            builder:
                (
                  BuildContext context,
                  void Function(void Function()) setState,
                ) {
                  return RadioGroup<String>(
                    groupValue: selectedCode,
                    onChanged: (v) =>
                        setState(() => selectedCode = v as String),
                    // The list outgrows a short phone, so it scrolls
                    // between the title and the buttons (#1331).
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<String>(
                            title: Text(
                              S.of(context).settingsThemeSystemDefaultLabel,
                            ),
                            value: _systemLocale,
                          ),
                          ...shippedLocales.entries.map(
                            (e) => RadioListTile<String>(
                              title: Text(e.value),
                              value: e.key,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).dialogCancelLabel),
            ),
            TextButton(
              onPressed: () {
                final locale = selectedCode.isEmpty ? null : selectedCode;
                final localeProvider = Provider.of<LocaleProvider>(
                  context,
                  listen: false,
                );
                final configRepo = locator<ConfigRepository>();
                // Keep Android's per-app language picker in step, so someone
                // who later looks there finds the language they chose here
                // rather than a stale one. A no-op off Android and below
                // API 33. The pushed value is read back and recorded, so a
                // later clear in Android's picker is honoured even if this
                // pick never fires a locale-change callback. The whole write
                // shares the lock runtime reconciliation runs under, so an
                // OS clear being reconciled cannot undo it halfway.
                unawaited(
                  applyInAppLocaleChoice(
                    lock: localeSyncLock,
                    localeCode: locale,
                    persistSelectedLocale: _settingsBloc.setSelectedLocale,
                    applyToApp: () {
                      _settingsBloc.add(LoadSettingsEvent());
                      localeProvider.updateLocale(
                        locale != null ? Locale(locale) : null,
                      );
                    },
                    pushToSystem: AppLocaleService.setApplicationLocale,
                    readSystemTag: AppLocaleService.getApplicationLocale,
                    markLocaleSyncSeeded: configRepo.setLocaleSyncSeeded,
                    clearLocaleSyncSeeded: configRepo.clearLocaleSyncSeeded,
                  ),
                );
                Navigator.of(context).pop();
              },
              child: Text(S.of(context).dialogOKLabel),
            ),
          ],
        );
      },
    );
  }
}

// Sentinel value meaning "follow system locale"
const _systemLocale = '';

String _accentSubtitle(
  BuildContext context, {
  required bool useMaterialYou,
  required int? accentColor,
}) {
  final isAndroid = Theme.of(context).platform == TargetPlatform.android;
  if (isAndroid && useMaterialYou) {
    return S.of(context).settingsAccentSubtitleMaterialYou;
  }
  if (accentColor != null) {
    return S.of(context).settingsAccentSubtitleCustom;
  }
  return S.of(context).settingsAccentSubtitleDefault;
}
