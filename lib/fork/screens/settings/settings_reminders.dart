part of 'settings_screen.dart';

/// The Reminders section: the daily reminder and its time.
extension _RemindersSettings on _SettingsScreenState {
  List<Widget> _remindersRows(
    BuildContext context,
    SettingsLoadedState state,
    AppPalette palette,
  ) {
    return [
      _categoryHeader(
        context,
        palette,
        S.of(context).settingsNotificationsLabel,
      ),
      _SettingsGroup(
        palette: palette,
        tiles: [
          _SettingsSwitchTile(
            palette: palette,
            icon: Icons.notifications_rounded,
            title: S.of(context).settingsNotificationsLabel,
            subtitle: state.notificationsEnabled
                ? S
                      .of(context)
                      .settingsNotificationsTimeLabel(
                        _formatNotificationTime(
                          state.notificationHour,
                          state.notificationMinute,
                        ),
                      )
                : null,
            value: state.notificationsEnabled,
            onChanged: (bool value) =>
                _onNotificationToggled(context, value, state),
          ),
          if (state.notificationsEnabled)
            _SettingsTile(
              palette: palette,
              icon: Icons.access_time_rounded,
              title: S
                  .of(context)
                  .settingsNotificationsTimeLabel(
                    _formatNotificationTime(
                      state.notificationHour,
                      state.notificationMinute,
                    ),
                  ),
              onTap: () => _pickNotificationTime(
                context,
                TimeOfDay(
                  hour: state.notificationHour,
                  minute: state.notificationMinute,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
      _categoryHeader(context, palette, 'Weigh-in and check-in'),
      _SettingsGroup(
        palette: palette,
        tiles: [
          // Weigh-in and check-in
          const RemindersTile(),
        ],
      ),
      const SizedBox(height: Dimens.spacing20),
    ];
  }

  String _formatNotificationTime(int hour, int minute) {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _onNotificationToggled(
    BuildContext context,
    bool enabled,
    SettingsLoadedState state,
  ) async {
    final l10n = S.of(context);
    final locale = Localizations.localeOf(context);
    final notificationService = locator<NotificationService>();
    await notificationService.initialize();
    if (enabled) {
      final granted = await notificationService.requestPermission();
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.notificationsPermissionDeniedSnack)),
          );
        }
        return;
      }
    }
    // Saves the choice and schedules or cancels in one step, in turn with
    // any language-change refresh still running.
    await locator<DailyReminderScheduler>().setEnabled(enabled, locale: locale);
    _settingsBloc.add(LoadSettingsEvent());
  }

  Future<void> _pickNotificationTime(
    BuildContext context,
    TimeOfDay current,
  ) async {
    final locale = Localizations.localeOf(context);
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null) return;
    await locator<DailyReminderScheduler>().setTime(
      picked.hour,
      picked.minute,
      locale: locale,
    );
    _settingsBloc.add(LoadSettingsEvent());
  }
}
