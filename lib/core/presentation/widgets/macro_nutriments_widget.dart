import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S79 macro-order
import 'package:opennutritracker/fork/display/display_prefs.dart';
// [/fork]

class MacroNutrientsView extends StatefulWidget {
  final double totalCarbsIntake;
  final double totalFatsIntake;
  final double totalProteinsIntake;
  final double totalCarbsGoal;
  final double totalFatsGoal;
  final double totalProteinsGoal;

  const MacroNutrientsView({
    super.key,
    required this.totalCarbsIntake,
    required this.totalFatsIntake,
    required this.totalProteinsIntake,
    required this.totalCarbsGoal,
    required this.totalFatsGoal,
    required this.totalProteinsGoal,
  });

  @override
  State<MacroNutrientsView> createState() => _MacroNutrientsViewState();
}

class _MacroNutrientsViewState extends State<MacroNutrientsView> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    // [fork] S79 macro-order: the rings in the user's macro order
    // [fork] S83 large-text: at large font sizes the rings stack, so the
    // values are not cut off
    final stack = MediaQuery.textScalerOf(context).scale(10) > 13;
    Widget fit(Widget ring) => stack ? ring : Expanded(child: ring);
    return MacroOrderBuilder(
      builder: (context) => Flex(
        direction: stack ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment:
            stack ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: inMacroOrder(
          carbs: fit(
            _MacroRing(
              intake: widget.totalCarbsIntake,
              goal: widget.totalCarbsGoal,
              label: S.of(context).carbsLabel,
              color: palette.carbs,
              palette: palette,
            ),
          ),
          fat: fit(
            _MacroRing(
              intake: widget.totalFatsIntake,
              goal: widget.totalFatsGoal,
              label: S.of(context).fatLabel,
              color: palette.fat,
              palette: palette,
            ),
          ),
          protein: fit(
            _MacroRing(
              intake: widget.totalProteinsIntake,
              goal: widget.totalProteinsGoal,
              label: S.of(context).proteinLabel,
              color: palette.protein,
              palette: palette,
            ),
          ),
        ),
      ),
    );
    // [/fork]
  }
}

class _MacroRing extends StatelessWidget {
  final double intake;
  final double goal;
  final String label;
  final Color color;
  final AppPalette palette;

  const _MacroRing({
    required this.intake,
    required this.goal,
    required this.label,
    required this.color,
    required this.palette,
  });

  double get _percent {
    if (!intake.isFinite || !goal.isFinite || intake <= 0 || goal <= 0) {
      return 0;
    } else if (intake > goal) {
      return 1;
    } else {
      return intake / goal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        CircularPercentIndicator(
          radius: 15.0,
          lineWidth: 6.0,
          animation: true,
          percent: _percent,
          progressColor: color,
          backgroundColor: palette.surfaceMuted,
          circularStrokeCap: CircularStrokeCap.round,
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.all(Dimens.spacing4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${intake.isFinite ? intake.toInt() : 0}/'
                  '${goal.isFinite ? goal.toInt() : 0} g',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: palette.textStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
