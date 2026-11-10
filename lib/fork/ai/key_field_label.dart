import 'package:flutter/material.dart';

/// An AI key field's label, drawn above the field rather than inside it
/// (S211): a label in the field stays on one line, and at twice the font
/// size "OpenRouter API key" and "Google Gemini API key" were cut off (UX A6).
/// The field carries the same text as its semantics label, so this copy is
/// kept out of semantics and a screen reader reads the name once.
class AiKeyLabel extends StatelessWidget {
  final String text;

  const AiKeyLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ExcludeSemantics(
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
