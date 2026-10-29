// Fork-owned copy of lib/features/add_meal/presentation/add_meal_screen.dart (D23); upstream's later changes to it
// are ported by hand: fork/tools/upstream-copies.sh.
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/empty_hint.dart';
import 'package:opennutritracker/core/presentation/widgets/error_dialog.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/add_meal_bloc.dart';
// Upstream's arguments, so upstream's callers open this screen too.
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart'
    show AddMealScreenArguments;
export 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart'
    show AddMealScreenArguments;
import 'package:opennutritracker/fork/screens/add_meal/bulk_add_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/food_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/recent_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/search_debounce.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/default_results_widget.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/meal_search_bar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/no_results_widget.dart';
import 'package:opennutritracker/fork/screens/add_meal/meal_item_card.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/partial_results_notice.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/quick_add_bottom_sheet.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/products_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_relevance_ranker.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/scanner/scanner_screen.dart';
import 'package:opennutritracker/features/scanner/util/barcode_check_digit.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/screens/add_meal/result_sections.dart';
import 'package:opennutritracker/fork/bulk/ai_add.dart';
import 'package:opennutritracker/fork/suggest/fits_left.dart';
import 'package:opennutritracker/fork/recents/search_sections.dart';

class AddMealScreen extends StatefulWidget {
  const AddMealScreen({super.key});

  @override
  State<AddMealScreen> createState() => _AddMealScreenState();
}

class _AddMealScreenState extends State<AddMealScreen> {
  final ValueNotifier<String> _searchStringListener = ValueNotifier('');

  late AddMealType _mealType;
  late DateTime _day;

  late ProductsBloc _productsBloc;
  late FoodBloc _foodBloc;
  late RecentMealBloc _recentMealBloc;
  late FavouriteMealBloc _favouriteMealBloc;

  // one bloc for the app bar and AI add, both need the units
  final _addMealBloc = locator<AddMealBloc>()..add(InitializeAddMealEvent());

  // AI add replaces the list icon while AI meal assistance is on
  final _aiAdd = aiAddEnabled();

  // Single smart search: one field, one results list, and source-filter chips.
  // Opens on Recent (fast re-logging); typing searches Products by default,
  // with Food / Recent a chip away.
  _SearchSource _source = _SearchSource.recent;

  // #576: once the user explicitly taps the Recent chip, typing should keep
  // filtering Recent instead of silently jumping to All (the default-Recent
  // case still upgrades to All on first keystroke, matching existing
  // behavior for someone who never touched the chips).
  bool _stickOnRecent = false;

  @override
  void initState() {
    _productsBloc = locator<ProductsBloc>();
    _foodBloc = locator<FoodBloc>();
    _recentMealBloc = locator<RecentMealBloc>();
    _favouriteMealBloc = locator<FavouriteMealBloc>();
    super.initState();
  }

  @override
  void didChangeDependencies() {
    final args =
        ModalRoute.of(context)?.settings.arguments as AddMealScreenArguments;
    _mealType = args.mealType;
    _day = args.day;
    // the recents put this meal's usual foods first
    _recentMealBloc.forkMeal = _mealType.getIntakeType();
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _searchStringListener.dispose();
    _favouriteMealBloc.close();
    _addMealBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Scaffold(
      // Let the keyboard overlay the results rather than compress the body.
      // In landscape the space above the keyboard is shorter than the pinned
      // search bar + tab bar, which otherwise overflows (issue #165 testing).
      resizeToAvoidBottomInset: false,
      // the foods picked so far, and "Log all"
      bottomNavigationBar: BasketBar(
        type: _mealType.getIntakeType(),
        day: _day,
      ),
      floatingActionButton: _aiAddFab(),
      appBar: AppBar(
        title: Text(_mealType.getTypeName(context)),
        actions: [
          Semantics(
            identifier: 'add-meal-quick-add',
            // an icon, as the actions beside it, so the meal
            // in the title has room (A6); Quick add is a tile on the + sheet
            child: IconButton(
              onPressed: _onQuickAddPressed,
              icon: const Icon(Icons.bolt_rounded),
              tooltip: S.of(context).quickAddCardLabel,
            ),
          ),
          BlocBuilder<AddMealBloc, AddMealState>(
            bloc: _addMealBloc,
            builder: (BuildContext context, AddMealState state) {
              if (state is AddMealLoadedState) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FutureBuilder<bool>(
                      future: _aiAdd,
                      builder: (context, ai) => ai.data == false
                          ? Semantics(
                              identifier: 'add-meal-bulk-add',
                              child: IconButton(
                                onPressed: () =>
                                    _onBulkAddPressed(state.usesImperialUnits),
                                icon: const Icon(Icons.playlist_add),
                                tooltip: S.of(context).bulkAddTitle,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Semantics(
                      identifier: 'add-meal-custom-add',
                      child: IconButton(
                        onPressed: () =>
                            _onCustomAddButtonPressed(state.usesImperialUnits),
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: S.of(context).newCustomMealLabel,
                      ),
                    ),
                  ],
                );
              }
              return const SizedBox();
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
          child: Column(
            children: [
              const SizedBox(height: Dimens.spacing8),
              MealSearchBar(
                searchStringListener: _searchStringListener,
                onSearchSubmit: _onSearchSubmit,
                onSearchChanged: _onSearchChanged,
                onBarcodePressed: _onBarcodeIconPressed,
                // opened to search, so the keyboard is up
                autofocus: true,
              ),
              const SizedBox(height: Dimens.spacing12),
              _buildSourceChips(context, palette),
              const SizedBox(height: Dimens.spacing12),
              // Rebuild on every keystroke so the empty-state logic can tell
              // "no results for this query" apart from "a newer query is
              // still debouncing/searching" — the latter shows a spinner.
              Expanded(
                // the lists scroll their last row clear of AI add
                child: FutureBuilder<bool>(
                  future: _aiAdd,
                  builder: (context, ai) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      padding: MediaQuery.paddingOf(
                        context,
                      ).copyWith(bottom: ai.data == true ? 88 : 0),
                    ),
                    child: ValueListenableBuilder<String>(
                      valueListenable: _searchStringListener,
                      builder: (context, query, _) =>
                          _buildResults(context, palette, query),
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

  void _onProductsRefreshButtonPressed() {
    _productsBloc.add(const RefreshProductsEvent());
  }

  void _onFoodRefreshButtonPressed() {
    _foodBloc.add(const RefreshFoodEvent());
  }

  void _onAllSourcesRefreshButtonPressed() {
    _onProductsRefreshButtonPressed();
    _onFoodRefreshButtonPressed();
  }

  void _onRecentMealsRefreshButtonPressed() {
    _recentMealBloc.add(const LoadRecentMealEvent(searchString: ""));
  }

  void _onFavouritesRefreshButtonPressed() {
    _favouriteMealBloc.add(
      LoadFavouriteMealEvent(searchString: _searchStringListener.value),
    );
  }

  /// Resolves the source to search for a query: an empty query always returns
  /// to Recent; a non-empty query searches Products by default, unless the user
  /// has explicitly chosen Food. Keeps the chip selection and the results in sync.
  /// Favourites is the exception — a chosen list the query filters, so typing
  /// or clearing the field keeps the user on it.
  _SearchSource _resolveSource(String trimmed) {
    if (_source == _SearchSource.favourites) return _SearchSource.favourites;
    if (trimmed.isEmpty) return _SearchSource.recent;
    if (_source == _SearchSource.recent) {
      // Typing searches every source at once (All) by default — unless the
      // user explicitly chose the Recent chip, in which case it stays put
      // and filters recent history instead (#576).
      return _stickOnRecent ? _SearchSource.recent : _SearchSource.all;
    }
    // An explicit Products / Food choice narrows that merged list.
    return _source;
  }

  bool _searchesProducts(_SearchSource s) =>
      s == _SearchSource.all || s == _SearchSource.products;
  bool _searchesFood(_SearchSource s) =>
      s == _SearchSource.all || s == _SearchSource.food;

  void _onSearchSubmit(String inputText) {
    final trimmed = inputText.trim();
    final source = _resolveSource(trimmed);
    if (source != _source) setState(() => _source = source);
    // A scannable barcode jumps straight to the scanner (product sources only).
    if (_searchesProducts(source) && isValidBarcodeCheckDigit(trimmed)) {
      Navigator.of(context).pushNamed(
        NavigationOptions.scannerRoute,
        arguments: ScannerScreenArguments(
          _day,
          _mealType.getIntakeType(),
          initialBarcode: trimmed,
        ),
      );
      return;
    }
    if (_searchesProducts(source)) {
      _productsBloc.add(LoadProductsEvent(searchString: inputText));
    }
    if (_searchesFood(source)) {
      _foodBloc.add(LoadFoodEvent(searchString: inputText));
    }
    if (source == _SearchSource.recent) {
      _recentMealBloc.add(LoadRecentMealEvent(searchString: inputText));
    }
    if (source == _SearchSource.favourites) {
      _favouriteMealBloc.add(LoadFavouriteMealEvent(searchString: inputText));
    }
  }

  /// Debounced search-as-you-type. Recent filters local intake history; the
  /// remote sources debounce via their own *InputChanged events. "All" searches
  /// products and food together into one merged list.
  void _onSearchChanged(String inputText) {
    final trimmed = inputText.trim();
    final source = _resolveSource(trimmed);
    if (source != _source) setState(() => _source = source);
    if (_searchesProducts(source)) {
      _productsBloc.add(SearchInputChangedEvent(searchString: inputText));
    }
    if (_searchesFood(source)) {
      _foodBloc.add(SearchFoodInputChangedEvent(searchString: inputText));
    }
    if (source == _SearchSource.recent) {
      // Filters the history already in memory rather than re-reading the
      // whole intake box on every keystroke.
      _recentMealBloc.add(
        RecentMealSearchChangedEvent(searchString: inputText),
      );
    }
    if (source == _SearchSource.favourites) {
      _favouriteMealBloc.add(LoadFavouriteMealEvent(searchString: inputText));
    }
  }

  void _selectSource(_SearchSource source) {
    setState(() {
      _source = source;
      _stickOnRecent = source == _SearchSource.recent;
    });
    final query = _searchStringListener.value;
    if (_searchesProducts(source)) {
      _productsBloc.add(LoadProductsEvent(searchString: query));
    }
    if (_searchesFood(source)) {
      _foodBloc.add(LoadFoodEvent(searchString: query));
    }
    if (source == _SearchSource.recent) {
      _recentMealBloc.add(LoadRecentMealEvent(searchString: query));
    }
    if (source == _SearchSource.favourites) {
      _favouriteMealBloc.add(LoadFavouriteMealEvent(searchString: query));
    }
  }

  // #576: "Search all" CTA on an empty filtered-Recent result — switches to
  // the All chip without the user having to find and tap it themselves.
  void _onSearchAllPressed() => _selectSource(_SearchSource.all);

  Widget _buildSourceChips(BuildContext context, AppPalette palette) {
    Widget chip(_SearchSource source, String label) => Padding(
      padding: const EdgeInsets.only(right: Dimens.spacing8),
      child: ChoiceChip(
        label: Text(label),
        // the check marks the chosen source; colour alone is too faint
        selected: _source == source,
        onSelected: (_) => _selectSource(source),
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(_SearchSource.recent, S.of(context).recentlyAddedLabel),
            Semantics(
              identifier: 'add-meal-source-favourites',
              child: chip(
                _SearchSource.favourites,
                S.of(context).favouritesLabel,
              ),
            ),
            chip(_SearchSource.all, S.of(context).allItemsLabel),
            chip(_SearchSource.products, S.of(context).searchProductsPage),
            chip(_SearchSource.food, S.of(context).searchFoodPage),
          ],
        ),
      ),
    );
  }

  Widget _resultsHeader(BuildContext context, AppPalette palette) => Container(
    padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
    alignment: Alignment.centerLeft,
    child: Text(
      S.of(context).searchResultsLabel,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: palette.textMuted,
      ),
    ),
  );

  /// True while the results carried by [state] lag behind [query]: the
  /// search for the current input is still debouncing or in flight. Empty
  /// views show a spinner in that window instead of a premature "no
  /// results". Sub-threshold input never searches, so it is never pending;
  /// failed states return false so the error stays visible.
  static bool _productsPending(ProductsState state, String query) {
    if (state is ProductsLoadingState) return true;
    if (query.trim().length < minQueryLength) return false;
    if (state is ProductsInitial) return true;
    if (state is ProductsLoadedState) return state.query != query;
    return false;
  }

  static bool _foodPending(FoodState state, String query) {
    if (state is FoodLoadingState) return true;
    if (query.trim().length < minQueryLength) return false;
    if (state is FoodInitial) return true;
    if (state is FoodLoadedState) return state.query != query;
    return false;
  }

  // Fixed-size and top-aligned: the "All" view returns this inside an
  // Expanded, whose tight constraints would otherwise stretch the
  // indicator across the whole results area.
  static const _pendingSpinner = Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: EdgeInsets.only(top: 32),
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(),
      ),
    ),
  );

  Widget _buildResults(BuildContext context, AppPalette palette, String query) {
    switch (_source) {
      case _SearchSource.all:
        // One merged list across product sources; each card already shows its
        // own brand/source, so provenance stays clear.
        return Column(
          children: [
            _resultsHeader(context, palette),
            Expanded(
              child: BlocBuilder<ProductsBloc, ProductsState>(
                bloc: _productsBloc,
                builder: (context, ps) {
                  return BlocBuilder<FoodBloc, FoodState>(
                    bloc: _foodBloc,
                    builder: (context, fs) {
                      // Wait for BOTH sources (OFF and the Supabase backend)
                      // before rendering the merged list — showing whichever
                      // lands first would make results pop in and shift when
                      // the second source arrives. A failed source counts as
                      // answered so one outage doesn't block the other's
                      // results, but it is tracked separately from a genuine
                      // zero-result answer so the two never look the same.
                      if (_productsPending(ps, query) ||
                          _foodPending(fs, query)) {
                        return _pendingSpinner;
                      }
                      // A provider timeout or rate limit doesn't fail the
                      // bloc: the use case falls back to local matches and
                      // flags the gap on the loaded state instead.
                      final productsFailed =
                          ps is ProductsFailedState ||
                          (ps is ProductsLoadedState && ps.remoteSourceFailed);
                      final foodFailed =
                          fs is FoodFailedState ||
                          (fs is FoodLoadedState && fs.remoteSourceFailed);
                      final VoidCallback retryFailed =
                          productsFailed && foodFailed
                          ? _onAllSourcesRefreshButtonPressed
                          : (productsFailed
                                ? _onProductsRefreshButtonPressed
                                : _onFoodRefreshButtonPressed);
                      final products = ps is ProductsLoadedState
                          ? ps.products
                          : const <MealEntity>[];
                      final foods = fs is FoodLoadedState
                          ? fs.food
                          : const <MealEntity>[];
                      final merged = mergeAndRankMeals(products, foods, query);
                      final imperial = ps is ProductsLoadedState
                          ? ps.usesImperialUnits
                          : (fs is FoodLoadedState
                                ? fs.usesImperialUnits
                                : false);
                      if (merged.isEmpty) {
                        if (ps is ProductsInitial && fs is FoodInitial) {
                          return const DefaultsResultsWidget();
                        }
                        if (productsFailed && foodFailed) {
                          // Scrollable for the same reason as the partial
                          // branch below: on a landscape phone the space
                          // left in this Expanded is shorter than the error,
                          // which would overflow and push Retry off screen.
                          return SingleChildScrollView(
                            child: ErrorDialog(
                              errorText: S.of(context).errorFetchingProductData,
                              onRefreshPressed:
                                  _onAllSourcesRefreshButtonPressed,
                              retryIdentifier: 'search-all-retry',
                            ),
                          );
                        }
                        // Exactly one source failed: the other genuinely has
                        // zero matches, so this is not a hard error, but it
                        // is not a confirmed "no results" from both sources
                        // either — say so instead of only offering the
                        // scan/create actions a real zero-result state gets.
                        if (productsFailed || foodFailed) {
                          // SingleChildScrollView, not a plain Column: this
                          // sits directly inside the Expanded above, and
                          // NoResultsWidget alone already relies on its own
                          // internal scroll view to stay overflow-safe on a
                          // short viewport (see the landscape overflow this
                          // screen hit in #165). Stacking a second widget on
                          // top of it without that same protection would
                          // reintroduce that overflow.
                          return SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PartialResultsNotice(onRetry: retryFailed),
                                NoResultsWidget(
                                  onScanBarcode: _onBarcodeIconPressed,
                                  onCreateCustomFood: () =>
                                      _onCustomAddButtonPressed(imperial),
                                ),
                              ],
                            ),
                          );
                        }
                        return NoResultsWidget(
                          onScanBarcode: _onBarcodeIconPressed,
                          onCreateCustomFood: () =>
                              _onCustomAddButtonPressed(imperial),
                        );
                      }
                      return Column(
                        children: [
                          // Both down with local matches left: say nothing
                          // online answered, not that one source is missing.
                          if (productsFailed || foodFailed)
                            PartialResultsNotice(
                              onRetry: retryFailed,
                              allSourcesDown: productsFailed && foodFailed,
                            ),
                          Expanded(
                            child: Semantics(
                              identifier: 'add-meal-all-list',
                              container: true,
                              // Basic foods, then products one row per
                              // name (the search-duplicates canvas, C).
                              child: ResultSections(
                                day: _day,
                                addMealType: _mealType,
                                usesImperialUnits: imperial,
                                merged: merged,
                                basicOrder: foods,
                                query: query,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      case _SearchSource.products:
        return Column(
          children: [
            _resultsHeader(context, palette),
            BlocBuilder<ProductsBloc, ProductsState>(
              bloc: _productsBloc,
              builder: (context, state) {
                if (state is ProductsInitial) {
                  return _productsPending(state, query)
                      ? _pendingSpinner
                      : const DefaultsResultsWidget();
                } else if (state is ProductsLoadingState) {
                  return _pendingSpinner;
                } else if (state is ProductsLoadedState) {
                  // Offline the tab said no foods matched, with no Retry:
                  // the search never ran. It says so, as All does.
                  final failed = state.remoteSourceFailed
                      ? PartialResultsNotice(
                          onRetry: _onProductsRefreshButtonPressed,
                        )
                      : null;
                  if (state.products.isEmpty) {
                    final noResults = NoResultsWidget(
                      onScanBarcode: _onBarcodeIconPressed,
                      onCreateCustomFood: () =>
                          _onCustomAddButtonPressed(state.usesImperialUnits),
                    );
                    return Flexible(
                      child: _productsPending(state, query)
                          ? _pendingSpinner
                          : failed == null
                          ? noResults
                          : SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [failed, noResults],
                              ),
                            ),
                    );
                  }
                  return Flexible(
                    child: Column(
                      children: [
                        ?failed,
                        Expanded(
                          child: Semantics(
                            identifier: 'add-meal-products-list',
                            container: true,
                            // One row per product name, as in All.
                            child: ResultSections(
                              day: _day,
                              addMealType: _mealType,
                              usesImperialUnits: state.usesImperialUnits,
                              merged: state.products,
                              query: query,
                              productsHeading: false,
                              footer: state.remoteSourceEmpty
                                  ? const NoResultsWidget()
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                } else if (state is ProductsFailedState) {
                  return ErrorDialog(
                    errorText: S.of(context).errorFetchingProductData,
                    onRefreshPressed: _onProductsRefreshButtonPressed,
                  );
                }
                return const SizedBox();
              },
            ),
          ],
        );
      case _SearchSource.food:
        return Column(
          children: [
            _resultsHeader(context, palette),
            BlocBuilder<FoodBloc, FoodState>(
              bloc: _foodBloc,
              builder: (context, state) {
                if (state is FoodInitial) {
                  return _foodPending(state, query)
                      ? _pendingSpinner
                      : const DefaultsResultsWidget();
                } else if (state is FoodLoadingState) {
                  return _pendingSpinner;
                } else if (state is FoodLoadedState) {
                  if (state.food.isEmpty) {
                    return Flexible(
                      child: _foodPending(state, query)
                          ? _pendingSpinner
                          : NoResultsWidget(
                              onScanBarcode: _onBarcodeIconPressed,
                              onCreateCustomFood: () =>
                                  _onCustomAddButtonPressed(
                                    state.usesImperialUnits,
                                  ),
                            ),
                    );
                  }
                  return Flexible(
                    child: Semantics(
                      identifier: 'add-meal-food-list',
                      container: true,
                      child: ListView.builder(
                        itemCount:
                            state.food.length +
                            (state.remoteSourceEmpty ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == state.food.length) {
                            return const NoResultsWidget();
                          }
                          return MealItemCard(
                            day: _day,
                            mealEntity: state.food[index],
                            addMealType: _mealType,
                            usesImperialUnits: state.usesImperialUnits,
                          );
                        },
                      ),
                    ),
                  );
                } else if (state is FoodFailedState) {
                  return ErrorDialog(
                    errorText: S.of(context).errorFetchingProductData,
                    onRefreshPressed: _onFoodRefreshButtonPressed,
                  );
                }
                return const SizedBox();
              },
            ),
          ],
        );
      case _SearchSource.favourites:
        return _buildFavouriteResults(context, query);
      case _SearchSource.recent:
        // a chip over the unfiltered recents
        final recents = BlocBuilder<RecentMealBloc, RecentMealState>(
          bloc: _recentMealBloc,
          builder: (context, state) {
            if (state is RecentMealInitial) {
              _recentMealBloc.add(const LoadRecentMealEvent(searchString: ""));
              return const SizedBox();
            } else if (state is RecentMealLoadingState) {
              return const Padding(
                padding: EdgeInsets.only(top: 32),
                child: CircularProgressIndicator(),
              );
            } else if (state is RecentMealLoadedState) {
              // before anything is typed, the
              // history at the amounts last logged, then the favourites
              if (state.recentMeals.isNotEmpty && query.trim().isEmpty) {
                return SearchSections(
                  day: _day,
                  addMealType: _mealType,
                  usesImperialUnits: state.usesImperialUnits,
                  history: state.recentMeals,
                  entries: state.forkIntakes,
                  favourites: _favouriteMealBloc,
                );
              }
              if (state.recentMeals.isNotEmpty) {
                return Semantics(
                  identifier: 'add-meal-recent-list',
                  container: true,
                  child: ListView.builder(
                    itemCount: state.recentMeals.length,
                    itemBuilder: (context, index) {
                      return MealItemCard(
                        day: _day,
                        mealEntity: state.recentMeals[index],
                        addMealType: _mealType,
                        usesImperialUnits: state.usesImperialUnits,
                        forkLastLogged: index < state.forkIntakes.length
                            ? state.forkIntakes[index]
                            : null,
                      );
                    },
                  ),
                );
              }
              if (query.trim().isEmpty) {
                return EmptyHint(
                  icon: Icons.history_rounded,
                  title: S.of(context).noMealsRecentlyAddedLabel,
                );
              }
              return NoResultsWidget(
                onScanBarcode: _onBarcodeIconPressed,
                onCreateCustomFood: () =>
                    _onCustomAddButtonPressed(state.usesImperialUnits),
                // All skips queries below minQueryLength, so only offer it
                // once the query is long enough to actually search.
                onSearchAll:
                    _stickOnRecent && query.trim().length >= minQueryLength
                    ? _onSearchAllPressed
                    : null,
              );
            } else if (state is RecentMealFailedState) {
              return ErrorDialog(
                errorText: S.of(context).noMealsRecentlyAddedLabel,
                onRefreshPressed: _onRecentMealsRefreshButtonPressed,
              );
            }
            return const SizedBox();
          },
        );
        return query.trim().isNotEmpty
            ? recents
            : FitsLeftSwitch(
                day: _day,
                addMealType: _mealType,
                recents: recents,
              );
    }
  }

  Widget _buildFavouriteResults(BuildContext context, String query) {
    return BlocBuilder<FavouriteMealBloc, FavouriteMealState>(
      bloc: _favouriteMealBloc,
      builder: (context, state) {
        if (state is FavouriteMealInitial) {
          _favouriteMealBloc.add(LoadFavouriteMealEvent(searchString: query));
          return const SizedBox();
        } else if (state is FavouriteMealLoadingState) {
          return const Padding(
            padding: EdgeInsets.only(top: 32),
            child: CircularProgressIndicator(),
          );
        } else if (state is FavouriteMealLoadedState) {
          if (state.favourites.isNotEmpty) {
            return Semantics(
              identifier: 'add-meal-favourites-list',
              container: true,
              child: ListView.builder(
                itemCount: state.favourites.length,
                itemBuilder: (context, index) => MealItemCard(
                  day: _day,
                  mealEntity: state.favourites[index],
                  addMealType: _mealType,
                  usesImperialUnits: state.usesImperialUnits,
                ),
              ),
            );
          }
          if (query.trim().isEmpty) {
            return EmptyHint(
              icon: Icons.star_outline_rounded,
              title: S.of(context).favouritesEmptyTitle,
              subtitle: S.of(context).favouritesEmptySubtitle,
            );
          }
          return NoResultsWidget(
            onScanBarcode: _onBarcodeIconPressed,
            onCreateCustomFood: () =>
                _onCustomAddButtonPressed(state.usesImperialUnits),
          );
        } else if (state is FavouriteMealFailedState) {
          return ErrorDialog(
            errorText: S.of(context).errorLoadingFavourites,
            onRefreshPressed: _onFavouritesRefreshButtonPressed,
            retryIdentifier: 'add-meal-favourites-retry',
          );
        }
        return const SizedBox();
      },
    );
  }

  void _onBarcodeIconPressed() {
    Navigator.of(context).pushNamed(
      NavigationOptions.scannerRoute,
      arguments: ScannerScreenArguments(_day, _mealType.getIntakeType()),
    );
  }

  void _onBulkAddPressed(bool usesImperialUnits) {
    Navigator.of(context).pushNamed(
      NavigationOptions.bulkAddRoute,
      arguments: BulkAddScreenArguments(
        _mealType.getIntakeType(),
        _day,
        usesImperialUnits,
      ),
    );
  }

  Widget _aiAddFab() => FutureBuilder<bool>(
    future: _aiAdd,
    builder: (context, ai) => ai.data != true
        ? const SizedBox.shrink()
        : BlocBuilder<AddMealBloc, AddMealState>(
            bloc: _addMealBloc,
            builder: (context, state) => state is AddMealLoadedState
                ? AiAddFab(
                    onPressed: () => _onBulkAddPressed(state.usesImperialUnits),
                  )
                : const SizedBox.shrink(),
          ),
  );

  void _onQuickAddPressed() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) =>
          QuickAddBottomSheet(intakeType: _mealType.getIntakeType(), day: _day),
    );
  }

  void _onCustomAddButtonPressed(bool usesImperialUnits) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(S.of(context).createCustomDialogTitle),
          content: Text(S.of(context).createCustomDialogContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(), // close dialog
              child: Text(S.of(context).dialogCancelLabel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                _openEditMealScreen(usesImperialUnits);
              },
              child: Text(S.of(context).buttonYesLabel),
            ),
          ],
        );
      },
    );
  }

  void _openEditMealScreen(bool usesImperialUnits) {
    Navigator.of(context).pushNamed(
      NavigationOptions.editMealRoute,
      arguments: EditMealScreenArguments(
        _day,
        MealEntity.empty(),
        _mealType.getIntakeType(),
        usesImperialUnits,
      ),
    );
  }
}

enum _SearchSource { recent, favourites, all, products, food }
