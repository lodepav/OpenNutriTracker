import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/meal_value_unit_text.dart';
import 'package:opennutritracker/core/presentation/widgets/image_full_screen.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/demo/unsplash_attribution.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/favourite_toggle_button.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_bottom_sheet.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_nutriments_table.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_info_button.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/off_disclaimer.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S45 remembered-amounts
import 'package:opennutritracker/fork/amounts/remembered_amounts.dart';
// [/fork]
// [fork] S125 food-page
import 'package:opennutritracker/fork/meal_detail/food_page.dart';
// [/fork]

class MealDetailScreen extends StatefulWidget {
  const MealDetailScreen({super.key});

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {

  static const String _initialQuantityMetric = '100';
  static const String _initialQuantityImperial = '1';

  final log = Logger('ItemDetailScreen');

  late MealDetailBloc _mealDetailBloc;
  final _scrollController = ScrollController();

  late MealEntity meal;
  late DateTime _day;
  late IntakeTypeEntity intakeTypeEntity;

  final quantityTextController = TextEditingController();
  late bool _usesImperialUnits;
  bool _showMicronutrients = false;
  // #1126: preloaded from `ConfigEntity.defaultToRawFoodUnits`. False keeps
  // the pre-existing "serving wins whenever one exists" default; true
  // steers `_applyInitialSelection` to grams/oz (or ml/fl oz) instead.
  bool _defaultToRawFoodUnits = false;

  String _initialUnit = "";
  String _initialQuantity = "";

  // [fork] S45 remembered-amounts: the amount this food was last logged at
  RememberedAmount? _forkRemembered;

  Future<void> _forkLoadRemembered() async {
    final remembered = await RememberedAmounts.current.of(meal);
    if (remembered == null || !mounted || _userChangedSelection) return;
    _forkRemembered = remembered;
    _initialUnit = "";
    _initialQuantity = "";
    _applyInitialSelection();
  }

  /// The remembered amount when this food can take its unit: a serving
  /// only once the record has a scalable one (a thin search hit gets it
  /// with hydration, which re-picks).
  RememberedAmount? get _forkUsableRemembered {
    final remembered = _forkRemembered;
    if (remembered == null) return null;
    if (remembered.unit == UnitDropdownItem.serving.toString() &&
        meal.scalableServingQuantity == null) {
      return null;
    }
    final quantity = double.tryParse(remembered.quantity.replaceAll(',', '.'));
    return quantity == null || quantity <= 0 ? null : remembered;
  }
  // [/fork]

  // Set on the first didChangeDependencies pass, which is the only one that
  // reads the route arguments and requests hydration (see there).
  bool _argumentsRead = false;
  bool _userChangedSelection = false;

  /// True while `_applyInitialSelection` is running. The bottom sheet's
  /// text-change listener echoes every write to `quantityTextController`
  /// back through [onQuantityOrUnitChanged], including the ones this
  /// method makes itself, and its `widget.selectedUnit` is the last
  /// rendered value — not the unit we're currently switching to. Without
  /// this guard the echo would (a) dispatch a stale-unit UpdateKcalEvent
  /// on top of the explicit one below, (b) flip [_userChangedSelection]
  /// to true although nobody touched anything, and (c) call
  /// `_scrollToCalorieText` on open — enough scroll to collapse the app
  /// bar and push the product image out of view.
  bool _applyingInitialSelection = false;

  // Scroll distance from expandedHeight down to the collapsed SliverAppBar
  // (toolbar + bottom bar): 268-124 with the DailyKcalOverview bottom bar,
  // 200-56 without it — always 144 either way, so no need to key it off
  // dayKcalGoal.
  // [fork] S125 food-page: the bar no longer collapses; the title shows
  // once the header's name has scrolled under it
  static const double _collapseScrollThreshold = 64.0;
  // [/fork]
  bool _showAppBarTitle = false;

  @override
  void initState() {
    _mealDetailBloc = locator<MealDetailBloc>();
    _loadDetailPreferences();
    _scrollController.addListener(_handleScroll);
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    quantityTextController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final show = _scrollController.offset >= _collapseScrollThreshold - 4;
    if (show != _showAppBarTitle) {
      setState(() => _showAppBarTitle = show);
    }
  }

  Future<void> _loadDetailPreferences() async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!mounted) return;
    final wasSelectionInitialised = _initialUnit != "";
    setState(() {
      _showMicronutrients = config.showMicronutrients;
      _defaultToRawFoodUnits = config.defaultToRawFoodUnits;
    });
    // #1126: the config read is async, so `_applyInitialSelection` may have
    // already run with the fallback default of "prefer serving". Re-pick
    // if the user hasn't touched selection yet, so opting into raw units
    // still switches the very first render's dropdown to grams/oz.
    if (wasSelectionInitialised &&
        _defaultToRawFoodUnits &&
        !_userChangedSelection) {
      _initialUnit = "";
      _initialQuantity = "";
      _applyInitialSelection();
    }
  }

  @override
  void didChangeDependencies() {
    // `ModalRoute.of` re-runs this whenever a route is pushed over or popped
    // off this screen — the unit dropdown's own menu included — so the
    // arguments are read once. Re-reading `meal` on every pass handed the
    // thin search hit back to the sheet the moment the dropdown opened,
    // after hydration had already swapped in the full record: the serving
    // entry the user then tapped was no longer in the rebuilt list and the
    // button went blank (#1216).
    if (!_argumentsRead) {
      final args =
          ModalRoute.of(context)?.settings.arguments
              as MealDetailScreenArguments;
      meal = args.mealEntity;
      _day = args.day;
      intakeTypeEntity = args.intakeTypeEntity;
      _usesImperialUnits = args.usesImperialUnits;
      _argumentsRead = true;

      // Thin OFF search results get hydrated to the full product record
      // (serving fields + micronutrients) once, in the background; the
      // listener in build() swaps the displayed meal in when it arrives.
      _mealDetailBloc.add(HydrateMealEvent(meal));
      // [fork] S45 remembered-amounts
      _forkLoadRemembered();
      // [/fork]
    }

    _mealDetailBloc.add(LoadDailyTotalsEvent(_day));

    _applyInitialSelection();

    super.didChangeDependencies();
  }

  /// Pick the default unit and quantity from the meal's shape. Serving-based
  /// meals default to 1 serving; otherwise to 100 g/ml (or 1 oz/fl oz in
  /// imperial). Guarded so it only runs while the user hasn't chosen yet, and
  /// re-run after hydration reveals serving values.
  void _applyInitialSelection() {
    // #1126: when the user has opted into raw units in Settings, the
    // scalable-serving branch is skipped so grams/oz (or ml/fl oz)
    // becomes the very first render's default. `hasScalableServing`
    // stays the classifier — a record with no parseable serving still
    // falls through to weight/volume the same way it always did.
    final preferServing =
        meal.scalableServingQuantity != null && !_defaultToRawFoodUnits;
    // [fork] S45 remembered-amounts
    final remembered = _forkUsableRemembered;
    // [/fork]

    _applyingInitialSelection = true;
    try {
      // [fork] S45 remembered-amounts
      if (_initialUnit == "" && remembered != null) {
        _initialUnit = remembered.unit;
        _mealDetailBloc.add(
          UpdateKcalEvent(meal: meal, selectedUnit: _initialUnit),
        );
      }
      if (_initialQuantity == "" && remembered != null) {
        _initialQuantity = remembered.quantity;
        quantityTextController.text = remembered.quantity;
        _mealDetailBloc.add(
          UpdateKcalEvent(
            meal: meal,
            totalQuantity: quantityTextController.text,
            selectedUnit: _initialUnit,
          ),
        );
      }
      // [/fork]
      if (_initialUnit == "") {
        // `scalableServingQuantity`, not `hasServingValues` (#629): the latter
        // is true for a record whose serving is unparseable text, and nothing
        // can scale those — they defaulted to "1 serving" and logged 1 g.
        if (preferServing) {
          _initialUnit = UnitDropdownItem.serving.toString();
        } else if (meal.isLiquid) {
          _initialUnit = _usesImperialUnits
              ? UnitDropdownItem.flOz.toString()
              : UnitDropdownItem.ml.toString();
        } else if (meal.isSolid) {
          _initialUnit = _usesImperialUnits
              ? UnitDropdownItem.oz.toString()
              : UnitDropdownItem.g.toString();
        } else {
          _initialUnit = UnitDropdownItem.gml.toString();
        }
        _mealDetailBloc.add(
          UpdateKcalEvent(meal: meal, selectedUnit: _initialUnit),
        );
      }

      if (_initialQuantity == "") {
        // Gated the same way as the unit above, so a bare "1" can never end
        // up beside a weight unit.
        if (preferServing) {
          _initialQuantity = "1";
          quantityTextController.text = "1";
        } else if (_usesImperialUnits) {
          _initialQuantity = _initialQuantityImperial;
          quantityTextController.text = _initialQuantityImperial;
        } else {
          _initialQuantity = _initialQuantityMetric;
          quantityTextController.text = _initialQuantityMetric;
        }
        // The unit rides along, not just the quantity: on the re-pick after
        // hydration the bottom sheet is already listening to the controller,
        // and the write above echoes back through onQuantityOrUnitChanged
        // with the unit the sheet last rendered (#1216). That echo is also
        // what `_applyingInitialSelection` makes `onQuantityOrUnitChanged`
        // ignore, so neither the stale unit nor the phantom
        // `_userChangedSelection` flip nor the scroll reaches the screen.
        _mealDetailBloc.add(
          UpdateKcalEvent(
            meal: meal,
            totalQuantity: quantityTextController.text,
            selectedUnit: _initialUnit,
          ),
        );
      }
    } finally {
      _applyingInitialSelection = false;
    }
  }

  /// Apply the hydrated full product to the screen. If the user hasn't touched
  /// the quantity/unit yet, re-pick the defaults (so serving becomes the
  /// default now that serving data exists); otherwise just recompute totals
  /// against the fuller nutriments while keeping the user's selection.
  void _onMealHydrated(MealEntity full) {
    setState(() => meal = full);
    if (_userChangedSelection) {
      _mealDetailBloc.add(
        UpdateKcalEvent(
          meal: meal,
          totalQuantity: quantityTextController.text,
          selectedUnit: _mealDetailBloc.state.selectedUnit,
        ),
      );
    } else {
      _initialUnit = "";
      _initialQuantity = "";
      _applyInitialSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MealDetailBloc, MealDetailState>(
      bloc: _mealDetailBloc,
      listenWhen: (prev, curr) =>
          curr.hydratedMeal != null && curr.hydratedMeal != prev.hydratedMeal,
      listener: (context, state) => _onMealHydrated(state.hydratedMeal!),
      child: SafeArea(
        child: Scaffold(
          backgroundColor:
              (Theme.of(context).brightness == Brightness.dark ? AppPalette.dark : AppPalette.light).canvas,
          body: BlocBuilder<MealDetailBloc, MealDetailState>(
            bloc: _mealDetailBloc,
            builder: (context, state) {
              if (state is MealDetailInitial) {
                return _getLoadedContent(
                  context,
                  state.totalQuantityConverted,
                  state.totalKcal,
                  state.totalCarbs,
                  state.totalFat,
                  state.totalProtein,
                  state.selectedUnit,
                  state.dayKcalConsumed,
                  state.dayKcalGoal,
                  state.isHydrating,
                );
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
        bottomSheet: BlocSelector<MealDetailBloc, MealDetailState, String>(
          bloc: _mealDetailBloc,
          selector: (state) => state.selectedUnit,
          builder: (context, selectedUnit) {
            return MealDetailBottomSheet(
              product: meal,
              day: _day,
              intakeTypeEntity: intakeTypeEntity,
              selectedUnit: selectedUnit,
              usesImperialUnits: _usesImperialUnits,
              mealDetailBloc: _mealDetailBloc,
              quantityTextController: quantityTextController,
              onQuantityOrUnitChanged: onQuantityOrUnitChanged,
            );
          },
          ),
        ),
      ),
    );
  }

  Widget _getLoadedContent(
    BuildContext context,
    String totalQuantity,
    double totalKcal,
    double totalCarbs,
    double totalFat,
    double totalProtein,
    String selectedUnit,
    double dayKcalConsumed,
    double dayKcalGoal,
    bool isHydrating,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // [fork] S125 food-page: a plain bar, then the food's header, the
        // ring of where the energy comes from and the day after adding it
        SliverAppBar(
          pinned: true,
          backgroundColor: palette.canvas,
          surfaceTintColor: Colors.transparent,
          title: AnimatedOpacity(
            opacity: _showAppBarTitle ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Text(
              meal.name ?? '',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          actions: [
            FavouriteToggleButton(
              meal: meal,
              semanticsIdentifier: 'meal-detail-favourite',
            ),
            Semantics(
              identifier: 'meal-detail-edit',
              child: IconButton(
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    NavigationOptions.editMealRoute,
                    arguments: EditMealScreenArguments(
                      _day,
                      meal,
                      intakeTypeEntity,
                      _usesImperialUnits,
                    ),
                  );
                },
                icon: const Icon(Icons.edit_rounded),
                tooltip: S.of(context).editMealLabel,
              ),
            ),
          ],
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FoodPageHeader(
                    meal: meal,
                    onPhotoTap: () => Navigator.of(context).pushNamed(
                      NavigationOptions.imageFullScreenRoute,
                      arguments: ImageFullScreenArguments(
                        meal.mainImageUrl ?? meal.thumbnailImageUrl ?? "",
                      ),
                    ),
                  ),
                  UnsplashCreditLine(imageUrl: meal.mainImageUrl),
                  const SizedBox(height: Dimens.spacing12),
                  MergeSemantics(
                    child: MealValueUnitText(
                      value: double.parse(totalQuantity),
                      meal: meal,
                      displayUnit:
                          selectedUnit == UnitDropdownItem.serving.toString()
                              ? meal.servingUnit
                              : selectedUnit,
                      usesImperialUnits: _usesImperialUnits,
                      textStyle: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textMuted),
                      prefix: 'In ',
                    ),
                  ),
                  const SizedBox(height: Dimens.spacing4),
                  FoodMacroRing(
                    kcal: totalKcal,
                    carbs: totalCarbs,
                    fat: totalFat,
                    protein: totalProtein,
                  ),
                  const SizedBox(height: Dimens.spacing8),
                  TodayAfterAdding(
                    day: _day,
                    kcal: totalKcal,
                    carbs: totalCarbs,
                    fat: totalFat,
                    protein: totalProtein,
                  ),
                  const SizedBox(height: Dimens.spacing16),
        // [/fork]
                  if (isHydrating)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16.0),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  MealDetailNutrimentsTable(
                    product: meal,
                    usesImperialUnits: _usesImperialUnits,
                    servingQuantity: meal.servingQuantity,
                    servingUnit: meal.servingUnit,
                    showMicronutrients: _showMicronutrients,
                  ),
                  const SizedBox(height: 32.0),
                  MealInfoButton(
                    url: meal.url,
                    source: meal.source,
                    backendSource: meal.backendSource,
                  ),
                  meal.source == MealSourceEntity.off
                      ? const Column(
                          children: [SizedBox(height: 32), OffDisclaimer()],
                        )
                      : const SizedBox(),
                  const SizedBox(height: 200.0), // height added to scroll
                ],
              ),
            ),
          ]),
        ),
      ],
    );
  }

  void onQuantityOrUnitChanged(String? quantityString, String? unit) {
    if (quantityString == null || unit == null) {
      return;
    }
    if (_applyingInitialSelection) {
      // Echo from `_applyInitialSelection`'s own controller.text write;
      // that method dispatches an authoritative UpdateKcalEvent itself.
      // Treating this as a user edit would collapse the app bar on open
      // via `_scrollToCalorieText` and record a phantom selection.
      return;
    }
    _userChangedSelection = true;
    _mealDetailBloc.add(
      UpdateKcalEvent(
        meal: meal,
        totalQuantity: quantityString,
        selectedUnit: unit,
      ),
    );
    _scrollToCalorieText();
  }

  void _scrollToCalorieText() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        // [fork] S125 food-page: back to the top, where the ring and the
        // day after adding now are
        0,
        // [/fork]
        duration: const Duration(seconds: 1),
        curve: Curves.easeInOut,
      );
    }
  }
}

class MealDetailScreenArguments {
  final MealEntity mealEntity;
  final IntakeTypeEntity intakeTypeEntity;
  final DateTime day;
  final bool usesImperialUnits;

  MealDetailScreenArguments(
    this.mealEntity,
    this.intakeTypeEntity,
    this.day,
    this.usesImperialUnits,
  );
}

