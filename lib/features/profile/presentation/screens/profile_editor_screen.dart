// [fork] S478 photo-staging: no File left here
// import 'dart:io';
// [/fork]

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/update_profile_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:opennutritracker/core/presentation/widgets/user_image_picker_tile.dart';
import 'package:opennutritracker/core/utils/demo/unsplash_attribution.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S251 avatar-pick
// S478 photo-staging: StagedPhoto evicts the avatars' copies
// import 'package:opennutritracker/fork/display/sized_file_image.dart' show evictPhoto;
// [/fork]
// [fork] S478 photo-staging
import 'package:opennutritracker/fork/photos/staged_photo.dart';
// [/fork]
// [fork] S479 profile-editor-guard
import 'package:opennutritracker/fork/recipe/recipe_delete.dart'
    show destructiveFilledStyle;
// [/fork]

/// Edits a single profile's name and picture. The picture is imported the
/// moment it's picked (the profile already has an id to key the file by),
/// mirroring the recipe builder's image flow.
class ProfileEditorScreen extends StatefulWidget {
  final ProfileEntity profile;

  const ProfileEditorScreen({super.key, required this.profile});

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  late final TextEditingController _nameController;
  late String? _imagePath;
  Future<({String name, String profileUrl})?>? _imageCredit;
  String? _nameError; // [fork] S439 profile-editor-name-required
  // [fork] S478 photo-staging: a picked or removed photo waits for Save (H3)
  final _forkPhoto = StagedPhoto(UserImageKind.profile);
  // [/fork]

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    // [fork] S479 profile-editor-guard: Back asks once the name changed
    _nameController.addListener(() => setState(() {}));
    // [/fork]
    _imagePath = widget.profile.imagePath;
    _imageCredit = _creditFor(_imagePath);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _forkPhoto.discard(); // [fork] S478 photo-staging
    super.dispose();
  }

  // [fork] S479 profile-editor-guard: Back asks before dropping a change, as
  // the recipe builder does (H3)
  bool get _forkDirty =>
      _nameController.text != widget.profile.name ||
      _imagePath != widget.profile.imagePath ||
      _forkPhoto.pending;

  Future<void> _forkOnBack() async {
    final s = S.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.discardChangesTitle),
        content: Text(s.discardChangesContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.dialogCancelLabel),
          ),
          FilledButton(
            style: destructiveFilledStyle(ctx),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.discardChangesConfirmLabel),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }
  // [/fork]

  Future<({String name, String profileUrl})?>? _creditFor(String? path) =>
      path == null ? null : UserImageStorage.readCredit(path);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // [fork] S479 profile-editor-guard
    // return Scaffold(
    return PopScope(
      canPop: !_forkDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _forkOnBack();
      },
      child: Scaffold(
    // [/fork]
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(kToolbarHeight),
        title: Text(
          s.editProfileTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Semantics(
            identifier: 'profile-editor-save',
            child: TextButton(
              onPressed: _onSave,
              child: Text(s.buttonSaveLabel),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: UserImagePickerTile(
              kind: UserImageKind.profile,
              // [fork] S478 photo-staging
              // imagePath: _imagePath,
              imagePath: _forkPhoto.shown(_imagePath),
              // [/fork]
              onPickFromGallery: () =>
                  _onPickImage(source: ImageSource.gallery),
              onTakePhoto: () => _onPickImage(source: ImageSource.camera),
              onRemove: _onRemoveImage,
            ),
          ),
          if (_imageCredit != null)
            UnsplashCreditFromSidecar(credit: _imageCredit!),
          const SizedBox(height: 16),
          Semantics(
            identifier: 'profile-editor-name',
            child: TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              // [fork] S439 profile-editor-name-required
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              // [/fork]
              decoration: InputDecoration(
                labelText: s.profileNameLabel,
                hintText: s.profileNameHint,
                border: const OutlineInputBorder(),
                errorText: _nameError, // [fork] S439 profile-editor-name-required
              ),
            ),
          ),
        ],
      ),
    ), // [fork] S479 profile-editor-guard: PopScope
    );
  }

  Future<void> _onPickImage({required ImageSource source}) async {
    // [fork] S479 profile-editor-guard: a failed pick says so (H9)
    try {
    // [/fork]
    // [fork] S251 avatar-pick: a camera photo is not taken in at full size
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1440,
      maxHeight: 1440,
    );
    // [/fork]
    if (picked == null) return;
    // [fork] S478 photo-staging: staged; Save writes it to the stored path
    // final relative = await UserImageStorage.importFrom(
    //   kind: UserImageKind.profile,
    //   ownerId: widget.profile.id,
    //   sourcePath: picked.path,
    // );
    // FileImage(File(await UserImageStorage.absolutePath(relative))).evict();
    // [/fork]
    // [fork] S251 avatar-pick: the avatars hold the photo at their own sizes
    // (S250), which the line above leaves cached; the new photo at that path
    // would not show.
    // await evictPhoto(relative);
    // [/fork]
    // [fork] S478 photo-staging
    final relative = await _forkPhoto.pick(
      ownerId: widget.profile.id,
      sourcePath: picked.path,
    );
    if (!mounted) return;
    // [/fork]
    setState(() {
      _imagePath = relative;
      // importFrom deletes any stale credit sidecar, so re-read once.
      // [fork] S478 photo-staging: Save deletes it with the old photo
      // _imageCredit = _creditFor(relative);
      _imageCredit = null;
      // [/fork]
    });
    // [fork] S479 profile-editor-guard
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add the photo')),
      );
    }
    // [/fork]
  }

  Future<void> _onRemoveImage() async {
    final current = _imagePath;
    if (current == null) return;
    // [fork] S478 photo-staging: deleted on Save
    // await UserImageStorage.delete(current);
    await _forkPhoto.remove(current);
    if (!mounted) return;
    // [/fork]
    setState(() {
      _imagePath = null;
      _imageCredit = null;
    });
  }

  Future<void> _onSave() async {
    // [fork] S439 profile-editor-name-required: a blank name, as Add
    // profile refuses (S302), would show as "Profile 1" (H5)
    if (_nameController.text.trim().isEmpty) {
      setState(() => _nameError = 'Enter a name');
      return;
    }
    // [/fork]
    final toSave = ProfileEntity(
      id: widget.profile.id,
      name: _nameController.text.trim(),
      createdAt: widget.profile.createdAt,
      boxSuffix: widget.profile.boxSuffix,
      imagePath: _imagePath,
    );
    await locator<UpdateProfileUsecase>().updateProfile(toSave);
    // [fork] S478 photo-staging: the photo once the profile is saved
    final photoSaved = await _forkPhoto.commit();
    if (!mounted) return;
    if (!photoSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the photo')),
      );
    }
    // [/fork]
    Navigator.of(context).pop(true);
  }
}
