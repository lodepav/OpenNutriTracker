part of 'settings_screen.dart';

/// The Units section: its rows and the unit pickers.
extension _UnitsSettings on _SettingsScreenState {
  List<Widget> _unitsRows(
    BuildContext context,
    SettingsLoadedState state,
    AppPalette palette,
  ) {
    return [
      if (widget.embedded)
        _categoryHeader(context, palette, S.of(context).settingsCategoryUnits),
      _SettingsGroup(
        palette: palette,
        tiles: [
          _SettingsTile(
            identifier: 'settings-food-units',
            palette: palette,
            icon: Icons.kitchen_rounded,
            title: S.of(context).settingsFoodUnitsLabel,
            subtitle: state.usesImperialFoodUnits
                ? S.of(context).settingsFoodUnitsImperial
                : S.of(context).settingsFoodUnitsMetric,
            onTap: () =>
                _showFoodUnitsDialog(context, state.usesImperialFoodUnits),
          ),
          _SettingsTile(
            identifier: 'settings-height-units',
            palette: palette,
            icon: Icons.height_rounded,
            title: S.of(context).settingsHeightUnitsLabel,
            subtitle: state.usesImperialHeightUnits
                ? S.of(context).settingsHeightUnitsImperial
                : S.of(context).settingsHeightUnitsMetric,
            onTap: () =>
                _showHeightUnitsDialog(context, state.usesImperialHeightUnits),
          ),
          _SettingsTile(
            identifier: 'settings-body-weight-unit',
            palette: palette,
            icon: Icons.monitor_weight_rounded,
            title: S.of(context).settingsBodyWeightUnitLabel,
            subtitle: state.bodyWeightUnit.getLabel(context),
            onTap: () =>
                _showBodyWeightUnitDialog(context, state.bodyWeightUnit),
          ),
          _SettingsTile(
            identifier: 'settings-energy-unit',
            palette: palette,
            icon: Icons.local_fire_department_rounded,
            title: S.of(context).settingsEnergyUnitLabel,
            subtitle: state.usesKilojoules
                ? S.of(context).energyUnitKjLabel
                : S.of(context).energyUnitKcalLabel,
            onTap: () => _showEnergyUnitDialog(context, state.usesKilojoules),
          ),
          // #1126: opt out of the serving-first default so the
          // meal-detail dropdown lands on the food unit (g, oz,
          // ml, fl oz) straight away. Sits after Energy unit in
          // the Units & Energy group since it steers the same
          // meal-detail dropdown. Off preserves the pre-existing
          // behaviour — serving wins whenever the food has one.
          _SettingsSwitchTile(
            identifier: 'settings-default-raw-food-units',
            palette: palette,
            icon: Icons.straighten_rounded,
            title: S.of(context).settingsDefaultToRawFoodUnitsLabel,
            subtitle: S.of(context).settingsDefaultToRawFoodUnitsSubtitle,
            value: state.defaultToRawFoodUnits,
            onChanged: (bool value) {
              _settingsBloc.setDefaultToRawFoodUnits(value);
              _settingsBloc.add(LoadSettingsEvent());
            },
          ),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
    ];
  }

  void _showFoodUnitsDialog(
    BuildContext context,
    bool currentUsesImperial,
  ) async {
    bool selectedUsesImperial = currentUsesImperial;
    final shouldUpdate = await showDialog<bool?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          title: Text(S.of(context).settingsFoodUnitsLabel),
          content: StatefulBuilder(
            builder:
                (
                  BuildContext context,
                  void Function(void Function()) setState,
                ) {
                  return RadioGroup<bool>(
                    groupValue: selectedUsesImperial,
                    onChanged: (value) {
                      setState(() {
                        selectedUsesImperial = value ?? false;
                      });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<bool>(
                          title: Text(S.of(context).settingsFoodUnitsMetric),
                          value: false,
                        ),
                        RadioListTile<bool>(
                          title: Text(S.of(context).settingsFoodUnitsImperial),
                          value: true,
                        ),
                      ],
                    ),
                  );
                },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).dialogCancelLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(S.of(context).dialogOKLabel),
            ),
          ],
        );
      },
    );
    if (shouldUpdate == true) {
      _settingsBloc.setUsesImperialFoodUnits(selectedUsesImperial);
      _settingsBloc.add(LoadSettingsEvent());
      _homeBloc.add(LoadItemsEvent());
      _diaryBloc.add(const LoadDiaryYearEvent());
    }
  }

  void _showHeightUnitsDialog(
    BuildContext context,
    bool currentUsesImperial,
  ) async {
    bool selectedUsesImperial = currentUsesImperial;
    final shouldUpdate = await showDialog<bool?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          title: Text(S.of(context).settingsHeightUnitsLabel),
          content: StatefulBuilder(
            builder:
                (
                  BuildContext context,
                  void Function(void Function()) setState,
                ) {
                  return RadioGroup<bool>(
                    groupValue: selectedUsesImperial,
                    onChanged: (value) {
                      setState(() {
                        selectedUsesImperial = value ?? false;
                      });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<bool>(
                          title: Text(S.of(context).settingsHeightUnitsMetric),
                          value: false,
                        ),
                        RadioListTile<bool>(
                          title: Text(
                            S.of(context).settingsHeightUnitsImperial,
                          ),
                          value: true,
                        ),
                      ],
                    ),
                  );
                },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).dialogCancelLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(S.of(context).dialogOKLabel),
            ),
          ],
        );
      },
    );
    if (shouldUpdate == true) {
      _settingsBloc.setUsesImperialHeightUnits(selectedUsesImperial);
      _settingsBloc.add(LoadSettingsEvent());
      _profileBloc.add(LoadProfileEvent());
    }
  }

  void _showBodyWeightUnitDialog(
    BuildContext context,
    BodyWeightUnit currentUnit,
  ) async {
    BodyWeightUnit selectedUnit = currentUnit;
    final shouldUpdate = await showDialog<bool?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          title: Text(S.of(context).settingsBodyWeightUnitLabel),
          content: StatefulBuilder(
            builder:
                (
                  BuildContext context,
                  void Function(void Function()) setState,
                ) {
                  return RadioGroup<BodyWeightUnit>(
                    groupValue: selectedUnit,
                    onChanged: (value) {
                      setState(() {
                        selectedUnit = value ?? BodyWeightUnit.kg;
                      });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<BodyWeightUnit>(
                          title: Text(S.of(context).kgLabel),
                          value: BodyWeightUnit.kg,
                        ),
                        RadioListTile<BodyWeightUnit>(
                          title: Text(S.of(context).lbsLabel),
                          value: BodyWeightUnit.lb,
                        ),
                        RadioListTile<BodyWeightUnit>(
                          title: Text(S.of(context).stLabel),
                          value: BodyWeightUnit.st,
                        ),
                      ],
                    ),
                  );
                },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).dialogCancelLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(S.of(context).dialogOKLabel),
            ),
          ],
        );
      },
    );
    if (shouldUpdate == true) {
      _settingsBloc.setBodyWeightUnit(selectedUnit);
      _settingsBloc.add(LoadSettingsEvent());
      // Body weight shows on the profile card, the home weight chip, and the
      // Trends weight chart, so all three need to re-read the new unit. Keep
      // the Trends range the user had picked rather than snapping back to the
      // default.
      _profileBloc.add(LoadProfileEvent());
      _homeBloc.add(const LoadItemsEvent());
      final trendsState = _trendsBloc.state;
      _trendsBloc.add(
        LoadTrendsEvent(
          rangeDays: trendsState is TrendsLoaded ? trendsState.rangeDays : 7,
        ),
      );
    }
  }

  // #177: Pick between kilocalories (default) and kilojoules for the
  // energy display unit. Internal storage stays in kcal; this only
  // toggles how energy is rendered everywhere it appears.
  void _showEnergyUnitDialog(
    BuildContext context,
    bool currentUsesKilojoules,
  ) async {
    bool selectedUsesKilojoules = currentUsesKilojoules;
    final shouldUpdate = await showDialog<bool?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          title: Text(S.of(context).settingsEnergyUnitLabel),
          content: StatefulBuilder(
            builder:
                (
                  BuildContext context,
                  void Function(void Function()) setState,
                ) {
                  return RadioGroup<bool>(
                    groupValue: selectedUsesKilojoules,
                    onChanged: (value) {
                      setState(() {
                        selectedUsesKilojoules = value ?? false;
                      });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<bool>(
                          title: Text(S.of(context).energyUnitKcalLabel),
                          value: false,
                        ),
                        RadioListTile<bool>(
                          title: Text(S.of(context).energyUnitKjLabel),
                          value: true,
                        ),
                      ],
                    ),
                  );
                },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).dialogCancelLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(S.of(context).dialogOKLabel),
            ),
          ],
        );
      },
    );
    if (shouldUpdate == true) {
      _settingsBloc.setUsesKilojoules(selectedUsesKilojoules);
      _settingsBloc.add(LoadSettingsEvent());
      if (context.mounted) {
        Provider.of<EnergyUnitProvider>(
          context,
          listen: false,
        ).updateUsesKilojoules(selectedUsesKilojoules);
      }
    }
  }
}
