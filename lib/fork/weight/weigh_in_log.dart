import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_display_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// The weigh-ins by their day. A day holds one: a second replaces it.
Future<Map<DateTime, WeightLogEntity>> weighInsByDay() async => {
  for (final e in await locator<GetWeightLogUsecase>().getAllEntries())
    _dayOf(e.date): e,
};

/// "today's 87.0 kg", "Oct 25's 87.0 kg": the weigh-in a new one replaces.
String replacedText(
  BuildContext context,
  WeightLogEntity replaced,
  BodyWeightUnit unit,
  DateTime today,
) =>
    '${_dayName(context, replaced.date, today)}\'s ${_weight(context, replaced.weightKg, unit)}';

String _dayName(BuildContext context, DateTime day, DateTime today) =>
    DateUtils.isSameDay(day, today)
    ? 'today'
    : MaterialLocalizations.of(context).formatShortMonthDay(day);

String _weight(BuildContext context, double kg, BodyWeightUnit unit) =>
    formatBodyWeight(
      kg,
      unit,
      kgLabel: S.of(context).kgLabel,
      lbLabel: S.of(context).lbsLabel,
      stLabel: S.of(context).stLabel,
    );

/// Files [kg] on [day] and says so, with an Undo that brings back the
/// weigh-in it replaced, or takes it off where there was none. [refresh]
/// runs after the save and after an Undo.
Future<void> logWeighIn(
  BuildContext context, {
  required double kg,
  required DateTime day,
  required BodyWeightUnit unit,
  required WeightLogEntity? replaced,
  required Future<void> Function() refresh,
  DateTime? today,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final entry = WeightLogEntity(date: _dayOf(day), weightKg: kg);
  final message =
      '${_weight(context, kg, unit)} logged for '
      '${_dayName(context, day, today ?? DateTime.now())}';
  await locator<AddWeightLogUsecase>().addEntry(entry);
  await refresh();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        // Goes after its time, as the other undos.
        persist: false,
        content: Text(message),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            if (replaced != null) {
              await locator<AddWeightLogUsecase>().addEntry(replaced);
            } else {
              await locator<DeleteWeightLogUsecase>().deleteEntry(entry);
            }
            await refresh();
          },
        ),
      ),
    );
}
