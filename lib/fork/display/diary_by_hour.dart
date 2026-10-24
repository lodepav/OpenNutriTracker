import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/timeline/timeline.dart';

/// One section of the Diary by the hour (seam S80): its title, the meal a
/// food added from it goes to, and its foods in the order eaten.
typedef HourSection = ({
  String title,
  AddMealType addMealType,
  List<IntakeEntity> intakes,
});

/// A day's [intakes] by the hour they were eaten, entries with no time
/// first. A section adds to the meal most of its foods were logged under.
List<HourSection> hourSections(List<IntakeEntity> intakes) => [
  for (final (hour, group) in timelineHours(intakes))
    (
      title: hour == null ? 'No time' : DateFormat.Hm().format(hour),
      addMealType: AddMealExtension.fromIntakeTypeEntity(_mostCommon(group)),
      intakes: group,
    ),
];

IntakeTypeEntity _mostCommon(List<IntakeEntity> group) {
  final counts = <IntakeTypeEntity, int>{};
  for (final i in group) {
    counts[i.type] = (counts[i.type] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// The one add row under the hour sections: it asks the time, then adds
/// at it, to the meal the time suggests. The sections have none of their
/// own, so an empty day still has a way in.
class HourAddCard extends StatelessWidget {
  final DateTime day;

  /// Material's time picker in the app; swapped out in tests.
  final Future<TimeOfDay?> Function(BuildContext context) pickTime;

  const HourAddCard({super.key, required this.day, this.pickTime = _picker});

  static Future<TimeOfDay?> _picker(BuildContext context) =>
      showTimePicker(context: context, initialTime: TimeOfDay.now());

  Future<void> _add(BuildContext context) async {
    final time = await pickTime(context);
    if (time == null || !context.mounted) return;
    final config = await locator<GetConfigUsecase>().getConfig();
    final at = momentOn(day, time, config.dayStartOffsetTotalMinutes);
    final meal = MealTypeSuggester.suggestFromTime(
      at,
      mealSharesPct: config.mealKcalSharesPct,
    );
    if (!context.mounted) return;
    await Navigator.of(context).pushNamed(
      NavigationOptions.addMealRoute,
      arguments: AddMealScreenArguments(
        AddMealExtension.fromIntakeTypeEntity(meal),
        at,
      ),
    );
  }

  /// Upstream's add row (PlaceholderCard), with its plus beside words:
  /// a bare plus here would not say a time is asked first.
  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing12,
        Dimens.spacing16,
        Dimens.spacing4,
      ),
      child: Semantics(
        identifier: 'diary-hour-add',
        button: true,
        child: AppCard(
          color: palette.surfaceMuted,
          bordered: false,
          borderRadius: Dimens.radiusM,
          onTap: () => _add(context),
          padding: const EdgeInsets.symmetric(
            horizontal: Dimens.spacing16,
            vertical: Dimens.spacing12,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 26, color: palette.textMuted),
              const SizedBox(width: Dimens.spacing8),
              Flexible(
                child: Text(
                  'Add food at a time…',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: palette.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
