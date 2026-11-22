import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:permission_handler/permission_handler.dart';

/// The camera permission calls [ScannerError] makes, swapped in tests so
/// they don't reach the plugin.
class CameraPermission {
  const CameraPermission();

  Future<PermissionStatus> request() => Permission.camera.request();

  Future<PermissionStatus> status() => Permission.camera.status;

  /// True after one refusal, while Android still shows the prompt.
  Future<bool> canPrompt() => Permission.camera.shouldShowRequestRationale;

  Future<bool> openSettings() => openAppSettings();
}

/// What a QR import scanner shows when its camera can't start: why, a way to
/// ask for the camera again, and the paste dialog as the way around it.
class ScannerError extends StatefulWidget {
  /// What Allow camera asks through; tests set a fake.
  @visibleForTesting
  static CameraPermission permission = const CameraPermission();

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
  State<ScannerError> createState() => _ScannerErrorState();
}

class _ScannerErrorState extends State<ScannerError>
    with WidgetsBindingObserver {
  /// Set while the app's settings page is open, so coming back re-checks.
  bool _inSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _inSettings) _recheck();
  }

  Future<void> _recheck() async {
    _inSettings = false;
    final status = await ScannerError.permission.status();
    if (status.isGranted && mounted) await widget.controller.start();
  }

  Future<void> _allow() async {
    final permission = ScannerError.permission;
    final couldPrompt = await permission.canPrompt();
    final status = await permission.request();
    if (status.isGranted) {
      if (mounted) await widget.controller.start();
      return;
    }
    // Refused twice, Android answers without a prompt and the switch is in
    // the app's settings. A refusal in a prompt just shown stays here.
    // Not the plugin's permanentlyDenied: the refusals went through
    // mobile_scanner, so the plugin never saw them and reads "denied".
    if (!couldPrompt && !await permission.canPrompt()) {
      _inSettings = true;
      await permission.openSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final refused = widget.error.errorCode == MobileScannerErrorCode.permissionDenied;
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
                refused
                    ? 'Allow the camera to scan a code. If no prompt appears, '
                          "Allow camera opens the app's settings: turn on "
                          'Camera there and come back.'
                    : 'You can paste the code instead.',
                style: text.bodyMedium?.copyWith(color: colors.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Dimens.spacing24),
              if (refused) ...[
                FilledButton.icon(
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Allow camera'),
                  onPressed: _allow,
                ),
                const SizedBox(height: Dimens.spacing12),
              ],
              PasteCodeButton(onPaste: widget.onPaste),
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
