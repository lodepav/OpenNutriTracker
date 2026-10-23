import 'dart:async';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/utils/app_locale_service.dart';
import 'package:opennutritracker/core/utils/app_locale_sync.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locale_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/theme_mode_provider.dart';
import 'package:provider/provider.dart';

/// Shows what a restore wrote to the settings now, rather than at the next
/// start: the theme, Material You and accent colour, kilojoules, and the
/// language, which goes through the in-app picker's path so Android's
/// per-app language follows it. Only what differs is touched, so calling it
/// when nothing changed (after an export) does nothing.
Future<void> applyRestoredSettings(BuildContext context) async {
  if (!locator.isRegistered<ConfigRepository>()) return;
  final configRepo = locator<ConfigRepository>();
  final theme = Provider.of<ThemeModeProvider>(context, listen: false);
  final energy = Provider.of<EnergyUnitProvider>(context, listen: false);
  final localeProvider = Provider.of<LocaleProvider>(context, listen: false);

  final config = await configRepo.getConfig();
  final localeCode = await configRepo.getSelectedLocale();

  if (theme.appTheme != config.appTheme) theme.updateTheme(config.appTheme);
  theme.updateUseMaterialYou(config.useMaterialYou);
  theme.updateAccentColor(config.accentColor);
  energy.updateUsesKilojoules(config.usesKilojoules);

  if (localeProvider.locale?.toString() == localeCode) return;
  await applyInAppLocaleChoice(
    lock: localeSyncLock,
    localeCode: localeCode,
    persistSelectedLocale: configRepo.setSelectedLocale,
    applyToApp: () => localeProvider.updateLocale(
      localeCode != null ? Locale(localeCode) : null,
    ),
    pushToSystem: AppLocaleService.setApplicationLocale,
    readSystemTag: AppLocaleService.getApplicationLocale,
    markLocaleSyncSeeded: configRepo.setLocaleSyncSeeded,
    clearLocaleSyncSeeded: configRepo.clearLocaleSyncSeeded,
  );
}
