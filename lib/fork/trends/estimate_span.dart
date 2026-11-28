import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';

/// Days from a run's start until the formula's prior has left the
/// estimate: a week's warm-up, then calibration updates taking 0.2 of the
/// gap each, which leave under 1% of the prior (0.8^23) by the last day of
/// [ExpenditureSettings.calibrationDays], logging every day.
// shortcut: assumes the first month was logged; days unlogged then settle
// later, so read the run's update count if a dip still shows.
int estimateSettlingDays(ExpenditureSettings settings) =>
    settings.calibrationDays - 1;

/// The days of [history] Trends draws and reckons from. A run that starts
/// at the user's first weigh-in is what they saw, and is shown whole; one
/// cut at the look-back, with [weighIns] before it, restarts from the
/// formula there, so its settling days are left out, unless nothing would
/// be left.
List<ExpenditureDay> estimateShown(
  List<ExpenditureDay> history, {
  required List<WeightLogEntity> weighIns,
  ExpenditureSettings settings = const ExpenditureSettings(),
}) {
  if (history.isEmpty) return history;
  final first = history.first.date;
  final start = DateTime(first.year, first.month, first.day);
  final cut = weighIns.any((w) => w.date.isBefore(start));
  final settling = estimateSettlingDays(settings);
  if (!cut || history.length <= settling) return history;
  return history.sublist(settling);
}
