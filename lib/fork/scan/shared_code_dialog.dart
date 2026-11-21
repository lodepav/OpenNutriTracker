import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The paste dialog of the recipe and workout importers: a code that isn't
/// one keeps the dialog open with the error under the field and the text kept.
/// Pops the trimmed code.
class SharedCodeDialog extends StatefulWidget {
  final String hint;
  final String actionLabel;
  final String invalidLabel;
  final bool Function(String code) isValid;

  const SharedCodeDialog({
    super.key,
    required this.hint,
    required this.actionLabel,
    required this.invalidLabel,
    required this.isValid,
  });

  @override
  State<SharedCodeDialog> createState() => _SharedCodeDialogState();
}

class _SharedCodeDialogState extends State<SharedCodeDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.isNotEmpty && widget.isValid(code)) {
      Navigator.of(context).pop(code);
    } else {
      setState(() => _error = widget.invalidLabel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: Dimens.shapeL,
      title: Text(S.of(context).pasteCodeLabel),
      content: SingleChildScrollView(
        child: TextField(
          controller: _controller,
          minLines: 3,
          maxLines: 5,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: _error,
            errorMaxLines: 3,
            border: const OutlineInputBorder(
              borderRadius: Dimens.borderRadiusS,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).dialogCancelLabel),
        ),
        TextButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}
