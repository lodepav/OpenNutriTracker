import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_activity/presentation/add_activity_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/meal_item_card.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/quick_add_bottom_sheet.dart';
import 'package:opennutritracker/features/scanner/scanner_screen.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart' show mealLabel;
import 'package:opennutritracker/fork/recents/recents_by_meal.dart'
    show recentKey;
import 'package:opennutritracker/generated/l10n.dart';

/// Seam S131: the + sheet after the canvas's "Add sheet · A". Search
/// first, the meal it goes to as chips (the time's meal picked), the
/// foods logged lately with that meal, then Quick add, Scan, Recipes and
/// Activity as tiles.
class AddSheet extends StatefulWidget {
  final DateTime day;
  final bool showActivityTracking;
  final bool usesImperialUnits;

  /// The meal picked when the sheet opens; the time's meal when null.
  final IntakeTypeEntity? suggestedType;

  const AddSheet({
    super.key,
    required this.day,
    this.showActivityTracking = true,
    this.usesImperialUnits = false,
    this.suggestedType,
  });

  @override
  State<AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<AddSheet> {
  late IntakeTypeEntity _type =
      widget.suggestedType ?? MealTypeSuggester.suggestFromTime(DateTime.now());

  /// Read once: the chips only re-sort what is already here.
  late final Future<List<IntakeEntity>>? _recent =
      locator.isRegistered<GetIntakeUsecase>()
      ? locator<GetIntakeUsecase>().getRecentIntake()
      : null;

  AddMealType get _mealType => AddMealExtension.fromIntakeTypeEntity(_type);

  void _openSearch() {
    Navigator.of(context)
      ..pop()
      ..pushNamed(
        NavigationOptions.addMealRoute,
        arguments: AddMealScreenArguments(_mealType, widget.day),
      );
  }

  void _openScanner() {
    Navigator.of(context)
      ..pop()
      ..pushNamed(
        NavigationOptions.scannerRoute,
        arguments: ScannerScreenArguments(widget.day, _type),
      );
  }

  void _openQuickAdd() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickAddBottomSheet(intakeType: _type, day: widget.day),
    );
  }

  void _openRecipes() {
    Navigator.of(context)
      ..pop()
      // The meal picked here is the one a recipe logs to.
      ..pushNamed(NavigationOptions.recipesRoute, arguments: _type);
  }

  void _openActivity() {
    Navigator.of(context)
      ..pop()
      ..pushNamed(
        NavigationOptions.addActivityRoute,
        arguments: AddActivityScreenArguments(day: widget.day),
      );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing8,
          Dimens.spacing16,
          Dimens.spacing16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                s.addItemLabel,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: Dimens.spacing12),
            Semantics(
              identifier: 'add-item-search',
              button: true,
              label: '${s.searchLabel}, ${mealLabel(context, _type)}',
              excludeSemantics: true,
              child: Material(
                color: palette.surfaceMuted,
                borderRadius: Dimens.borderRadiusM,
                child: InkWell(
                  borderRadius: Dimens.borderRadiusM,
                  onTap: _openSearch,
                  child: SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        const SizedBox(width: Dimens.spacing12),
                        Icon(Icons.search_rounded, color: palette.textMuted),
                        const SizedBox(width: Dimens.spacing8),
                        Expanded(
                          child: Text(
                            s.searchLabel,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Dimens.spacing12),
            Wrap(
              spacing: Dimens.spacing8,
              runSpacing: Dimens.spacing4,
              children: [
                for (final type in IntakeTypeEntity.values)
                  Semantics(
                    identifier: 'add-item-${type.name}',
                    child: ChoiceChip(
                      label: Text(mealLabel(context, type)),
                      selected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                    ),
                  ),
              ],
            ),
            _recentFoods(context),
            const SizedBox(height: Dimens.spacing16),
            _tiles(context, [
              _tile(
                context,
                id: 'quick-add',
                icon: Icons.bolt_rounded,
                label: s.quickAddCardLabel,
                onTap: _openQuickAdd,
              ),
              _tile(
                context,
                id: 'scan',
                icon: Icons.qr_code_scanner_rounded,
                label: 'Scan',
                onTap: _openScanner,
              ),
              _tile(
                context,
                id: 'recipes',
                icon: Icons.menu_book_outlined,
                label: s.recipesLabel,
                onTap: _openRecipes,
              ),
              if (widget.showActivityTracking)
                _tile(
                  context,
                  id: 'activity',
                  icon: UserActivityEntity.getIconData(),
                  label: s.activityLabel,
                  onTap: _openActivity,
                ),
            ]),
          ],
        ),
      ),
    );
  }

  /// Up to four foods logged lately with the picked meal, else with any.
  Widget _recentFoods(BuildContext context) {
    final recent = _recent;
    if (recent == null) return const SizedBox.shrink();
    return FutureBuilder<List<IntakeEntity>>(
      future: recent,
      builder: (context, snapshot) {
        final intakes = snapshot.data;
        if (intakes == null || intakes.isEmpty) return const SizedBox.shrink();
        final forMeal = intakes.where((i) => i.type == _type).toList();
        final shown = (forMeal.isEmpty ? intakes : forMeal).take(4).toList();
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: Dimens.spacing16,
                bottom: Dimens.spacing4,
              ),
              child: Text(
                forMeal.isEmpty
                    ? S.of(context).recentlyAddedLabel
                    : 'Recent for ${mealLabel(context, _type)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final (index, intake) in shown.indexed)
              MealItemCard(
                key: ValueKey('add-item-recent-${recentKey(intake)}-$_type'),
                day: widget.day,
                mealEntity: intake.meal,
                addMealType: _mealType,
                usesImperialUnits: widget.usesImperialUnits,
                favouriteSemanticsIdentifier:
                    'add-item-recent-favourite-${index + 1}',
                // The amount it was logged with, as search shows it.
                forkLastLogged: intake,
              ),
          ],
        );
      },
    );
  }

  /// The tiles on one row, or two rows of two with large text, so their
  /// names do not break mid-word (A6).
  Widget _tiles(BuildContext context, List<Widget> tiles) {
    final large = MediaQuery.textScalerOf(context).scale(10) > 13;
    final perRow = large ? 2 : tiles.length;
    return Column(
      spacing: Dimens.spacing8,
      children: [
        for (var i = 0; i < tiles.length; i += perRow)
          Row(
            spacing: Dimens.spacing8,
            children: [
              ...tiles.skip(i).take(perRow),
              // An odd last tile keeps its half.
              if (tiles.length - i < perRow) const Spacer(),
            ],
          ),
      ],
    );
  }

  Widget _tile(
    BuildContext context, {
    required String id,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    return Expanded(
      child: Semantics(
        identifier: 'add-item-$id',
        button: true,
        child: Material(
          color: palette.surfaceMuted,
          borderRadius: Dimens.borderRadiusM,
          child: InkWell(
            borderRadius: Dimens.borderRadiusM,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: Dimens.spacing12,
                  horizontal: Dimens.spacing4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(height: Dimens.spacing4),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
