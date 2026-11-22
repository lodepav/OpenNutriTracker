import 'dart:io';

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
import 'package:opennutritracker/fork/display/sized_file_image.dart' show evictPhoto;
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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _imagePath = widget.profile.imagePath;
    _imageCredit = _creditFor(_imagePath);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<({String name, String profileUrl})?>? _creditFor(String? path) =>
      path == null ? null : UserImageStorage.readCredit(path);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
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
              imagePath: _imagePath,
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
    );
  }

  Future<void> _onPickImage({required ImageSource source}) async {
    // [fork] S251 avatar-pick: a camera photo is not taken in at full size
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1440,
      maxHeight: 1440,
    );
    // [/fork]
    if (picked == null) return;
    final relative = await UserImageStorage.importFrom(
      kind: UserImageKind.profile,
      ownerId: widget.profile.id,
      sourcePath: picked.path,
    );
    FileImage(File(await UserImageStorage.absolutePath(relative))).evict();
    // [fork] S251 avatar-pick: the avatars hold the photo at their own sizes
    // (S250), which the line above leaves cached; the new photo at that path
    // would not show.
    await evictPhoto(relative);
    // [/fork]
    setState(() {
      _imagePath = relative;
      // importFrom deletes any stale credit sidecar, so re-read once.
      _imageCredit = _creditFor(relative);
    });
  }

  Future<void> _onRemoveImage() async {
    final current = _imagePath;
    if (current == null) return;
    await UserImageStorage.delete(current);
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
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
}
