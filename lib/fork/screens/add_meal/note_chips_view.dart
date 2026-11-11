import 'package:flutter/material.dart';
import 'package:opennutritracker/fork/bulk/note_chips.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';

/// Under a photo's note, before it is sent (D49): a chip puts its words in
/// the note, which stays editable, and a second tap takes them out. One
/// line that scrolls sideways, so the box above the rows does not grow at
/// large text (#820).
class NoteChipsView extends StatelessWidget {
  final TextEditingController controller;

  /// Focused for a chip that wants a number after its words.
  final FocusNode? focus;

  const NoteChipsView({super.key, required this.controller, this.focus});

  void _tap(NoteChip chip) {
    final next = toggleNoteChip(controller.text, chip);
    controller.value = TextEditingValue(
      text: next.text,
      selection: TextSelection.collapsed(offset: next.cursor),
    );
    if (chip.asksMore && noteHasChip(next.text, chip)) focus?.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: DishStrings.noteChipsLabel,
    child: SingleChildScrollView(
      key: const ValueKey('bulk-add-note-chips'),
      scrollDirection: Axis.horizontal,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Row(
          children: [
            for (final (i, chip) in noteChips.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Semantics(
                identifier: 'bulk-add-note-chip-$i',
                child: FilterChip(
                  key: ValueKey('bulk-add-note-chip-$i'),
                  label: Text(chip.label),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  selected: noteHasChip(controller.text, chip),
                  onSelected: (_) => _tap(chip),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
