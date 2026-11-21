import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/bounds/ranges_const.dart';
import 'package:opennutritracker/core/utils/bounds/validator.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/fork/onboarding/birthday_input.dart';

/// What a typed birthday gets told: null while incomplete or when accepted,
/// else whether the date is not real or outside the accepted years.
String? birthdayError(String text, BirthdayFormat format, {DateTime? now}) {
  if (text.replaceAll(RegExp(r'[^0-9]'), '').length != 8) return null;
  final date = format.parse(text);
  if (date == null) return "That date doesn't exist";
  final first = ValueValidator.getFirstDate(now: now);
  final last = ValueValidator.getLastDate(now: now);
  if (!date.isBefore(first) && !date.isAfter(last)) return null;
  // Whole years only: an edge year only partly accepted is left out.
  final firstYear = first.month == 1 && first.day == 1
      ? first.year
      : first.year + 1;
  final lastYear = last.month == 12 && last.day == 31
      ? last.year
      : last.year - 1;
  return 'Enter a birthday between $firstYear and $lastYear';
}

/// The accepted height in the unit shown, rounded inward so both ends pass.
String heightRangeText({required bool imperial}) => imperial
    ? 'Height between ${Ranges.minHeightInFeet.ceil()} and '
          '${Ranges.maxHeightInFeet.floor()} ft'
    : 'Height between ${Ranges.minHeight.ceil()} and '
          '${Ranges.maxHeight.floor()} cm';

/// The accepted weight in [unit], named [unitLabel], rounded inward.
String weightRangeText(BodyWeightUnit unit, String unitLabel) {
  final (min, max) = switch (unit) {
    BodyWeightUnit.kg => (Ranges.minWeight, Ranges.maxWeight),
    BodyWeightUnit.lb => (Ranges.minWeightInLbs, Ranges.maxWeightInLbs),
    BodyWeightUnit.st => (
      UnitCalc.kgToLbs(Ranges.minWeight) / 14,
      UnitCalc.kgToLbs(Ranges.maxWeight) / 14,
    ),
  };
  return 'Weight between ${min.ceil()} and ${max.floor()} $unitLabel';
}

/// The blocked Next's message when exactly one field is wrong, naming it;
/// null otherwise, where the general message fits.
String? bodyBlockedMessage({
  required bool heightOk,
  required bool weightOk,
  required bool targetOk,
}) {
  final wrong = [
    if (!heightOk) 'Enter a valid height to continue',
    if (!weightOk) 'Enter a valid weight to continue',
    if (!targetOk) 'Enter a valid target weight, or leave it blank',
  ];
  return wrong.length == 1 ? wrong.single : null;
}

/// About you's blocked Next message when exactly one field is wrong, naming
/// it, with the birthday's [birthdayError] when it has one; null otherwise,
/// where upstream's message names both.
String? aboutYouBlockedMessage({
  required bool genderOk,
  required bool birthdayOk,
  String? birthdayError,
}) {
  if (genderOk == birthdayOk) return null;
  return genderOk
      ? birthdayError ?? 'Enter your birthday to continue'
      : 'Select your gender to continue';
}
