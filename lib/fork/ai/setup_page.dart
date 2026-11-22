import 'package:flutter/material.dart';

/// AI setup as a full-screen page (seam S582, G6-27): a settings page with a
/// provider list, key, model and checks had outgrown an AlertDialog. Takes
/// the dialog's title, content and actions, so the setup's own build is
/// unchanged; the actions sit under the content, above the keyboard.
class AiSetupPage extends StatelessWidget {
  const AiSetupPage({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: title),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                // The content keeps its own 12 dp gutter for the scrollbar
                padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
                child: content,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
