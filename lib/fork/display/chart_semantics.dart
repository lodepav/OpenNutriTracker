import 'package:flutter/widgets.dart';

/// A chart as one TalkBack node, its [label] the name and range in words:
/// the axis ticks under it are not read after it.
class ChartSemantics extends StatelessWidget {
  final String label;
  final Widget child;

  const ChartSemantics({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    excludeSemantics: true,
    child: child,
  );
}

/// A series' first and last figure in words, for a [ChartSemantics] label.
String spokenFromTo(String first, String last, String unit) =>
    first == last ? 'at $first $unit' : 'from $first to $last $unit';
