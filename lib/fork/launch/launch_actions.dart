import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/quick_add_bottom_sheet.dart';
import 'package:opennutritracker/features/scanner/scanner_screen.dart';
import 'package:opennutritracker/fork/screens/add_meal/bulk_add_screen.dart';
import 'package:opennutritracker/fork/screens/profile/weight_history_screen.dart';

/// What a launcher shortcut or a share asks of the app (S167).
sealed class LaunchAction {
  const LaunchAction();

  /// From the Android side's map; null for a kind this build doesn't know.
  static LaunchAction? parse(Map<Object?, Object?>? payload) {
    final path = payload?['path'];
    final text = payload?['text'];
    return switch (payload?['kind']) {
      'scan' => const ScanAction(),
      'photo' => const PhotoAction(),
      'quickAdd' => const QuickAddAction(),
      'weighIn' => const WeighInAction(),
      'sharedPhoto' when path is String => SharedPhotoAction(path),
      'sharedText' when text is String && text.trim().isNotEmpty =>
        SharedTextAction(text.trim()),
      _ => null,
    };
  }
}

class ScanAction extends LaunchAction {
  const ScanAction();
}

class PhotoAction extends LaunchAction {
  const PhotoAction();
}

class QuickAddAction extends LaunchAction {
  const QuickAddAction();
}

class WeighInAction extends LaunchAction {
  const WeighInAction();
}

/// An image shared from another app, copied into the cache.
class SharedPhotoAction extends LaunchAction {
  final String path;

  const SharedPhotoAction(this.path);
}

/// Text shared from another app: a meal to read, or a recipe link.
class SharedTextAction extends LaunchAction {
  final String text;

  const SharedTextAction(this.text);
}

/// Seam S167: around the main screen, opens what a shortcut or a share
/// asked for, once on mounting (a cold start) and whenever Android says
/// another arrived. Below the main screen, so only an onboarded profile
/// gets one.
class LaunchActionHost extends StatefulWidget {
  final Widget child;

  const LaunchActionHost({super.key, required this.child});

  @override
  State<LaunchActionHost> createState() => _LaunchActionHostState();
}

class _LaunchActionHostState extends State<LaunchActionHost> {
  static const _channel = MethodChannel('openbite/launch');
  static final _log = Logger('LaunchActions');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'launch') await _consume();
    });
    _consume();
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _consume() async {
    Map<Object?, Object?>? payload;
    try {
      payload = await _channel.invokeMethod<Map<Object?, Object?>>('consume');
    } on MissingPluginException {
      return; // tests, and platforms without the channel
    } catch (e) {
      _log.info('No launch action read: $e');
      return;
    }
    final action = LaunchAction.parse(payload);
    if (action == null || !mounted) return;
    await _open(action);
  }

  Future<void> _open(LaunchAction action) async {
    final now = DateTime.now();
    final type = MealTypeSuggester.suggestFromTime(now);
    final imperial =
        (await locator<GetConfigUsecase>().getConfig()).usesImperialFoodUnits;
    if (!mounted) return;
    final navigator = Navigator.of(context);
    BulkAddScreenArguments bulk({
      bool startWithPhoto = false,
      String? photoPath,
      String? text,
    }) => BulkAddScreenArguments(
      type,
      now,
      imperial,
      startWithPhoto: startWithPhoto,
      sharedPhotoPath: photoPath,
      sharedText: text,
    );
    switch (action) {
      case ScanAction():
        navigator.pushNamed(
          NavigationOptions.scannerRoute,
          arguments: ScannerScreenArguments(now, type),
        );
      case PhotoAction():
        navigator.pushNamed(
          NavigationOptions.bulkAddRoute,
          arguments: bulk(startWithPhoto: true),
        );
      case QuickAddAction():
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => QuickAddBottomSheet(intakeType: type, day: now),
        );
      case WeighInAction():
        navigator.pushNamed(
          NavigationOptions.weightHistoryRoute,
          arguments: const WeighInOnOpen(),
        );
      case SharedPhotoAction(:final path):
        navigator.pushNamed(
          NavigationOptions.bulkAddRoute,
          arguments: bulk(photoPath: path),
        );
      case SharedTextAction(:final text):
        navigator.pushNamed(
          NavigationOptions.bulkAddRoute,
          arguments: bulk(text: text),
        );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
