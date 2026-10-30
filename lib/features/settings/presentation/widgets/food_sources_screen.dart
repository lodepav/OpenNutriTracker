import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S137 food-databases
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/settings/food_databases_view.dart';
// [/fork]
import 'package:opennutritracker/core/utils/safe_url_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings → Food databases: lets the user pick which food databases the
/// search screens draw from. State is persisted on
/// [ConfigEntity.foodSourceToggles]; a source not present in the map
/// defaults to enabled, so users who never visit this screen search every
/// database. Open Food Facts powers the product and barcode search and is
/// shown as a fixed, always-on entry.
class FoodSourcesScreen extends StatefulWidget {
  const FoodSourcesScreen({super.key});

  @override
  State<FoodSourcesScreen> createState() => _FoodSourcesScreenState();
}

class _FoodSourcesScreenState extends State<FoodSourcesScreen> {
  Map<String, bool> _toggles = <String, bool>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadToggles();
  }

  Future<void> _loadToggles() async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!mounted) return;
    setState(() {
      _toggles = Map<String, bool>.from(config.foodSourceToggles);
      _loading = false;
    });
  }

  Future<void> _toggle(String sourceCode, bool enabled) async {
    setState(() => _toggles[sourceCode] = enabled);
    await locator<AddConfigUsecase>().setConfigFoodSourceToggles(_toggles);
  }

  /// Opens the database's public website in the in-app browser (Custom
  /// Tabs / SFSafariViewController) so the user stays inside the app.
  Future<void> _openSourceInfo(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorText = S.of(context).errorOpeningBrowser;
    if (await tryLaunchExternalUrl(url, mode: LaunchMode.inAppBrowserView)) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(errorText)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.settingsFoodSourcesLabel)),
      // [fork] S137 food-databases: MacroFactor's list, a tag for each
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppPalette.dark.canvas
          : AppPalette.light.canvas,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : FoodDatabasesView(
              toggles: _toggles,
              onToggle: _toggle,
              onOpenSite: _openSourceInfo,
            ),
      // [/fork]
    );
  }
}
