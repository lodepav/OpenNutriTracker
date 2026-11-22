import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';

/// The drink logged last among [entries], for Undo last: the highest
/// `water-<microseconds>` id the Log water dialog stamps; with none stamped
/// (sample or imported drinks only), the latest by time. A drink can be timed
/// after the one just logged, so time alone undid the wrong one.
WaterIntakeEntity? lastLoggedWater(List<WaterIntakeEntity> entries) {
  if (entries.isEmpty) return null;
  int? stamp(WaterIntakeEntity e) =>
      e.id.startsWith('water-') ? int.tryParse(e.id.substring(6)) : null;
  final stamped = entries.where((e) => stamp(e) != null).toList();
  if (stamped.isNotEmpty) {
    return stamped.reduce((a, b) => stamp(b)! > stamp(a)! ? b : a);
  }
  return entries.reduce((a, b) => b.dateTime.isAfter(a.dateTime) ? b : a);
}
