import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/fork/update/updater.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whether to offer [info] now: a newer version with an APK, and not the
/// version last offered ([seen]).
bool shouldOffer(UpdateInfo? info, String? seen) =>
    info != null &&
    info.hasUpdate &&
    info.apkUrl != null &&
    info.latestVersion.isNotEmpty &&
    info.latestVersion != seen;

/// A new OpenBite offers itself when the app is opened (D16), after
/// openGym-Hevier's UpdateNotice (its D77): a sheet with Install and Not now,
/// 4 s after launch and 1 s after every return to the app. Asked is
/// answered: the version offered is kept on the device, so Not now, or a tap
/// outside, waits for the next one; Settings → About → Updates still has it.
class UpdateNotice extends StatefulWidget {
  static const boxName = 'ForkUpdateBox';
  static const seenKey = 'seen';

  final Widget child;
  final Updater? updater;

  /// The version last offered, and keeping it: in [boxName] by default.
  final Future<String?> Function() readSeen;
  final Future<void> Function(String version) writeSeen;

  const UpdateNotice({
    super.key,
    required this.child,
    this.updater,
    this.readSeen = _readSeen,
    this.writeSeen = _writeSeen,
  });

  static Future<String?> _readSeen() async =>
      (await Hive.openBox<dynamic>(boxName)).get(seenKey) as String?;

  static Future<void> _writeSeen(String version) async =>
      (await Hive.openBox<dynamic>(boxName)).put(seenKey, version);

  @override
  State<UpdateNotice> createState() => _UpdateNoticeState();
}

class _UpdateNoticeState extends State<UpdateNotice>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _open = false;

  Updater get _updater => widget.updater ?? Updater.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _later(const Duration(seconds: 4));
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _later(const Duration(seconds: 1));
  }

  void _later(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _check);
  }

  Future<void> _check() async {
    if (_open) return;
    final UpdateInfo info;
    try {
      info = await _updater.check();
    } catch (_) {
      return; // offline: the next return to the app asks again
    }
    if (!info.hasUpdate) return;
    final seen = await widget.readSeen();
    if (!mounted || _open || !shouldOffer(info, seen)) return;
    await widget.writeSeen(info.latestVersion);
    if (!mounted) return;
    _open = true;
    try {
      await offerUpdate(context, info, _updater);
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The offer's sheet: Install, or Not now.
Future<void> offerUpdate(
  BuildContext context,
  UpdateInfo info,
  Updater updater,
) async {
  final install = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('OpenBite ${info.latestVersion} is available'),
            subtitle: const Text(
              'It downloads here and Android’s installer opens. Your data '
              'stays as it is.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Install'),
            onTap: () => Navigator.pop(context, true),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Not now'),
            subtitle: const Text('Settings → About → Updates still has it.'),
            onTap: () => Navigator.pop(context, false),
          ),
        ],
      ),
    ),
  );
  if (install == true && context.mounted) {
    await installUpdate(context, info, updater);
  }
}

/// Downloads and installs [info], with the download's progress in a dialog
/// that cannot be dismissed; a failure is a snackbar.
Future<void> installUpdate(
  BuildContext context,
  UpdateInfo info,
  Updater updater,
) async {
  final progress = ValueNotifier<String>('Starting download…');
  final fraction = ValueNotifier<double?>(null);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Downloading update…'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder(
                valueListenable: fraction,
                builder: (_, value, _) => LinearProgressIndicator(value: value),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder(
                valueListenable: progress,
                builder: (_, text, _) => Text(text),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    await updater.install(
      info,
      onProgress: (received, total) {
        if (total != null && total > 0) {
          final value = (received / total).clamp(0.0, 1.0);
          fraction.value = value;
          progress.value = '${(value * 100).round()} %';
        } else {
          progress.value = '${(received / 1000000).toStringAsFixed(1)} MB';
        }
      },
    );
    navigator.pop();
  } catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Update failed: $e')));
  }
}

/// About's row: "Update to OpenBite X" when there is one, nothing otherwise
/// (and nothing in a build that never checks). A release without an APK
/// opens the releases page.
class AboutUpdateRow extends StatelessWidget {
  final Updater? updater;

  const AboutUpdateRow({super.key, this.updater});

  @override
  Widget build(BuildContext context) {
    final updater = this.updater ?? Updater.instance;
    return FutureBuilder<UpdateInfo>(
      future: updater.check(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null || !info.hasUpdate) return const SizedBox.shrink();
        return TextButton(
          onPressed: () => info.apkUrl != null
              ? installUpdate(context, info, updater)
              : launchUrl(
                  Uri.parse(releasesPage),
                  mode: LaunchMode.externalApplication,
                ),
          child: Row(
            children: [
              const Icon(Icons.system_update_outlined),
              const SizedBox(width: 8.0),
              Flexible(child: Text('Update to OpenBite ${info.latestVersion}')),
            ],
          ),
        );
      },
    );
  }
}

/// Settings' Updates row (S76): the version running and what GitHub says,
/// through [builder] so the row looks like the screen's others. A tap
/// installs the update there is, or asks again.
class UpdateStatus extends StatefulWidget {
  /// The version running, as Settings already has it.
  final String version;
  final Updater? updater;
  final Widget Function(String subtitle, VoidCallback onTap) builder;

  const UpdateStatus({
    super.key,
    required this.version,
    required this.builder,
    this.updater,
  });

  @override
  State<UpdateStatus> createState() => _UpdateStatusState();
}

class _UpdateStatusState extends State<UpdateStatus> {
  Updater get _updater => widget.updater ?? Updater.instance;
  late Future<UpdateInfo> _info = _updater.check();

  void _again() => setState(() {
    _info = _updater.recheck();
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<UpdateInfo>(
    future: _info,
    builder: (context, snapshot) {
      final running = 'Version ${widget.version}';
      final info = snapshot.data;
      if (snapshot.hasError) {
        return widget.builder(
          '$running. Could not check for updates; tap to try again.',
          _again,
        );
      }
      if (info == null) {
        return widget.builder('$running. Checking for updates…', () {});
      }
      if (!info.checked) {
        return widget.builder(
          '$running, a development build: it gets no updates. Tap for '
          'the released app, which installs beside it.',
          () => launchUrl(
            Uri.parse(releasesPage),
            mode: LaunchMode.externalApplication,
          ),
        );
      }
      if (info.hasUpdate) {
        return widget.builder(
          '$running. OpenBite ${info.latestVersion} is available; tap to '
          'install.',
          () => info.apkUrl != null
              ? installUpdate(context, info, _updater)
              : launchUrl(
                  Uri.parse(releasesPage),
                  mode: LaunchMode.externalApplication,
                ),
        );
      }
      return widget.builder(
        '$running, the latest. Tap to check again.',
        _again,
      );
    },
  );
}
