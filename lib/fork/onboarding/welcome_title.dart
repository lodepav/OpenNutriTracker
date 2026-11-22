import 'package:flutter/material.dart';

/// The intro page's title as a heading TalkBack can jump to, drawn as
/// introduction_screen draws a plain title.
class WelcomeTitle extends StatelessWidget {
  final String text;
  final TextStyle style;

  const WelcomeTitle(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: style, textAlign: TextAlign.center),
  );
}
