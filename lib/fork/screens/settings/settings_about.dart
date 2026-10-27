part of 'settings_screen.dart';

/// The About section: privacy, disclaimer, sources, error reports and the about dialog.
extension _AboutSettings on _SettingsScreenState {
  List<Widget> _aboutRows(
    BuildContext context,
    SettingsLoadedState state,
    AppPalette palette,
  ) {
    return [
      // On its own page the title says it
      if (widget.embedded)
        _categoryHeader(context, palette, S.of(context).settingsCategoryAbout),
      _SettingsGroup(
        palette: palette,
        tiles: [
          _SettingsTile(
            palette: palette,
            icon: Icons.policy_rounded,
            title: S.of(context).settingsPrivacySettings,
            onTap: () => _showPrivacyDialog(
              context,
              state.sendAnonymousData,
              isDemoData: state.isDemoData,
            ),
          ),
          _SettingsTile(
            palette: palette,
            icon: Icons.description_rounded,
            title: S.of(context).settingsDisclaimerLabel,
            onTap: () => _showDisclaimerDialog(context),
          ),
          _SettingsTile(
            palette: palette,
            icon: Icons.menu_book_rounded,
            title: S.of(context).settingsSourcesLabel,
            showChevron: true,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SourcesScreen())),
          ),
          _SettingsTile(
            palette: palette,
            icon: Icons.bug_report_rounded,
            title: S.of(context).settingsReportErrorLabel,
            onTap: () => _showReportErrorDialog(context),
          ),
          // The version running, and its update
          UpdateStatus(
            version: state.versionNumber,
            builder: (subtitle, onTap) => _SettingsTile(
              identifier: 'settings-updates',
              palette: palette,
              icon: Icons.system_update_rounded,
              title: 'Updates',
              subtitle: subtitle,
              onTap: onTap,
            ),
          ),
          _SettingsTile(
            palette: palette,
            icon: Icons.error_outline_rounded,
            title: 'About OpenBite',
            onTap: () => _showAboutDialog(context),
          ),
        ],
      ),
      const SizedBox(height: Dimens.spacing24),
      AppBannerVersion(versionNumber: state.versionNumber),
    ];
  }

  void _showDisclaimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return const DisclaimerDialog();
      },
    );
  }

  void _showReportErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(S.of(context).settingsReportErrorLabel),
          content: Text(S.of(context).reportErrorDialogText),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(S.of(context).dialogCancelLabel),
            ),
            TextButton(
              onPressed: () async {
                _reportError(context);
                Navigator.of(context).pop();
              },
              child: Text(S.of(context).dialogOKLabel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _reportError(BuildContext context) async {
    final reportUri = Uri.parse(
      "mailto:${AppConst.reportErrorEmail}?subject=Report_Error",
    );

    if (await canLaunchUrl(reportUri)) {
      launchUrl(reportUri);
    } else {
      // Cannot open email app, show error snackbar
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).errorOpeningEmail)),
        );
      }
    }
  }

  void _showPrivacyDialog(
    BuildContext context,
    bool hasAcceptedAnonymousData, {
    required bool isDemoData,
  }) async {
    // Crash reporting is not meaningful on synthetic demo data and would
    // still attach release diagnostics to a session that holds no real
    // user profile — keep the control off and locked while isDemoData.
    bool switchActive = isDemoData ? false : hasAcceptedAnonymousData;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(S.of(context).settingsPrivacySettings),
          content: StatefulBuilder(
            builder:
                (
                  BuildContext context,
                  void Function(void Function()) setState,
                ) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(S.of(context).sendCrashReports),
                        value: switchActive,
                        onChanged: isDemoData
                            ? null
                            : (bool value) {
                                setState(() {
                                  switchActive = value;
                                });
                              },
                      ),
                      // Keep meal photos 24 h for leftovers (D14)
                      const KeepMealPhotosSwitch(),
                      if (isDemoData) ...[
                        const SizedBox(height: 8),
                        Text(
                          S.of(context).settingsDemoPrivacyNote,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
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
                final accepted = isDemoData ? false : switchActive;
                await _settingsBloc.setHasAcceptedAnonymousData(accepted);
                if (!accepted) Sentry.close();
                _settingsBloc.add(LoadSettingsEvent());
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
              child: Text(S.of(context).dialogOKLabel),
            ),
          ],
        );
      },
    );
  }

  void _showAboutDialog(BuildContext context) async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (context.mounted) {
      showAboutDialog(
        context: context,
        applicationName: S.of(context).appTitle,
        // OpenBite's logo
        applicationIcon: const OpenBiteLogo(size: 40),
        applicationVersion: aboutVersion(packageInfo.version),
        applicationLegalese: S.of(context).appLicenseLabel,
        children: [
          const AboutUpdateRow(),
          TextButton(
            onPressed: () {
              _launchSourceCodeUrl(context);
            },
            child: Row(
              children: [
                const Icon(Icons.code_outlined),
                const SizedBox(width: 8.0),
                Text(S.of(context).settingsSourceCodeLabel),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              _launchPrivacyPolicyUrl(context);
            },
            child: Row(
              children: [
                const Icon(Icons.policy_outlined),
                const SizedBox(width: 8.0),
                Text(S.of(context).privacyPolicyLabel),
              ],
            ),
          ),
        ],
      );
    }
  }

  void _launchSourceCodeUrl(BuildContext context) async {
    final sourceCodeUri = Uri.parse(AppConst.sourceCodeUrl);
    _launchUrl(context, sourceCodeUri);
  }

  void _launchPrivacyPolicyUrl(BuildContext context) async {
    final privacyPolicyUri = Uri.parse(
      URLConst.privacyPolicyFor(Localizations.localeOf(context).languageCode),
    );
    _launchUrl(context, privacyPolicyUri);
  }

  void _launchUrl(BuildContext context, Uri url) async {
    if (await canLaunchUrl(url)) {
      launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      // Cannot open browser app, show error snackbar
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).errorOpeningBrowser)),
        );
      }
    }
  }
}
