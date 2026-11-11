import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/fork/bulk/amount_question.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';

/// The question on a photo's row, under its amount: one line, then the
/// chips that answer it with one tap. Once answered the line thanks the
/// user and the chips stay, so a mis-tap takes one more tap to correct.
/// Until then the chips are built around the amount [row] shows.
class AmountQuestionView extends StatelessWidget {
  final AmountQuestion question;

  /// The row it is asked on, as it is now.
  final BulkAddRow row;

  /// The row's index, for the keys.
  final int index;
  final ValueChanged<int> onChosen;

  const AmountQuestionView({
    super.key,
    required this.question,
    required this.row,
    required this.index,
    required this.onChosen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    final answered = question.answered != null;
    final choices = question.choicesFor(row);
    final selected = question.selectedIn(choices);
    return Semantics(
      container: true,
      child: Column(
        key: ValueKey('bulk-add-amount-question-$index'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            answered
                ? DishStrings.amountAnswered
                : DishStrings.amountQuestion(question.food),
            style: answered
                ? theme.textTheme.bodySmall?.copyWith(color: palette.textMuted)
                : theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textStrong,
                    fontWeight: FontWeight.w600,
                  ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, choice) in choices.indexed)
                Semantics(
                  identifier: 'bulk-add-amount-choice-$i',
                  child: ChoiceChip(
                    key: ValueKey('bulk-add-amount-choice-$index-$i'),
                    label: Text(choice.label, semanticsLabel: choice.spoken),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    selected: i == selected,
                    onSelected: (_) => onChosen(i),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
