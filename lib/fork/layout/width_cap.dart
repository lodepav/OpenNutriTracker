import 'package:flutter/widgets.dart';

/// [child] at most [maxWidth] wide, centred, on a tablet, in landscape or a
/// wide split window; on a phone it changes nothing. Wrap a scrolling
/// list's items rather than the list, so its sides still scroll.
// shortcut: one centred phone column at any width, no multi-column layout
// (the app is phone-first); lay tiles out wider if tablets matter.
class WidthCap extends StatelessWidget {
  static const double maxWidth = 600;

  final Widget child;

  const WidthCap({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final spare = constraints.maxWidth - maxWidth;
      // padding, not a loose box: the child keeps a tight width as before;
      // always a Padding, so crossing 600 dp doesn't remount the child
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spare > 0 && constraints.hasBoundedWidth ? spare / 2 : 0,
        ),
        child: child,
      );
    },
  );
}
