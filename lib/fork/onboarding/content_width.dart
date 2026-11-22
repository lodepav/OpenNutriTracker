import 'package:flutter/widgets.dart';

/// Onboarding's and the goal planner's content, centred at no more than
/// [maxWidth] on a tablet or a landscape phone; a phone in portrait is
/// narrower, so nothing changes there.
class ContentWidth extends StatelessWidget {
  static const maxWidth = 600.0;

  final Widget child;

  const ContentWidth({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Center(
    // As tall as the child, so a bottom bar stays its own height.
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
