import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_meal_bloc.dart';
import 'package:opennutritracker/fork/screens/add_meal/meal_item_card.dart';

/// The add-meal screen before anything is typed (seam S116, MacroFactor's
/// search): the foods from the history, each at the amount last logged,
/// then the favourites, so the go-to foods are a glance away without
/// switching chips. Past [historyShown] foods the history waits behind
/// "Show all", or the favourites would sit under every food ever logged.
class SearchSections extends StatefulWidget {
  static const historyShown = 10;

  final DateTime day;
  final AddMealType addMealType;
  final bool usesImperialUnits;
  final List<MealEntity> history;

  /// The latest entry of each of [history], in the same order; empty when
  /// not known, and the rows show the food per 100 g.
  final List<IntakeEntity> entries;
  final FavouriteMealBloc favourites;

  const SearchSections({
    super.key,
    required this.day,
    required this.addMealType,
    required this.usesImperialUnits,
    required this.history,
    required this.entries,
    required this.favourites,
  });

  @override
  State<SearchSections> createState() => _SearchSectionsState();
}

class _SearchSectionsState extends State<SearchSections> {
  bool _all = false;

  @override
  void initState() {
    super.initState();
    // The Favourites chip may have left it filtered.
    widget.favourites.add(const LoadFavouriteMealEvent(searchString: ''));
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.history;
    final shown = _all
        ? history.length
        : history.length.clamp(0, SearchSections.historyShown);
    MealItemCard row(MealEntity meal, IntakeEntity? entry, bool imperial) =>
        MealItemCard(
          day: widget.day,
          mealEntity: meal,
          addMealType: widget.addMealType,
          usesImperialUnits: imperial,
          forkLastLogged: entry,
        );
    return Semantics(
      identifier: 'add-meal-recent-list',
      container: true,
      child: CustomScrollView(
        slivers: [
          if (history.isNotEmpty)
            SliverToBoxAdapter(
              child: _Header(
                title: 'From your history',
                note: widget.entries.isEmpty ? null : 'last amount',
              ),
            ),
          SliverList.builder(
            itemCount: shown,
            itemBuilder: (context, index) => row(
              history[index],
              index < widget.entries.length ? widget.entries[index] : null,
              widget.usesImperialUnits,
            ),
          ),
          if (shown < history.length)
            SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('search-history-all'),
                  onPressed: () => setState(() => _all = true),
                  child: Text('Show all ${history.length}'),
                ),
              ),
            ),
          BlocBuilder<FavouriteMealBloc, FavouriteMealState>(
            bloc: widget.favourites,
            builder: (context, state) {
              if (state is! FavouriteMealLoadedState ||
                  state.favourites.isEmpty) {
                return const SliverToBoxAdapter(child: SizedBox());
              }
              return SliverMainAxisGroup(
                slivers: [
                  const SliverToBoxAdapter(child: _Header(title: 'Favourites')),
                  SliverList.builder(
                    itemCount: state.favourites.length,
                    itemBuilder: (context, index) => row(
                      state.favourites[index],
                      null,
                      state.usesImperialUnits,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String? note;

  const _Header({required this.title, this.note});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: palette.textMuted);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: style?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (note != null) Text(note!, style: style),
        ],
      ),
    );
  }
}
