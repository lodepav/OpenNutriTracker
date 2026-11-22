import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/send_intake_to_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_display_name.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/profile_avatar.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Bottom sheet that lets the user pick one or more *other* profiles and
/// copy the given intakes into each. Only profiles other than the active
/// one are listed. Shows a confirmation snackbar on the calling screen.
Future<void> showCopyToProfileSheet(
  BuildContext context,
  List<IntakeEntity> intakes,
) async {
  final getProfiles = locator<GetProfilesUsecase>();
  final activeId = getProfiles.activeProfileId;
  final otherProfiles =
      getProfiles.getProfiles().where((p) => p.id != activeId).toList();
  if (otherProfiles.isEmpty) return;

  final messenger = ScaffoldMessenger.of(context);
  final copiedSnackbar = S.of(context).copiedToProfileSnackbar;
  final copied = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) =>
        _CopyToProfileSheet(intakes: intakes, otherProfiles: otherProfiles),
  );

  if (copied == true) {
    messenger.showSnackBar(SnackBar(content: Text(copiedSnackbar)));
  }
}

class _CopyToProfileSheet extends StatefulWidget {
  final List<IntakeEntity> intakes;
  final List<ProfileEntity> otherProfiles;

  const _CopyToProfileSheet({
    required this.intakes,
    required this.otherProfiles,
  });

  @override
  State<_CopyToProfileSheet> createState() => _CopyToProfileSheetState();
}

class _CopyToProfileSheetState extends State<_CopyToProfileSheet> {
  final _selectedIds = <String>{};
  bool _copying = false;
  bool _failed = false; // [fork] S484 copy-to-profile-errors

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            // [fork] S482 section-headings: TalkBack's heading navigation (A7)
            child: Semantics(
              header: true,
              child: Text(
                s.copyToProfileLabel,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            // [/fork]
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final profile in widget.otherProfiles)
                  Semantics(
                    identifier: 'copy-to-profile-item',
                    child: CheckboxListTile(
                      value: _selectedIds.contains(profile.id),
                      onChanged: _copying
                          ? null
                          : (checked) => setState(() {
                                if (checked == true) {
                                  _selectedIds.add(profile.id);
                                } else {
                                  _selectedIds.remove(profile.id);
                                }
                              }),
                      secondary: ProfileAvatar(profile: profile),
                      title: Text(profileDisplayName(context, profile)),
                    ),
                  ),
              ],
            ),
          ),
          // [fork] S484 copy-to-profile-errors: why Copy is off, and a copy
          // that failed (H6, H9)
          if (_failed || (_selectedIds.isEmpty && !_copying))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Semantics(
                liveRegion: _failed,
                child: Text(
                  _failed
                      ? 'Could not copy. Try again.'
                      : 'Pick a profile to copy to',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _failed
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          // [/fork]
          Padding(
            padding: const EdgeInsets.all(16),
            child: Semantics(
              identifier: 'copy-to-profile-confirm',
              child: FilledButton(
                onPressed:
                    _selectedIds.isEmpty || _copying ? null : _onConfirm,
                child: _copying
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(s.copyActionLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onConfirm() async {
    // [fork] S484 copy-to-profile-errors
    // setState(() => _copying = true);
    setState(() {
      _copying = true;
      _failed = false;
    });
    // [/fork]
    final targets = widget.otherProfiles
        .where((p) => _selectedIds.contains(p.id))
        .toList();
    // [fork] S484 copy-to-profile-errors: a failed copy no longer leaves the
    // spinner on for good
    // await locator<SendIntakeToProfilesUsecase>()
    //     .copyToProfiles(widget.intakes, targets);
    try {
      await locator<SendIntakeToProfilesUsecase>()
          .copyToProfiles(widget.intakes, targets);
    } catch (_) {
      if (mounted) {
        setState(() {
          _copying = false;
          _failed = true;
        });
      }
      return;
    }
    // [/fork]
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
}
