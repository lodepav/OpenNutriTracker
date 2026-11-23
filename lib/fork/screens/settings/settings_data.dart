part of 'settings_screen.dart';

/// The Data section: health sync, imports, exports, backups, profiles and deleting.
extension _DataSettings on _SettingsScreenState {
  List<Widget> _dataRows(
    BuildContext context,
    SettingsLoadedState state,
    AppPalette palette,
  ) {
    final error = Theme.of(context).colorScheme.error;
    return [
      // MacroFactor's Data A, the backup
      // first, then what comes in and what goes out
      if (widget.embedded)
        _categoryHeader(context, palette, S.of(context).settingsCategoryData),
      _SettingsGroup(
        palette: palette,
        tiles: [
          const AutoBackupTile(),
          _SettingsTile(
            identifier: 'settings-health-sync',
            palette: palette,
            icon: Icons.favorite_rounded,
            // The platform's own product name, so the row reads as
            // the thing users already know ("Health Connect"), not
            // as a generic feature label.
            title: healthPlatformName,
            // All the page syncs
            subtitle: 'Workouts, weight, body fat and nutrition',
            showChevron: true,
            onTap: () => _openHealthSyncScreen(context),
          ),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
      _categoryHeader(context, palette, 'Bring data in'),
      _SettingsGroup(
        palette: palette,
        tiles: [
          // Another app's history in
          const HistoryImportTile(),
          _SettingsTile(
            identifier: 'settings-import-custom-food',
            palette: palette,
            icon: Icons.restaurant_menu_rounded,
            title: S.of(context).importCustomFoodDataLabel,
            onTap: () => _showImportCustomFoodDataDialog(context),
          ),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
      _categoryHeader(context, palette, 'Take data out'),
      _SettingsGroup(
        palette: palette,
        tiles: [
          // The diary for a spreadsheet
          const CsvExportTile(),
          _SettingsTile(
            palette: palette,
            icon: Icons.import_export_rounded,
            title: S.of(context).exportImportAppDataLabel,
            subtitle: 'Everything, to a file or back from one',
            onTap: () => _showExportImportDialog(context),
          ),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
      // Where a careful user looks
      // for them (they also sit on the You tab)
      _categoryHeader(context, palette, 'Profiles'),
      _SettingsGroup(
        palette: palette,
        tiles: [
          _SettingsTile(
            identifier: 'settings-manage-profiles',
            palette: palette,
            icon: Icons.people_alt_rounded,
            title: S.of(context).manageProfilesLabel,
            subtitle: 'Switch, add or rename',
            showChevron: true,
            onTap: () => Navigator.of(
              context,
            ).pushNamed(NavigationOptions.manageProfilesRoute),
          ),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
      _categoryHeader(context, palette, 'Start over'),
      _SettingsGroup(
        palette: palette,
        tiles: [
          _SettingsTile(
            identifier: 'settings-delete-all-data',
            palette: palette,
            icon: Icons.delete_forever_rounded,
            iconColor: error,
            titleColor: error,
            title: S.of(context).settingsDeleteAllDataLabel,
            // The shared AI key is named here too: it goes for every profile
            subtitle: "This profile's data and the shared AI key",
            onTap: () => _confirmDeleteAllData(context),
          ),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
    ];
  }

  void _openHealthSyncScreen(BuildContext context) {
    // The named route rather than a direct push: Health Connect can ask for
    // this same screen from outside the app (#927), and one registration is
    // easier to keep honest than two ways in.
    Navigator.of(context).pushNamed(NavigationOptions.healthSyncRoute);
  }

  void _showExportImportDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => ExportImportDialog());
  }

  void _showImportCustomFoodDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => ImportCustomFoodDataDialog(),
    );
  }

  Future<void> _confirmDeleteAllData(BuildContext context) async {
    final l10n = S.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(l10n.settingsDeleteAllDataConfirmTitle),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // "For good" up front: at 200% the last line is below the fold
              'Deletes this profile for good: its goals, logged foods, '
              'weigh-ins, photos and everything else it holds, and the AI '
              'key every profile shares.',
            ),
            SizedBox(height: Dimens.spacing12),
            Text('Other profiles, custom foods and recipes stay.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(false);
              _showExportImportDialog(context);
            },
            child: const Text('Export first'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.dialogCancelLabel),
          ),
          FilledButton(
            style: destructiveFilledStyle(ctx),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.settingsDeleteAllDataConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await locator<DeleteAllUserDataUsecase>().deleteAll();
    if (!mounted) return;
    navigator.pushNamedAndRemoveUntil(
      NavigationOptions.onboardingRoute,
      (_) => false,
    );
  }
}
