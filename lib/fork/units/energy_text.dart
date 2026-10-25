import 'package:flutter/widgets.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

/// Energy in the user's unit (#177) for the fork's screens; kcal where no
/// [EnergyUnitProvider] is above, as in widget tests.
/// [listen] false from event handlers.
bool usesKj(BuildContext context, {bool listen = true}) =>
    Provider.of<EnergyUnitProvider?>(context, listen: listen)?.usesKilojoules ??
    false;

String energyUnit(BuildContext context) => usesKj(context) ? 'kJ' : 'kcal';

/// The unit as the language writes it ("ккал", "千卡"), for upstream's
/// translated strings.
String energyUnitLabel(BuildContext context) =>
    usesKj(context) ? S.of(context).kjLabel : S.of(context).kcalLabel;

/// [kcal] in the display unit, truncated as upstream's EnergyDisplay does,
/// so one value reads the same on every screen.
int energyValue(BuildContext context, double kcal) =>
    (usesKj(context) ? UnitCalc.kcalToKj(kcal) : kcal).toInt();

String energyText(BuildContext context, double kcal, {bool signed = false}) {
  final value = energyValue(context, kcal);
  return '${signed && value > 0 ? '+' : ''}$value ${energyUnit(context)}';
}

/// A typed value in the display unit, back to kcal. A typed kJ goes back
/// to its own number under truncation toward zero: 7239 alone returns
/// 7238.99…, so it is moved a hair away from zero; 0 stays 0.
double kcalFromInput(BuildContext context, double value) =>
    usesKj(context, listen: false)
    ? UnitCalc.kjToKcal(value + 1e-6 * value.sign)
    : value;

/// Upstream strings with "kcal" written into them (#150's "{consumed} /
/// {target} kcal" in 16 languages), in kJ when kJ is chosen: the values
/// passed in must be in the display unit already.
String inEnergyUnit(BuildContext context, String text) {
  if (!usesKj(context)) return text;
  final s = S.of(context);
  var out = text;
  for (final kcal in {s.kcalLabel, 'kcal', '千卡'}) {
    out = out.replaceAll(kcal, s.kjLabel);
  }
  return out;
}
