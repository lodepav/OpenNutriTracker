part of 'settings_screen.dart';

/// The Food section: search sources, Open Food Facts and AI assist.
extension _FoodSettings on _SettingsScreenState {
  List<Widget> _foodRows(
    BuildContext context,
    SettingsLoadedState state,
    AppPalette palette,
  ) {
    return [
      if (widget.embedded)
        _categoryHeader(context, palette, SettingsSection.food.title),
      _SettingsGroup(
        palette: palette,
        tiles: [
          _SettingsTile(
            identifier: 'settings-food-sources',
            palette: palette,
            icon: Icons.travel_explore_rounded,
            // Not the section's name again
            title: 'Search sources',
            subtitle: S.of(context).settingsFoodSourcesSubtitle,
            showChevron: true,
            onTap: () => _openFoodSourcesScreen(context),
          ),
          _SettingsTile(
            identifier: 'settings-ai-assist',
            palette: palette,
            icon: Icons.auto_awesome_rounded,
            title: S.of(context).settingsAiAssistLabel,
            subtitle: _aiAssistSubtitle(context),
            badge: S.of(context).aiAssistExperimentalLabel,
            onTap: () => _openAiAssistDialog(context),
          ),
          const OffAccountTile(),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
    ];
  }

  /// The tile is the only place the destination is visible without opening
  /// the dialog, so the "on" state names it.
  ///
  /// The switch itself lives in [aiAssistSubtitle], shared with onboarding's
  /// Other options page since #728 — one exhaustive site rather than two that
  /// can disagree about who is being sent to.
  String? _aiAssistSubtitle(BuildContext context) => aiAssistSubtitle(
    S.of(context),
    configured: _aiConfigured,
    endpoint: _aiEndpoint,
    enabled: _aiEnabled,
    provider: _aiProvider,
  );

  Future<void> _openAiAssistDialog(BuildContext context) async {
    await AiAssistDialog.show(
      context,
      _aiCredentials,
      probeRunner: _aiProbeRunner,
    );
    // Unconditionally, not only when the dialog reports a change: the
    // subtitle is cheap to recompute and a stale one misdescribes what
    // leaves the device.
    await _refreshAiAssistState();
  }

  void _openFoodSourcesScreen(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const FoodSourcesScreen()));
  }
}
