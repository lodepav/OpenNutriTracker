import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/health_sync_screen.dart'
    show healthPlatformName;
import 'package:opennutritracker/fork/dev/fake_health.dart';
import 'package:opennutritracker/fork/health/body_fat_import.dart';
import 'package:opennutritracker/fork/health/health_disclosure.dart';
import 'package:opennutritracker/fork/health/health_sync_cards.dart';
import 'package:opennutritracker/fork/health/nutrition_export.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';
import 'package:opennutritracker/fork/weight/weigh_in_log.dart'
    show weighInChanges;

/// After an import filed something: the weight chart, BMI and the goals.
void refreshAfterWeightImport() {
  locator<ProfileBloc>().add(LoadProfileEvent());
  locator<DiaryBloc>().updateHomePage();
  weighInChanges.value++;
}

/// "Weight in" on the health sync screen (seam S27), under upstream's
/// workout import, with its own box and permission. Hidden where the
/// import was not started.
class WeightImportTile extends StatelessWidget {
  /// Health store present and the screen not busy.
  final bool available;

  const WeightImportTile({super.key, required this.available});

  @override
  Widget build(BuildContext context) {
    final import = WeightImport.current;
    return import == null
        ? const SizedBox.shrink()
        : HealthImportTile(
            key: const Key('fork-weight-import'),
            identifier: 'health-sync-weight',
            available: available,
            icon: Icons.monitor_weight_outlined,
            title: 'Weight in',
            detail: 'From your smart scale; never over one you enter',
            what: 'weight',
            disclosureTitle: 'Import weight from $healthPlatformName?',
            disclosure:
                'OpenBite will read your body weight from $healthPlatformName: '
                'the last ${WeightImport.backfill.inDays} days now, then new '
                'readings when you come back to the app. Each day\'s latest '
                'reading goes into your weight log, and a weight you entered '
                'yourself is never replaced. The newest becomes the weight '
                'your BMI and calorie goal use.\n\n'
                'This import writes nothing to $healthPlatformName and sends '
                'none of it anywhere: it stays on this device.\n\n'
                'Untick Weight in to stop. Weights already imported stay in '
                'the log.',
            offMessage: 'Weight import off; imported weights stay in the log',
            done: (days) => days == 0
                ? 'Weight import on; no new weigh-ins'
                : 'Imported $days ${days == 1 ? 'day' : 'days'} of weight',
            isOn: import.isOn,
            turnOn: () async {
              final days = await import.turnOn();
              if (days != null && days > 0) refreshAfterWeightImport();
              return days;
            },
            turnOff: import.turnOff,
          );
  }
}

/// "Import body fat" beside it: a smart scale's body fat % into the body
/// measurements.
class BodyFatImportTile extends StatelessWidget {
  final bool available;

  const BodyFatImportTile({super.key, required this.available});

  @override
  Widget build(BuildContext context) {
    final import = BodyFatImport.current;
    return import == null
        ? const SizedBox.shrink()
        : HealthImportTile(
            key: const Key('fork-body-fat-import'),
            identifier: 'health-sync-body-fat',
            available: available,
            icon: Icons.percent_rounded,
            title: 'Body fat in',
            detail: 'Into body measurements; never over one you enter',
            what: 'body fat',
            disclosureTitle: 'Import body fat from $healthPlatformName?',
            disclosure:
                'OpenBite will read your body fat percentage from '
                '$healthPlatformName, such as a smart scale\'s: the last '
                '${BodyFatImport.backfill.inDays} days now, then new readings '
                'when you come back to the app. Each day\'s latest reading '
                'goes into your body measurements, where it feeds your '
                'energy estimate and lean mass; a value you entered yourself '
                'is never replaced.\n\n'
                'This import writes nothing to $healthPlatformName and sends '
                'none of it anywhere: it stays on this device.\n\n'
                'Untick Body fat in to stop. Readings already imported stay.',
            offMessage: 'Body fat import off; imported values stay',
            done: (days) => days == 0
                ? 'Body fat import on; no new readings'
                : 'Imported $days ${days == 1 ? 'day' : 'days'} of body fat',
            isOn: import.isOn,
            turnOn: import.turnOn,
            turnOff: import.turnOff,
          );
  }
}

/// What Nutrition out's disclosure says before its permission is asked.
String nutritionOutDisclosure() =>
    'OpenBite will write each food in your diary from the last '
    '${NutritionExport.window.inDays} days to $healthPlatformName: '
    'the food\'s name, the meal, the time, its calories and '
    'macros, and fibre, sugars, saturated fat and sodium where the '
    'food has them. It keeps them up to '
    'date when you open or leave the app: an edited food is '
    'written again, a deleted one removed.\n\n'
    'Other apps you let read nutrition in $healthPlatformName can '
    'see them. OpenBite sends them nowhere else.\n\n'
    'Untick Nutrition out to stop. Records already written stay in '
    '$healthPlatformName; you can delete them in its settings.';

/// "Write nutrition": the diary's calories and macros to Health Connect.
class NutritionExportTile extends StatelessWidget {
  final bool available;

  const NutritionExportTile({super.key, required this.available});

  @override
  Widget build(BuildContext context) {
    final export = NutritionExport.current;
    return export == null
        ? const SizedBox.shrink()
        : HealthImportTile(
            key: const Key('fork-nutrition-export'),
            identifier: 'health-sync-nutrition',
            available: available,
            icon: Icons.restaurant_rounded,
            title: 'Nutrition out',
            detail: 'Other apps see what you ate',
            what: 'nutrition',
            disclosureTitle: 'Write nutrition to $healthPlatformName?',
            disclosure: nutritionOutDisclosure(),
            verb: 'write',
            offMessage: 'Nutrition writing off; what was written stays',
            done: (n) => n == 0
                ? 'Nutrition writing on; nothing new to write'
                : 'Wrote $n ${n == 1 ? 'food' : 'foods'} to '
                      '$healthPlatformName',
            isOn: export.isOn,
            turnOn: export.turnOn,
            turnOff: export.turnOff,
          );
  }
}

/// A health import's card (S138): asks for the permission when turned on, and
/// says what came of it in a snackbar.
class HealthImportTile extends StatefulWidget {
  final bool available;
  final IconData icon;
  final String identifier;
  final String title;

  /// Where it goes, under the title.
  final String detail;

  /// What is read, in "Could not read [what]".
  final String what;

  /// The disclosure put up before the permission, as Workouts in has.
  final String disclosureTitle;
  final String disclosure;

  /// "read", or "write" for an export.
  final String verb;
  final String offMessage;

  /// The message once on, given what [turnOn] returned.
  final String Function(int count) done;
  final Future<bool> Function() isOn;

  /// The days filed, or null when the permission was refused.
  final Future<int?> Function() turnOn;
  final Future<void> Function() turnOff;

  const HealthImportTile({
    super.key,
    required this.available,
    required this.icon,
    required this.identifier,
    required this.title,
    required this.detail,
    required this.what,
    required this.disclosureTitle,
    required this.disclosure,
    this.verb = 'read',
    required this.offMessage,
    required this.done,
    required this.isOn,
    required this.turnOn,
    required this.turnOff,
  });

  @override
  State<HealthImportTile> createState() => _HealthImportTileState();
}

class _HealthImportTileState extends State<HealthImportTile> {
  bool? _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.isOn().then((on) {
      if (mounted) setState(() => _on = on);
    });
  }

  Future<void> _toggle(bool on) async {
    // Shown on every turn-on, as upstream's Workouts in does; anything but
    // Continue leaves it off and asks for nothing.
    if (on &&
        !await confirmHealthDisclosure(
          context,
          title: widget.disclosureTitle,
          body: widget.disclosure,
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    String message;
    try {
      if (!on) {
        await widget.turnOff();
        message = widget.offMessage;
      } else {
        final count = await widget.turnOn();
        message = count == null
            ? 'Permission to ${widget.verb} ${widget.what} was not given'
            : widget.done(count);
      }
    } catch (_) {
      message = widget.verb == 'read'
          ? 'Could not read ${widget.what} from $healthPlatformName'
          : 'Could not write ${widget.what} to $healthPlatformName';
    }
    final now = await widget.isOn();
    if (!mounted) return;
    setState(() {
      _on = now;
      _busy = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => HealthSyncCard(
    identifier: widget.identifier,
    icon: widget.icon,
    title: widget.title,
    detail: widget.detail,
    value: _on ?? false,
    onChanged: _on == null || _busy || !(widget.available || forkFakeHealth)
        ? null
        : _toggle,
  );
}
