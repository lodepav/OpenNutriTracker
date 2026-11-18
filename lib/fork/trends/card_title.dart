import 'package:flutter/widgets.dart';

/// A card's title as a heading TalkBack can jump to, in its own node so the
/// heading is the title, not the card.
class CardTitle extends StatelessWidget {
  final Widget child;

  const CardTitle({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, header: true, child: child);
}
