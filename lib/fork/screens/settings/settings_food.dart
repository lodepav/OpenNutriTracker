part of 'settings_screen.dart';

/// The Food section: search sources, their cache, Open Food Facts and AI
/// assist.
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
          // The search's cached results
          _SettingsTile(
            palette: palette,
            icon: Icons.cached_rounded,
            title: S.of(context).clearOffCacheLabel,
            subtitle: state.offCacheCount == 0
                ? 'Nothing cached'
                : S
                      .of(context)
                      .clearOffCacheSubtitle(
                        state.offCacheCount,
                        _formatBytes(state.offCacheSizeBytes),
                      ),
            enabled: state.offCacheCount > 0,
            onTap: () => _confirmClearOffCache(context),
          ),
          // #1518: one switch for every AI surface — the AI add, Photo
          // log, the AI badges, the set-up offer and the AI meal
          // assistance row — and, while off, nothing is sent to a model.
          // Device-wide, like the keys it sits beside. Shown while off,
          // so it can be turned back on.
          _SettingsSwitchTile(
            identifier: 'settings-show-ai',
            palette: palette,
            icon: Icons.auto_awesome_rounded,
            title: S.of(context).settingsShowAiFeaturesLabel,
            subtitle: S.of(context).settingsShowAiFeaturesSubtitle,
            value: !_aiHidden,
            onChanged: (bool value) async {
              _update(() => _aiHidden = !value);
              await _aiCredentials.setHidden(!value);
              await _refreshAiAssistState();
            },
          ),
          if (!_aiHidden)
            _SettingsTile(
              identifier: 'settings-ai-assist',
              palette: palette,
              icon: Icons.auto_awesome_rounded,
              title: S.of(context).settingsAiAssistLabel,
              subtitle: _aiAssistSubtitle(context),
              badge: S.of(context).aiAssistExperimentalLabel,
              onTap: () => _openAiAssistDialog(context),
            ),
          // the photo sheet's text, readable after it stopped showing
          if (!_aiHidden)
            _SettingsTile(
              identifier: 'settings-ai-photo-disclosure',
              palette: palette,
              icon: Icons.photo_camera_outlined,
              title: 'What happens to a meal photo',
              onTap: () => showPhotoDisclosure(context, _aiCredentials),
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

  Future<void> _confirmClearOffCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(S.of(context).clearOffCacheConfirmTitle),
        content: Text(S.of(context).clearOffCacheConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(S.of(context).dialogCancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(S.of(context).dialogOKLabel),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _settingsBloc.clearOffCache();
    }
  }

  /// Format a byte count for display in the cache-clear tile subtitle.
  /// Uses KB up to 1 MB, then MB with one decimal place above that.
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
