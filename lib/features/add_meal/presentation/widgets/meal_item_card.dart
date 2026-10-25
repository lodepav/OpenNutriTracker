import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/off_const.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_const.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/favourite_toggle_button.dart';
import 'package:opennutritracker/features/add_meal/util/food_emoji_resolver.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S83 search-macros
import 'package:opennutritracker/fork/display/meal_macros_line.dart';
// [/fork]
// [fork] S116 search-dense
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
// [/fork]

class MealItemCard extends StatelessWidget {
  final DateTime day;
  final AddMealType addMealType;
  final MealEntity mealEntity;
  final bool usesImperialUnits;
  final String? favouriteSemanticsIdentifier;
  // [fork] S116 search-dense: a recent's latest entry; the row then shows
  // that amount's energy and macros instead of those per 100 g
  final IntakeEntity? forkLastLogged;
  static const double forkThumb = 32;
  // [/fork]

  const MealItemCard({
    super.key,
    required this.day,
    required this.mealEntity,
    required this.addMealType,
    required this.usesImperialUnits,
    this.favouriteSemanticsIdentifier,
    this.forkLastLogged, // [fork] S116
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    final isRecipe = mealEntity.source == MealSourceEntity.recipe;
    // Colored emoji is reserved for FDC base-food items where the head
    // noun reliably identifies the food ("Milk, fluid, nonfat..." → milk).
    // OFF products are branded, so a head-noun match would often be
    // misleading; they keep the outline icon as a placeholder.
    final emoji = (mealEntity.thumbnailImageUrl == null && mealEntity.source == MealSourceEntity.fdc)
        ? resolveFoodEmoji(mealEntity.name)
        : null;
    // [fork] S116 search-dense: a row as short as a logged food's (S115):
    // a 32 dp picture, the source and macros under the name, the energy
    // and what it is for on the trailing edge, a small add button. Was a
    // 60 dp picture, a source chip, the package quantity and the per-100 g
    // line on rows of their own.
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: palette.textMuted);
    final last = forkLastLogged;
    final n = mealEntity.nutriments;
    final kcal = last?.totalKcal ?? n.energyKcal100;
    final per = last != null
        ? _forkAmount(last)
        : 'per 100 ${mealEntity.isLiquid ? 'ml' : 'g'}';
    final source = isRecipe
        ? S.of(context).additionalInfoLabelRecipe
        : _sourceLabel();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: AppCard(
        onTap: () => _onItemPressed(context),
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing12,
          6,
          Dimens.spacing4,
          6,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Row(
            children: [
              _buildThumbnail(context, palette, accent, isRecipe, emoji),
              const SizedBox(width: Dimens.spacing12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AutoSizeText.rich(
                      TextSpan(
                        text: mealEntity.name ?? "?",
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: palette.textStrong,
                        ),
                        children: [
                          TextSpan(
                            text: ' ${mealEntity.brands ?? ""}',
                            style: muted,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      minFontSize: 11,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    MacrosLine(
                      lead: source,
                      carbs: last?.totalCarbsGram ?? n.carbohydrates100,
                      fat: last?.totalFatsGram ?? n.fat100,
                      protein: last?.totalProteinsGram ?? n.proteins100,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Dimens.spacing8),
              if (kcal != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      energyText(context, kcal),
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: palette.textStrong,
                      ),
                    ),
                    Text(per, style: muted),
                  ],
                ),
              // A builder row leaves the identifier out and its list
              // carries one (AGENTS.md, "Dynamic lists"); the add-item
              // sheet's fixed recent rows pass their own.
              FavouriteToggleButton(
                meal: mealEntity,
                semanticsIdentifier: favouriteSemanticsIdentifier,
              ),
              Semantics(
                identifier: 'meal-item-add',
                child: IconButton(
                  style: IconButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent, width: 1.5),
                    shape: const CircleBorder(),
                    minimumSize: const Size(32, 32),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  tooltip: S.of(context).addFoodLabel(mealEntity.name ?? ''), // [fork] S83
                  onPressed: () => _onItemPressed(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // [/fork]
  }

  // [fork] S116 search-dense
  static String _forkAmount(IntakeEntity intake) {
    final n = intake.amount;
    final text = n == n.roundToDouble()
        ? n.toInt().toString()
        : n.toStringAsFixed(1);
    return '$text ${intake.unit}';
  }
  // [/fork]

  Widget _buildThumbnail(
    BuildContext context,
    AppPalette palette,
    Color accent,
    bool isRecipe,
    String? emoji,
  ) {
    final radius = BorderRadius.circular(Dimens.radiusM);
    if (mealEntity.thumbnailImageUrl != null) {
      return ClipRRect(
        borderRadius: radius,
        child: CachedNetworkImage(
          cacheManager: locator<CacheManager>(),
          fit: BoxFit.cover,
          width: forkThumb, // [fork] S116: was Dimens.mealThumb
          height: forkThumb, // [fork] S116
          imageUrl: mealEntity.thumbnailImageUrl ?? "",
        ),
      );
    }
    return Container(
      width: forkThumb, // [fork] S116: was Dimens.mealThumb
      height: forkThumb, // [fork] S116
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: isRecipe ? accent.withValues(alpha: 0.16) : palette.surfaceMuted,
      ),
      child: emoji != null
          ? ExcludeSemantics(
              child: Text(emoji, style: const TextStyle(fontSize: 18)), // [fork] S116: was 30
            )
          : Icon(
              isRecipe ? Icons.menu_book_rounded : Icons.restaurant_rounded,
              size: 18, // [fork] S116: was 26
              color: isRecipe ? accent : palette.textMuted,
            ),
    );
  }

  // [fork] S116 search-dense: upstream's _buildSubtitle and _labelChip
  // went with the source chip

  /// Database-of-origin label: the Supabase backend source (BLS, FDC SR
  /// Legacy...) when known, Open Food Facts for OFF products, null for the
  /// user's own custom meals.
  String? _sourceLabel() {
    final backendLabel = SPConst.foodSourceShortNames[mealEntity.backendSource];
    if (backendLabel != null) return backendLabel;
    if (mealEntity.source == MealSourceEntity.off) {
      return OFFConst.offSourceName;
    }
    return null;
  }

  void _onItemPressed(BuildContext context) {
    Navigator.of(context).pushNamed(
      NavigationOptions.mealDetailRoute,
      arguments: MealDetailScreenArguments(
        mealEntity,
        addMealType.getIntakeType(),
        day,
        usesImperialUnits,
      ),
    );
  }
}
