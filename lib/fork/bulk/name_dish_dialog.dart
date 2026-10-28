import 'package:flutter/material.dart';

/// Asks what the photo shows, for reading the same photo again with it as
/// the note. A photo names a regional dish generically ("dumplings",
/// "stuffed pie"); with a note every model named every dish in the eval,
/// and the published photo studies found a misnamed dish the costliest
/// error. Null when cancelled or left empty.
Future<String?> askDishName(BuildContext context, {String initial = ''}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDishDialog(initial: initial),
    );

class _NameDishDialog extends StatefulWidget {
  final String initial;

  const _NameDishDialog({required this.initial});

  @override
  State<_NameDishDialog> createState() => _NameDishDialogState();
}

class _NameDishDialogState extends State<_NameDishDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    Navigator.pop(context, text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Name what you ate'),
    content: Semantics(
      identifier: 'name-dish-field',
      child: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          hintText: 'e.g. pelmeni with sour cream, 2 pancakes',
          helperText: 'The photo is read again with this',
          helperMaxLines: 2,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      Semantics(
        identifier: 'name-dish-read-again',
        child: FilledButton(
          onPressed: _submit,
          child: const Text('Read again'),
        ),
      ),
    ],
  );
}
