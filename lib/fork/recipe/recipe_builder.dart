import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/util/food_emoji_resolver.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/fork/recipe/recipe_list.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Seam S127: the recipe builder after the canvas's "Recipe builder · A".
/// The name, then the ingredients with their amounts typed in place, the
/// rest folded under "Optional", and the totals with Save at the bottom.

/// [amount] without a trailing ".0".
String _amountText(double amount) => amount == amount.roundToDouble()
    ? amount.toInt().toString()
    : amount.toString();

/// An ingredient: its kind, name and macros; its amount typed in place, in
/// its own unit. A tap on the name opens the amount and unit dialog.
class BuilderIngredientRow extends StatefulWidget {
  final RecipeIngredientEntity ingredient;
  final ValueChanged<double> onAmount;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const BuilderIngredientRow({
    super.key,
    required this.ingredient,
    required this.onAmount,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  State<BuilderIngredientRow> createState() => _BuilderIngredientRowState();
}

class _BuilderIngredientRowState extends State<BuilderIngredientRow> {
  late final _amount = TextEditingController(
    text: _amountText(widget.ingredient.amount),
  );

  @override
  void didUpdateWidget(BuilderIngredientRow old) {
    super.didUpdateWidget(old);
    // The dialog changed it: show the new amount, unless it is the one
    // being typed.
    final typed = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (typed != widget.ingredient.amount) {
      _amount.text = _amountText(widget.ingredient.amount);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final ingredient = widget.ingredient;
    final meal = ingredient.snapshotMeal;
    final grams = ingredient.convertedAmountG;
    double of(double? per100) => (per100 ?? 0) * grams / 100;
    final n = meal.nutriments;
    final values = (
      kcal: of(n.energyKcal100),
      carbs: of(n.carbohydrates100),
      fat: of(n.fat100),
      protein: of(n.proteins100),
    );
    final emoji = OffKinds.emojiFor(meal) ?? resolveFoodEmoji(meal.name);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: Dimens.borderRadiusS,
            ),
            child: emoji != null
                ? ExcludeSemantics(
                    child: Text(emoji, style: const TextStyle(fontSize: 20)),
                  )
                : Icon(Icons.eco_rounded, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: Dimens.spacing12),
          Expanded(
            child: InkWell(
              borderRadius: Dimens.borderRadiusS,
              onTap: widget.onEdit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.name ?? '?',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${energyText(context, values.kcal)} · ',
                          ),
                          ...macroSpans(context, values),
                        ],
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: Dimens.spacing8),
          SizedBox(
            width: 84,
            child: Semantics(
              label: 'Amount of ${meal.name ?? 'the ingredient'}',
              child: TextField(
                controller: _amount,
                textAlign: TextAlign.end,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*([.,]\d{0,2})?$'),
                  ),
                ],
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: ingredient.unit,
                  border: const OutlineInputBorder(
                    borderRadius: Dimens.borderRadiusS,
                  ),
                ),
                onChanged: (text) {
                  final amount = double.tryParse(text.replaceAll(',', '.'));
                  if (amount != null && amount > 0) widget.onAmount(amount);
                },
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove ${meal.name ?? 'ingredient'}',
            icon: Icon(Icons.close_rounded, color: palette.textMuted),
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}

/// The recipe's energy and macros, and Save with its weight.
class BuilderSaveBar extends StatelessWidget {
  final MealNutrimentsEntity per100;
  final double totalWeightG;
  final bool saving;
  final VoidCallback onSave;

  const BuilderSaveBar({
    super.key,
    required this.per100,
    required this.totalWeightG,
    required this.saving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    double of(double? value) => (value ?? 0) * totalWeightG / 100;
    Widget figure(String value, String label, Color? color) => Expanded(
      child: MergeSemantics(
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
    return Material(
      color: palette.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing12,
            Dimens.spacing16,
            Dimens.spacing12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  figure(
                    '${energyValue(context, of(per100.energyKcal100))}',
                    energyUnit(context),
                    null,
                  ),
                  ...inMacroOrder(
                    carbs: figure(
                      '${of(per100.carbohydrates100).round()}',
                      '${s.carbsLabel} g',
                      palette.carbs,
                    ),
                    fat: figure(
                      '${of(per100.fat100).round()}',
                      '${s.fatLabel} g',
                      palette.fat,
                    ),
                    protein: figure(
                      '${of(per100.proteins100).round()}',
                      '${s.proteinLabel} g',
                      palette.protein,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Dimens.spacing12),
              Semantics(
                identifier: 'recipe-builder-save',
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: saving ? null : onSave,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: Dimens.spacing16,
                      ),
                    ),
                    child: Text(
                      totalWeightG > 0
                          ? '${s.recipeSaveLabel} · ${totalWeightG.round()} g'
                          : s.recipeSaveLabel,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
