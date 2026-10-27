import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/fork/food/result_groups.dart';
import 'package:opennutritracker/fork/recents/search_sections.dart';
import 'package:opennutritracker/fork/screens/add_meal/meal_item_card.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// The All list, and the Products tab's, as [sectionResults] splits it: the user's own foods, then
/// "Basic foods" (the first [basicShown], the rest behind "Show more"),
/// then "Products", where a name several products share is one row that
/// opens in place to its products.
class ResultSections extends StatefulWidget {
  static const basicShown = 3;
  static const groupShown = 5;

  final DateTime day;
  final AddMealType addMealType;
  final bool usesImperialUnits;
  final List<MealEntity> merged;

  /// The Food search's own list, whose order the basic foods keep, and the
  /// search, which puts a product named for none of its words last (see
  /// [sectionResults]).
  final List<MealEntity> basicOrder;
  final String query;

  /// A last row under the sections, as the Products tab's note that the
  /// online search found nothing.
  final Widget? footer;

  /// Whether the products go under their heading; the Products tab is
  /// named for them already.
  final bool productsHeading;

  const ResultSections({
    super.key,
    required this.day,
    required this.addMealType,
    required this.usesImperialUnits,
    required this.merged,
    this.basicOrder = const [],
    this.query = '',
    this.footer,
    this.productsHeading = true,
  });

  @override
  State<ResultSections> createState() => _ResultSectionsState();
}

class _ResultSectionsState extends State<ResultSections> {
  bool _allBasic = false;
  final _open = <Object>{};
  final _openAll = <Object>{};

  @override
  void didUpdateWidget(ResultSections old) {
    super.didUpdateWidget(old);
    // A new search starts closed.
    if (!identical(old.merged, widget.merged)) {
      _allBasic = false;
      _open.clear();
      _openAll.clear();
    }
  }

  MealItemCard _row(MealEntity meal) => MealItemCard(
    day: widget.day,
    mealEntity: meal,
    addMealType: widget.addMealType,
    usesImperialUnits: widget.usesImperialUnits,
  );

  Widget _more(String label, VoidCallback onPressed) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(onPressed: onPressed, child: Text(label)),
  );

  @override
  Widget build(BuildContext context) {
    final sections = sectionResults(
      widget.merged,
      basicOrder: widget.basicOrder,
      query: widget.query,
    );
    final basic = sections.basic;
    final basicShown = _allBasic
        ? basic.length
        : basic.length.clamp(0, ResultSections.basicShown);
    final rows = <Widget>[
      for (final meal in sections.own) _row(meal),
      if (basic.isNotEmpty)
        SearchSectionHeader(title: 'Basic foods · ${_basicSources(basic)}'),
      for (final meal in basic.take(basicShown)) _row(meal),
      if (basicShown < basic.length)
        _more(
          'Show ${basic.length - basicShown} more basic foods',
          () => setState(() => _allBasic = true),
        ),
      if (widget.productsHeading && sections.products.isNotEmpty)
        const SearchSectionHeader(title: 'Products · Open Food Facts'),
      for (final group in sections.products) ..._group(group),
      ?widget.footer,
    ];
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }

  List<Widget> _group(List<MealEntity> group) {
    if (group.length == 1) return [_row(group.single)];
    final key = productGroupKey(group.first);
    final open = _open.contains(key);
    final shown = _openAll.contains(key)
        ? group.length
        : group.length.clamp(0, ResultSections.groupShown);
    return [
      _GroupRow(
        group: group,
        open: open,
        onTap: () => setState(() => open ? _open.remove(key) : _open.add(key)),
      ),
      if (open) ...[
        for (final meal in group.take(shown))
          Padding(
            padding: const EdgeInsets.only(left: Dimens.spacing24),
            child: _row(meal),
          ),
        if (shown < group.length)
          Padding(
            padding: const EdgeInsets.only(left: Dimens.spacing24),
            child: _more(
              'Show ${group.length - shown} more',
              () => setState(() => _openAll.add(key)),
            ),
          ),
      ],
    ];
  }

  /// The tables [basic] comes from, as the user knows them.
  static String _basicSources(List<MealEntity> basic) {
    final names = <String>{
      for (final meal in basic)
        switch (meal.backendSource) {
          final s? when s.startsWith('fdc') => 'USDA',
          'bls' => 'BLS',
          'fork_dishes' => 'OpenBite',
          _ => 'USDA',
        },
    };
    return [
      for (final name in ['USDA', 'BLS', 'OpenBite'])
        if (names.contains(name)) name,
    ].join(', ');
  }
}

/// One row for the products a name shares: how many, whose, and the
/// range of their energy per 100 g.
class _GroupRow extends StatelessWidget {
  final List<MealEntity> group;
  final bool open;
  final VoidCallback onTap;

  const _GroupRow({
    required this.group,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: palette.textMuted);
    final name = group.first.name ?? '?';
    final brands = <String>{
      for (final meal in group)
        if (meal.brands?.trim() case final b? when b.isNotEmpty) b,
    }.toList();
    final whose = switch (brands.length) {
      0 => '${group.length} products',
      <= 3 => brands.join(', '),
      _ => '${brands.take(2).join(', ')} and ${brands.length - 2} more',
    };
    final typical = typicalRange([
      for (final meal in group) ?meal.nutriments.energyKcal100,
    ]);
    final range = typical == null
        ? null
        : typical.low.round() == typical.high.round()
        ? energyText(context, typical.low)
        : '${energyValue(context, typical.low)}–'
              '${energyText(context, typical.high)}';
    final unit = group.every((m) => m.isLiquid) ? 'ml' : 'g';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        button: true,
        expanded: open,
        label:
            '$name, ${group.length} products'
            '${range == null ? '' : ', $range per 100 $unit'}',
        excludeSemantics: true,
        onTap: onTap,
        child: AppCard(
          onTap: onTap,
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
                Container(
                  width: MealItemCard.forkThumb,
                  height: MealItemCard.forkThumb,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Dimens.radiusM),
                    color: palette.surfaceMuted,
                  ),
                  child: Text(
                    '${group.length}',
                    style: text.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.textStrong,
                    ),
                  ),
                ),
                const SizedBox(width: Dimens.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: palette.textStrong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        whose,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Dimens.spacing8),
                if (range != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        range,
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: palette.textStrong,
                        ),
                      ),
                      Text('per 100 $unit', style: muted),
                    ],
                  ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
