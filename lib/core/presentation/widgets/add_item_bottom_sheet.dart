import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
// [fork] S131 add-sheet
import 'package:opennutritracker/fork/add/add_sheet.dart';
// [/fork]

class AddItemBottomSheet extends StatelessWidget {
  final DateTime day;
  final bool showActivityTracking;
  final bool usesImperialUnits;

  /// Meal type to visually highlight as a suggested default (e.g. based on
  /// the current time). Null keeps every tile unhighlighted — used when the
  /// sheet is launched from a specific meal section, where the caller has
  /// already committed to a meal type.
  final IntakeTypeEntity? suggestedType;

  const AddItemBottomSheet({
    super.key,
    required this.day,
    this.showActivityTracking = true,
    this.usesImperialUnits = false,
    this.suggestedType,
  });

  // [fork] S131 add-sheet: search first, the meal as chips, its recent
  // foods and the tools as tiles
  @override
  Widget build(BuildContext context) => AddSheet(
    day: day,
    showActivityTracking: showActivityTracking,
    usesImperialUnits: usesImperialUnits,
    suggestedType: suggestedType,
  );
  // [/fork]
}
