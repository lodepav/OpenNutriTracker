import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';

/// The add screen's camera (seam S90): "Add several items" opened straight
/// at its photo sheet, where a photo was found only behind that screen's
/// list icon. Shown while the AI feature is on; the screen it opens still
/// decides whether a photo can be read.
class PhotoMealButton extends StatefulWidget {
  final VoidCallback onPressed;

  const PhotoMealButton({super.key, required this.onPressed});

  @override
  State<PhotoMealButton> createState() => _PhotoMealButtonState();
}

class _PhotoMealButtonState extends State<PhotoMealButton> {
  // Not registered in the many upstream tests that pump the add screen.
  final _enabled = locator.isRegistered<AiCredentialStorage>()
      ? locator<AiCredentialStorage>().isEnabled()
      : Future.value(false);

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _enabled,
    builder: (context, snapshot) => snapshot.data == true
        ? IconButton(
            key: const ValueKey('add-meal-photo'),
            onPressed: widget.onPressed,
            icon: const Icon(Icons.photo_camera_rounded),
            tooltip: 'Log a meal photo',
          )
        : const SizedBox.shrink(),
  );
}
