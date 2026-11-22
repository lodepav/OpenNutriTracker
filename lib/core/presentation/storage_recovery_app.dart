import 'package:flutter/material.dart';
// [fork] S112 storage-rescue
import 'package:opennutritracker/fork/backup/storage_rescue.dart';
// [/fork]
// [fork] S544 recovery-theme-help
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/app_const.dart';
// [/fork]

class StorageRecoveryApp extends StatelessWidget {
  const StorageRecoveryApp({
    required this.errorCode,
    required this.onRetry,
    super.key,
  });

  final String errorCode;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // [fork] S544 recovery-theme-help: the app's palette, light and dark,
      // in place of Flutter's default; it needs nothing startup sets up
      theme: buildAppTheme(AppPalette.light),
      darkTheme: buildAppTheme(AppPalette.dark),
      // [/fork]
      home: _StorageRecoveryScreen(errorCode: errorCode, onRetry: onRetry),
    );
  }
}

class _StorageRecoveryScreen extends StatefulWidget {
  const _StorageRecoveryScreen({
    required this.errorCode,
    required this.onRetry,
  });

  final String errorCode;
  final Future<void> Function() onRetry;

  @override
  State<_StorageRecoveryScreen> createState() => _StorageRecoveryScreenState();
}

class _StorageRecoveryScreenState extends State<_StorageRecoveryScreen> {
  bool _retrying = false;
  // [fork] S500 recovery-busy: a rescue step is moving files, so Retry is
  // off as the panel's buttons are while Retry runs
  bool _forkRescueBusy = false;
  // [/fork]

  Future<void> _retry() async {
    // [fork] S500 recovery-busy
    // if (_retrying) return;
    if (_retrying || _forkRescueBusy) return;
    // [/fork]
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // [fork] S112: a lost or broken key is not mended by moving files
    final rescue = StorageRescue.helps(widget.errorCode);
    // [/fork]
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.storage_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Your local data could not be opened safely',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  // [fork] S112 storage-rescue: was "Try again. If the
                  // problem persists, contact support before clearing the
                  // app data or reinstalling", beside the panel's two ways
                  // out
                  Text(
                    rescue
                        ? 'Your data files have not been changed. Retry once. '
                              'If it fails again, use a button below: it moves '
                              'the files that will not open aside on the phone '
                              'instead of deleting them. Do not clear the app '
                              'data or reinstall.'
                        // [fork] S544 recovery-theme-help: an open-source app
                        // has no support desk; say where to report it
                        // : 'Your data files have not been changed. Try again. '
                        //       'If the problem persists, contact support before '
                        //       'clearing the app data or reinstalling.',
                        : 'Your data files have not been changed. Try again. '
                              'If the problem persists, report the error code '
                              'at ${AppConst.sourceCodeUrl.replaceFirst('https://', '')}/issues '
                              'before clearing the app data or reinstalling.',
                        // [/fork]
                    textAlign: TextAlign.center,
                  ),
                  // [/fork]
                  const SizedBox(height: 12),
                  Text(
                    'Error code: ${widget.errorCode}',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    identifier: 'storage-recovery-retry',
                    child: FilledButton.icon(
                      // [fork] S500 recovery-busy
                      // onPressed: _retrying ? null : _retry,
                      onPressed: _retrying || _forkRescueBusy ? null : _retry,
                      // [/fork]
                      icon: _retrying
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ),
                  // [fork] S112 S500 storage-rescue: restore the automatic
                  // backup, or start again; off while Retry runs, and
                  // Retry off while it does
                  if (rescue)
                    StorageRescuePanel(
                      onRetry: widget.onRetry,
                      busy: _retrying,
                      onBusy: (busy) {
                        if (mounted) setState(() => _forkRescueBusy = busy);
                      },
                    ),
                  // [/fork]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
