import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/custom_food/serving_mode.dart';

/// The Custom foods list with a search over its names, as the Recipes list
/// has (G3-25): [list] builds the foods that match, and a search that hides
/// them all says so with a way back.
class CustomFoodSearch extends StatefulWidget {
  final List<MealEntity> meals;
  final Widget Function(BuildContext context, List<MealEntity> shown) list;

  const CustomFoodSearch({super.key, required this.meals, required this.list});

  @override
  State<CustomFoodSearch> createState() => _CustomFoodSearchState();
}

class _CustomFoodSearchState extends State<CustomFoodSearch> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    CustomFoodModes.ensureLoaded();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.meals
        : widget.meals
              .where((m) => (m.name ?? '').toLowerCase().contains(q))
              .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing12,
            Dimens.spacing16,
            Dimens.spacing4,
          ),
          child: TextField(
            controller: _controller,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: palette.surfaceMuted,
              // a label, not a hint, so TalkBack names the field (A3)
              labelText: 'Search foods',
              floatingLabelBehavior: FloatingLabelBehavior.never,
              prefixIcon: Icon(Icons.search_rounded, color: palette.textMuted),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      icon: Icon(Icons.clear_rounded, color: palette.textMuted),
                      onPressed: _clear,
                    )
                  : null,
              border: const OutlineInputBorder(
                borderRadius: Dimens.borderRadiusM,
                borderSide: BorderSide.none,
              ),
              // the theme's 3:1 field edge, as the recipe search has
              enabledBorder: OutlineInputBorder(
                borderRadius: Dimens.borderRadiusM,
                borderSide: BorderSide(color: palette.textMuted),
              ),
            ),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Dimens.spacing32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'No foods match',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: palette.textMuted),
                        ),
                        const SizedBox(height: Dimens.spacing8),
                        TextButton(
                          onPressed: _clear,
                          child: const Text('Clear search'),
                        ),
                      ],
                    ),
                  ),
                )
              : widget.list(context, shown),
        ),
      ],
    );
  }
}
