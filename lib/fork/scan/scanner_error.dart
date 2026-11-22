import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// What a QR import scanner shows when its camera can't start: why, a way to
/// ask for the camera again, and the paste dialog as the way around it.
class ScannerError extends StatelessWidget {
  final MobileScannerException error;
  final MobileScannerController controller;
  final VoidCallback onPaste;

  const ScannerError({
    super.key,
    required this.error,
    required this.controller,
    required this.onPaste,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final refused = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: colors.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Dimens.spacing24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography_outlined,
                size: 48,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: Dimens.spacing16),
              Text(
                refused ? 'Camera access is off' : "The camera couldn't start",
                style: text.titleMedium?.copyWith(color: colors.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Dimens.spacing8),
              Text(
                // shortcut: no settings opener in the app (no permission
                // package, no channel), so the text names the switch; add a
                // button once a channel opens the app's settings page.
                refused
                    ? 'Allow the camera to scan a code. If no prompt appears, '
                          "turn on Camera in your phone's Settings › Apps › "
                          'OpenBite › Permissions.'
                    : 'You can paste the code instead.',
                style: text.bodyMedium?.copyWith(color: colors.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Dimens.spacing24),
              if (refused) ...[
                FilledButton.icon(
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Allow camera'),
                  // start() asks for the permission again while Android still
                  // shows the prompt.
                  onPressed: controller.start,
                ),
                const SizedBox(height: Dimens.spacing12),
              ],
              PasteCodeButton(onPaste: onPaste),
            ],
          ),
        ),
      ),
    );
  }
}

/// The way around the camera on a QR import scanner: opens the paste dialog.
class PasteCodeButton extends StatelessWidget {
  final VoidCallback onPaste;

  const PasteCodeButton({super.key, required this.onPaste});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.keyboard_rounded),
      label: const Text('Paste a code instead'),
      onPressed: onPaste,
    );
  }
}
