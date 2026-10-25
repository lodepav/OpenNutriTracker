import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/delete_profile_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/screens/profile_editor_screen.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_switch_coordinator.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/profile_switcher_sheet.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S139 profiles
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/fork/profile/profiles_view.dart';
// [/fork]

class ManageProfilesScreen extends StatefulWidget {
  const ManageProfilesScreen({super.key});

  @override
  State<ManageProfilesScreen> createState() => _ManageProfilesScreenState();
}

class _ManageProfilesScreenState extends State<ManageProfilesScreen> {
  late List<ProfileEntity> _profiles;
  late String _activeId;
  // [fork] S139 profiles: each profile's figures, read after the list
  Map<String, ProfileStats> _forkStats = const {};
  BodyWeightUnit _forkWeightUnit = BodyWeightUnit.kg;
  // [/fork]

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final getProfiles = locator<GetProfilesUsecase>();
    _profiles = getProfiles.getProfiles();
    _activeId = getProfiles.activeProfileId;
    // [fork] S139 profiles
    _forkReadStats();
    // [/fork]
  }

  // [fork] S139 profiles
  Future<void> _forkReadStats() async {
    final db = locator<HiveDBProvider>();
    final stats = <String, ProfileStats>{};
    for (final p in _profiles) {
      try {
        stats[p.id] = await readProfileStats(
          db,
          p,
          active: p.id == _activeId,
        );
      } catch (_) {
        // A profile whose boxes can not be read shows dashes.
      }
    }
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!mounted) return;
    setState(() {
      _forkStats = stats;
      _forkWeightUnit = config.bodyWeightUnit;
    });
  }
  // [/fork]

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.manageProfilesLabel)),
      // [fork] S139 profiles: a card for each, Add profile under them
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Semantics(
            identifier: 'manage-profiles-add',
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () async {
                await showAddProfileDialog(context);
                if (mounted) setState(_reload);
              },
              icon: const Icon(Icons.add),
              label: Text(s.addProfileLabel),
            ),
          ),
        ),
      ),
      body: ProfilesView(
        profiles: _profiles,
        activeId: _activeId,
        stats: _forkStats,
        weightUnit: _forkWeightUnit,
        onEdit: _onEdit,
        onSwitch: (profile) =>
            locator<ProfileSwitchCoordinator>().switchTo(context, profile),
        onDelete: _onDelete,
      ),
      // [/fork]
    );
  }

  Future<void> _onEdit(ProfileEntity profile) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileEditorScreen(profile: profile),
      ),
    );
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _onDelete(ProfileEntity profile) async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.deleteProfileConfirmTitle),
        content: Text(s.deleteProfileConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.dialogCancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.dialogDeleteLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Deleting the active profile switches to another first, which routes
    // away from this screen — so let the coordinator take over and stop.
    final wasActive = profile.id == _activeId;
    await locator<DeleteProfileUsecase>().deleteProfile(profile);
    if (!mounted) return;
    if (wasActive) {
      final fallback = locator<GetProfilesUsecase>().getActiveProfile();
      if (fallback != null) {
        await locator<ProfileSwitchCoordinator>().switchTo(context, fallback);
        return;
      }
    }
    setState(_reload);
  }
}
