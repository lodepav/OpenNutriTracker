import 'package:flutter/widgets.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:provider/provider.dart';

/// Energy in the user's unit (#177) for the fork's screens; kcal where no
/// [EnergyUnitProvider] is above, as in widget tests.
/// [listen] false from event handlers.
bool usesKj(BuildContext context, {bool listen = true}) =>
    Provider.of<EnergyUnitProvider?>(context, listen: listen)?.usesKilojoules ??
    false;

String energyUnit(BuildContext context) => usesKj(context) ? 'kJ' : 'kcal';

/// [kcal] in the display unit, rounded.
int energyValue(BuildContext context, double kcal) =>
    (usesKj(context) ? UnitCalc.kcalToKj(kcal) : kcal).round();

String energyText(BuildContext context, double kcal, {bool signed = false}) {
  final value = energyValue(context, kcal);
  return '${signed && value > 0 ? '+' : ''}$value ${energyUnit(context)}';
}

/// A typed value in the display unit, back to kcal.
double kcalFromInput(BuildContext context, double value) =>
    usesKj(context, listen: false) ? UnitCalc.kjToKcal(value) : value;
