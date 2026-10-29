import 'package:flutter/material.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

/// A phase's colour on the goal's calendar and bars: cut orange,
/// maintenance pale, bulk blue, apart in lightness as well as hue.
Color phaseColor(BuildContext context, PhaseKind kind) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (kind) {
    PhaseKind.cut => const Color(0xFFE59A4E),
    PhaseKind.maintain =>
      dark ? const Color(0xFF4A5552) : const Color(0xFFCFDAD7),
    PhaseKind.bulk => dark ? const Color(0xFFA9CCEB) : const Color(0xFF2C6E9E),
  };
}

/// Text on [phaseColor].
Color onPhaseColor(BuildContext context, PhaseKind kind) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (kind) {
    PhaseKind.bulk when !dark => Colors.white,
    PhaseKind.maintain when dark => Colors.white,
    _ => const Color(0xFF2B2A27),
  };
}

/// "Cut", "Maintenance", "Bulk"; maintenance inside a cut is a diet break.
String phaseName(PhaseKind kind, {bool inCut = false}) =>
    kind == PhaseKind.maintain && inCut ? 'Diet break' : kind.label;

/// The phase colours named, for the calendar and bars.
class PhaseLegend extends StatelessWidget {
  /// The kinds shown; every kind by default.
  final Set<PhaseKind> kinds;

  /// Maintenance is also a cut's diet breaks.
  final bool breaks;

  const PhaseLegend({
    super.key,
    this.kinds = const {...PhaseKind.values},
    this.breaks = false,
  });

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final kind in PhaseKind.values)
          if (kinds.contains(kind))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: phaseColor(context, kind),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  kind == PhaseKind.maintain && breaks
                      ? 'Maintenance or diet break'
                      : kind.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
      ],
    ),
  );
}

/// [plan]'s phases as one bar, each as long as its weeks.
class PhaseBar extends StatelessWidget {
  final PhasePlan plan;

  const PhaseBar(this.plan, {super.key});

  @override
  Widget build(BuildContext context) {
    final inCut = plan.kind == PhaseKind.cut;
    return Semantics(
      label: [
        for (final p in plan.phases)
          '${phaseName(p.kind, inCut: inCut)} ${p.weeks} '
              '${p.weeks == 1 ? 'week' : 'weeks'}',
      ].join(', '),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          height: 14,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, p) in plan.phases.indexed) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: p.weeks,
                  child: ColoredBox(color: phaseColor(context, p.kind)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
