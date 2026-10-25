import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart' show mealLabel;

/// The meal an entry goes to, as an outlined chip that opens the four
/// meals (S125's food page, S133's quick add).
class MealPickerChip extends StatelessWidget {
  final IntakeTypeEntity type;
  final ValueChanged<IntakeTypeEntity> onChanged;

  const MealPickerChip({
    super.key,
    required this.type,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<IntakeTypeEntity>(
    tooltip: 'Meal',
    initialValue: type,
    onSelected: onChanged,
    itemBuilder: (context) => [
      for (final t in IntakeTypeEntity.values)
        PopupMenuItem(value: t, child: Text(mealLabel(context, t))),
    ],
    child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing12),
      decoration: ShapeDecoration(
        shape: StadiumBorder(
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mealLabel(context, type)),
          const Icon(Icons.arrow_drop_down_rounded),
        ],
      ),
    ),
  );
}
