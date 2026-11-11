// Fork-owned copy of lib/features/add_meal/presentation/screens/bulk_add_screen.dart (D23); upstream's later changes to it
// are ported by hand: fork/tools/upstream-copies.sh.
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/presentation/widgets/badged_title.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/run_ai_endpoint_probe_usecase.dart';
import 'package:opennutritracker/core/utils/ai_model_catalogue.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/fork/bulk/ai_add.dart';
import 'package:opennutritracker/features/add_meal/util/meal_photo_encoder.dart';
import 'package:opennutritracker/features/add_meal/util/portion_label.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/add_meal/presentation/voice/voice_input_button.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/own_server_wait_indicator.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/quick_add_bottom_sheet.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/features/settings/settings_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
// break a row into a dish's ingredients (D12)
import 'package:opennutritracker/fork/dish/dish_breakdown_controller.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';
import 'package:opennutritracker/fork/dish/dish_group.dart';
import 'package:opennutritracker/fork/dish/dish_recipe.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';
import 'package:opennutritracker/fork/bulk/discard_guard.dart';
import 'package:opennutritracker/fork/bulk/amount_question.dart';
import 'package:opennutritracker/fork/bulk/meal_scale.dart';
import 'package:opennutritracker/fork/bulk/scale_rows.dart';
import 'package:opennutritracker/fork/bulk/review_totals.dart';
import 'package:opennutritracker/fork/bulk/review_units.dart';
import 'package:opennutritracker/fork/bulk/shown_unit.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/display/meal_macros_line.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/fork/meal_detail/food_page.dart'
    show TodayAfterAdding, DayTotals, loadDayTotals;
import 'package:opennutritracker/fork/amounts/amount_picker.dart';
import 'package:opennutritracker/fork/amounts/amount_units.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';
import 'package:opennutritracker/fork/meal_detail/unit_change.dart';
// remember which entries one save wrote (D14)
import 'package:opennutritracker/fork/leftovers/meal_groups.dart';
import 'package:opennutritracker/fork/bulk/name_dish_dialog.dart';
import 'package:opennutritracker/fork/leftovers/meal_photo_cache.dart';
// a recipe from typed lines or a recipe link
import 'package:http/http.dart' as http;
import 'package:opennutritracker/fork/recipe/recipe_link.dart';
import 'package:opennutritracker/fork/screens/add_meal/amount_question_view.dart';
// a meal like one the user corrected before
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory_store.dart';
import 'package:opennutritracker/fork/screens/add_meal/history_offer_view.dart';
// the photo's amounts sized the way the user usually corrects them (D46)
import 'package:opennutritracker/fork/bulk/usual_sizes.dart';
import 'package:opennutritracker/fork/screens/add_meal/usual_sizes_view.dart';
// an unusual amount, the fat a meal was cooked in, and the note's chips
// (D47-D49)
import 'package:opennutritracker/fork/bulk/cooking_fat.dart';
import 'package:opennutritracker/fork/bulk/put_row.dart';
import 'package:opennutritracker/fork/bulk/usual_serving.dart';
import 'package:opennutritracker/fork/dish/break_down_dish_usecase.dart'
    show preferTableRow;
import 'package:opennutritracker/fork/screens/add_meal/cooking_fat_view.dart';
import 'package:opennutritracker/fork/screens/add_meal/note_chips_view.dart';
import 'package:opennutritracker/fork/screens/add_meal/usual_serving_view.dart';

part 'bulk_add_body.dart';
part 'bulk_add_row.dart';
part 'bulk_add_dish.dart';

class BulkAddScreenArguments {
  final IntakeTypeEntity intakeTypeEntity;
  final DateTime day;
  final bool usesImperialUnits;
  // opened by the add screen's camera, for a photo
  final bool startWithPhoto;
  // shared from another app (S167): a photo copied into the cache, or text
  final String? sharedPhotoPath;
  final String? sharedText;

  const BulkAddScreenArguments(
    this.intakeTypeEntity,
    this.day,
    this.usesImperialUnits, {
    this.startWithPhoto = false,
    this.sharedPhotoPath,
    this.sharedText,
  });
}

/// Type a whole meal, confirm what it matched, log it in one go.
///
/// **The confirmation step is not optional.** It exists so nothing reaches
/// the diary that the user has not looked at. Tier 0 resolves everything
/// against the food database and invents no numbers, so today that is a
/// correctness concern; once a model tier lands it also becomes the human
/// review that AI Act Art. 50(4) and both providers' usage policies expect.
/// See #599 before removing it.
class BulkAddScreen extends StatefulWidget {
  const BulkAddScreen({super.key});

  @override
  State<BulkAddScreen> createState() => _BulkAddScreenState();
}

/// Today's totals for the review's meal card (D36); tests swap it.
Future<DayTotals> Function(DateTime day) forkDayTotals = loadDayTotals;

/// The photo meal memory the review reads and Log writes; tests swap it.
PhotoMealMemoryStore Function() forkPhotoMealMemory = PhotoMealMemoryStore.new;

/// The food table's oil a cooking fat chip adds, at [grams] (D48); null
/// when nothing matched. Tests swap it.
Future<ResolvedMealItem?> Function(double grams) forkCookingFatFood =
    _cookingFatFood;

Future<ResolvedMealItem?> _cookingFatFood(double grams) async {
  final found = await locator<ResolveParsedMealsUseCase>().resolve([
    ParsedMealItem(query: cookingFatQuery, quantity: grams, unit: 'g'),
  ], fromPhoto: true);
  if (found.isEmpty || !found.first.isResolved) return null;
  // the table's oil, not a bottle nobody named
  return preferTableRow(found.first);
}

/// A row as the photo's read gave it: its food, unit, grams or millilitres
/// and amount text, and whether a size could change it then.
typedef _PhotoRow = ({
  String key,
  String unit,
  double? base,
  String text,
  bool sizable,
});

class _BulkAddScreenState extends State<BulkAddScreen> {
  final _log = Logger('BulkAddScreen');
  final _bloc = locator<BulkAddBloc>();
  final _textController = TextEditingController();
  final _voice = GlobalKey<VoiceInputButtonState>();
  // the photo this batch was read from, kept with the meal
  MealPhoto? _forkMealPhoto;
  // taken or picked, waiting for send; kept through the read, so a failed
  // read can be sent again without a new photo
  MealPhoto? _stagedPhoto;
  bool _readingStaged = false;
  // the note the last photo went with, out of the box so a second send
  // doesn't replace the photo's rows with its note's (UX review U1)
  String? _photoNote;
  late final StreamSubscription<BulkAddState> _stagedRead = _bloc.stream.listen(
    _onStagedReadState,
  );

  /// The meal's Size on a photo's review: taken anew with each read.
  var _mealScale = MealScale();
  late final StreamSubscription<BulkAddState> _scaleFollow;

  /// The rows a size just set, for the card to say the meal's energy at.
  List<BulkAddRow>? _mealSizeSaid;

  /// The one amount a photo's review asks about, chosen once per read;
  /// null when none was, or once it ended.
  AmountQuestion? _amountQuestion;
  bool _amountAsked = false;

  /// An answer to say once built: the amount, and the rows it set.
  ({String amount, List<BulkAddRow> rows})? _amountSaid;

  /// A meal like this photo's that the user corrected before, found once
  /// per read as its rows arrive; null when none was.
  PhotoMealMatch? _history;
  bool _historyAsked = false;

  /// While its amounts are used: the bases and size they replaced.
  MealScaleSnapshot? _historyUndo;

  /// Counts reads, so a memory found for one is not offered on the next.
  var _readSerial = 0;

  /// The dish the photo's read arrived as, kept with the meal on Log.
  String? _arrivalDish;

  /// The rows of a photo's read as they arrived, kept so the photo's own
  /// amounts can come back and be kept with the meal on Log.
  final _photoRows = LinkedHashMap<ResolvedMealItem, _PhotoRow>.identity();

  /// The usual sizes applied to this read, the rows they changed, and the
  /// foods and whole-meal size the line names; null when none were.
  UsualSizes? _usual;
  final _usualRows = Set<ResolvedMealItem>.identity();
  List<({String name, double factor})> _usualFoods = const [];

  /// The bases before the usual sizes, which "Use the photo's amounts"
  /// puts back; and, while the photo's amounts are used, the usual ones.
  MealScaleSnapshot? _photoBases;
  MealScaleSnapshot? _usualBases;

  /// Whether the usual sizes are what the rows' bases are now.
  bool get _usualInForce =>
      _usual != null && _usualBases == null && _historyUndo == null;

  /// Each row's grams or millilitres when it first appeared, and whether
  /// the user has changed any amount from it (a row they set that moved).
  final _firstAmounts = LinkedHashMap<ResolvedMealItem, double?>.identity();
  bool _amountChanged = false;

  /// The question about the fat the meal was cooked or dressed with,
  /// decided once per read as its rows arrive; null when not asked.
  CookingFatAsk? _fatAsk;
  bool _fatAsked = false;

  /// Answered None: the question goes.
  bool _fatClosed = false;

  /// The fat row a chip added, while it is on the review.
  ResolvedMealItem? _fatItem;

  /// The chip tapped while the table's oil is looked up.
  int? _fatPending;

  /// The note's field, focused by a chip that wants a number after it.
  final _noteFocus = FocusNode();

  // titled like the buttons that open it while AI meal assistance is on
  final _aiAdd = aiAddEnabled();
  // the page the text was read from, if any
  LinkedRecipe? _forkLinkedRecipe;
  String? _forkLink;

  Future<void> _readRecipeLink(Uri link) async {
    final messenger = ScaffoldMessenger.of(context)
      ..showSnackBar(const SnackBar(content: Text(DishStrings.readingLink)));
    LinkedRecipe? recipe;
    String? failure;
    try {
      recipe = await RecipeLinkReader(locator<http.Client>()).read(link);
      if (recipe == null) failure = DishStrings.linkHasNoRecipe;
    } catch (e) {
      _log.info('Recipe link not read: $e');
      failure = DishStrings.linkFailed;
    }
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (recipe == null) {
      messenger.showSnackBar(SnackBar(content: Text(failure!)));
      return;
    }
    _textController.text = recipe.ingredients.join('\n');
    _forkLinkedRecipe = recipe;
    _forkLink = link.host;
    _onParsePressed();
  }

  Future<void> _saveAllAsRecipe(BulkAddLoadedState state) async {
    final linked = _forkLinkedRecipe;
    final recipe = recipeFromRows(
      state.rows,
      name: linked?.name ?? '',
      description: linked == null
          ? DishStrings.typedRecipeDescription
          : DishStrings.linkedRecipeDescription(_forkLink!),
      servings: linked?.servings ?? 1,
    );
    if (recipe == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(DishStrings.nothingToSave)));
      return;
    }
    await openDishRecipe(context, recipe);
  }

  // runs breakdowns and marks the rows (D12)
  late final _dishBreakdown =
      DishBreakdownController(
        _bloc,
        photo: () => _forkMealPhoto,
        onRowsMoved: _onRowsMoved,
      )..addListener(() {
        if (mounted) setState(() {});
      });

  /// A field keeps its place in the list while its row moves, so typing on
  /// would go to another food; the refusal marks and portion bases are by
  /// index.
  void _onRowsMoved() {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _quantityErrors.clear();
      _portionBase.clear();
    });
  }

  Future<void> _breakDown(BulkAddRow row) async {
    final outcome = await _dishBreakdown.breakDown(row);
    if (!mounted) return;
    final message = switch (outcome) {
      DishBreakdownOutcome.replaced => null,
      DishBreakdownOutcome.empty => DishStrings.breakDownEmpty,
      DishBreakdownOutcome.noModel => DishStrings.breakDownNoModel,
      DishBreakdownOutcome.failed => DishStrings.breakDownFailed,
    };
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _saveDishRecipe(Object group) async {
    final state = _bloc.state;
    final recipe = state is BulkAddLoadedState
        ? recipeFromDishGroup(state.rows, group)
        : null;
    if (recipe == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(DishStrings.nothingToSave)));
      return;
    }
    await openDishRecipe(context, recipe);
  }

  /// One controller per row, keyed by row index and rebuilt whenever a new
  /// parse produces a different set of rows.
  final _amountControllers = <int, TextEditingController>{};

  /// A dish's portion field, its folded state, and the dishes the user
  /// chose to log as separate rows (canvas "AI dish A", D24); keyed by its
  /// group.
  final _portionControllers = <Object, TextEditingController>{};
  final _foldedDishes = <Object>{};
  final _separateDishes = <Object>{};

  /// The rows' amounts when the portion being typed was first changed, so
  /// that each keystroke scales from them and not from the last rounding.
  final _portionBase = <Object, Map<int, double>>{};

  void _toggleDishFolded(Object group) =>
      setState(() => _foldedDishes.remove(group) || _foldedDishes.add(group));

  void _logDishSeparately(Object group, {bool separately = true}) => setState(
    () =>
        separately ? _separateDishes.add(group) : _separateDishes.remove(group),
  );

  /// Done typing a portion: the field shows the rows' sum again.
  void _endPortionEdit(Object group) =>
      setState(() => _portionBase.remove(group));

  /// What the last submit attempt refused, keyed by index into
  /// `BulkAddLoadedState.rows`.
  ///
  /// Held here rather than derived in `build` because a row is only wrong
  /// once it has been asked for: `BulkAddRow.amountText` is text so that a
  /// field mid-edit ("", "1,") is not marked while it is being typed. The
  /// map is what makes every bad row visible at once — the check refuses the
  /// whole batch, so reporting one at a time asks the user to resubmit for
  /// each. #1013.
  final _quantityErrors = <int, BulkAddQuantityError>{};

  /// Whether the photo action is offered at all. Held rather than resolved
  /// inside `build` — a future rebuilt on every frame would re-read the
  /// keystore continuously for an answer that changes only when the user
  /// visits settings. It is re-read when they come back from there, and only
  /// then; see [_openSettings].
  /// **Both halves are load-bearing, and neither implies the other.**
  ///
  /// Found on a Pixel 6: with a server the user runs configured, the feature
  /// *is* enabled, so the camera icon appeared — and did nothing, because
  /// nothing had established that the model on the other end can see. A
  /// button that is present and inert is worse than one that is absent.
  ///
  /// The destination alone is not the answer either. It resolves for an
  /// install that has never opened settings: nothing stored reads as
  /// Anthropic (#688), and an absent model id falls back to the list's first
  /// entry — so gating on it alone offered the camera to every user with no
  /// key at all, and to every user who had deliberately switched the feature
  /// off.
  late Future<bool> _photoAvailable = _resolvePhotoAvailable();

  Future<bool> _resolvePhotoAvailable() async {
    if (!await locator<AiCredentialStorage>().isEnabled()) return false;
    return await _photoDestination != null;
  }

  /// Whether to offer the model at all, for someone who has never set it up.
  ///
  /// Asked of *every* provider rather than the active one. `readSummary`'s
  /// `configured` speaks only for whichever provider is selected, so a user
  /// holding a key for one of the other three would be invited to set up
  /// something they set up last week — an app that does not know its own
  /// configuration.
  ///
  /// Deliberately **not** gated on `isEnabled`. A user who paused the feature
  /// has not failed to discover it, and this line exists for discovery. The
  /// rule is one sentence: it shows only for someone who has configured
  /// nothing. #844.
  ///
  /// And not to someone who hid the AI features (#1518): they have found
  /// it, and asked not to be offered it.
  late Future<bool> _modelUnknown = _resolveModelUnknown();

  Future<bool> _resolveModelUnknown() async {
    final storage = locator<AiCredentialStorage>();
    if (await storage.isHidden()) return false;
    return !await storage.hasAnyUsableProvider();
  }

  /// Where a photo would actually go, **and the name the sheet gives it**.
  ///
  /// The sheet below is the last moment the user can decline, so it has to
  /// name the real destination — it named Anthropic unconditionally until a
  /// Pixel 6 showed it saying so while OpenRouter was selected.
  ///
  /// The name is one field rather than two because there is one question:
  /// *who is at the far end?* For the three providers reached at a
  /// compiled-in endpoint that is a company, taken from the curated model's
  /// [AiModel.servedBy]; for a server the user runs there is no company to
  /// name and the only honest answer is **the address they configured**,
  /// which is what #736 settled and what #781 makes this record able to
  /// express. Two of the four sentences carry the name inside themselves
  /// rather than as a placeholder, which does not make the field less true
  /// for them.
  ///
  /// Deliberately not `readSelection()`: that carries the API key, and
  /// nothing in the widget layer has any business holding it.
  /// Null when the stored provider is a name this build does not know. The
  /// sheet cannot name a destination it cannot identify, so it does not open
  /// — the same outcome as a provider with no key, and the point of #753.
  late Future<({AiProvider provider, String name})?> _photoDestination =
      _resolvePhotoDestination();

  Future<({AiProvider provider, String name})?>
  _resolvePhotoDestination() async {
    final storage = locator<AiCredentialStorage>();
    final provider = await storage.activeProvider();
    if (provider == null) return null;
    if (provider == AiProvider.ownServer) {
      return await _ownServerDestination(storage);
    }
    final model = AiModelCatalogue.resolve(
      provider,
      await storage.readModel(provider: provider),
    );
    if (model == null) return null;
    return (provider: provider, name: model.servedBy);
  }

  /// A server the user runs, **only once a photo probe has passed against the
  /// pair currently configured** — and null otherwise.
  ///
  /// The stored pass is the whole gate (#735). There is no curated list here
  /// and no behavioural screen the project can run against a machine it has
  /// never seen, so the app's own setup-time test is what stands in for one;
  /// and unlike the text path there is nothing underneath a photo to fall
  /// back to, so offering the camera to a model that cannot see is offering a
  /// dead end. [AiCredentialStorage.writeEndpoint] and
  /// [AiCredentialStorage.writeModel] each discard the record when their
  /// value changes, so a pass read here can only describe the address and
  /// model in use right now.
  ///
  /// A missing host is a second, independent null: the sheet's whole job for
  /// this provider is to say the address out loud, and it cannot do that from
  /// text that is not one.
  Future<({AiProvider provider, String name})?> _ownServerDestination(
    AiCredentialStorage storage,
  ) async {
    const provider = AiProvider.ownServer;
    final probe = await storage.readProbe(provider: provider);
    if (probe.photo != AiCapability.passed) return null;
    final endpoint = await storage.readEndpoint(provider: provider);
    if (endpoint == null) return null;
    final host = AiCredentialStorage.displayHost(endpoint);
    if (host == null) return null;
    return (provider: provider, name: host);
  }

  /// Whether a read from this screen waits on a server the user runs.
  ///
  /// Decides which loading state is drawn. The bloc cannot say: it hands the
  /// line to `ReadMealTextUseCase`, which reads the selection itself and
  /// never reports which provider it chose — and the loading state is
  /// emitted *before* that read, deliberately, so a screen that does nothing
  /// for two seconds does not read as broken. Asked of the keystore here
  /// instead, in the same way and for the same reasons as the answers above:
  /// once, and again after Settings, which is the only place it can change.
  ///
  /// `enabled` and not only the provider, because a paused feature takes the
  /// parser path and answers at once — a two-minute wait drawn for that
  /// would describe a request never sent. Hosted providers keep the bare
  /// spinner; they answer in seconds and the sentence about a model loading
  /// would be noise there (#1148).
  late Future<bool> _waitsOnOwnServer = _resolveWaitsOnOwnServer();

  Future<bool> _resolveWaitsOnOwnServer() async {
    final summary = await locator<AiCredentialStorage>().readSummary();
    return summary.enabled && summary.provider == AiProvider.ownServer;
  }

  late BulkAddScreenArguments _args;
  bool _submitting = false;

  /// Opens settings, and re-reads the three answers above once it pops.
  ///
  /// Every route out of this screen that can change them comes through here,
  /// which is what makes "resolved once" safe. Without it the first run of
  /// the feature ends with the feature missing: a new user follows the hint
  /// below, configures a provider, comes back — and the camera is still
  /// hidden, because the screen is still holding the answers it computed
  /// before they left. #992.
  ///
  /// Re-read on the pop rather than on every rebuild: the keystore is the
  /// only thing that can have changed, and only a visit to settings can have
  /// changed it.
  Future<void> _openSettings({SettingsScreenArguments? arguments}) async {
    await Navigator.of(
      context,
    ).pushNamed(NavigationOptions.settingsRoute, arguments: arguments);
    if (!mounted) return;
    _resolveAiAnswers();
    await _resolveAgainWhenProbeLands();
  }

  void _resolveAiAnswers() {
    setState(() {
      // Destination first: the availability answer awaits this field.
      _photoDestination = _resolvePhotoDestination();
      _photoAvailable = _resolvePhotoAvailable();
      _modelUnknown = _resolveModelUnknown();
      _waitsOnOwnServer = _resolveWaitsOnOwnServer();
    });
  }

  /// A second trigger, for the one answer that is not ready when the user
  /// comes back. #1089.
  ///
  /// Saving an own-server address starts a capability probe **without
  /// awaiting it**, and it takes long enough that returning promptly reads
  /// the verdict as `unknown`. `_ownServerDestination` requires
  /// `photo == passed`, so the camera stays hidden — and the route pop was
  /// the only thing that would have re-read it, and has already happened.
  ///
  /// The waiting itself is deliberate and stays: the camera is offered only
  /// once a photograph has actually been read (#735). What was missing is
  /// that nothing told the screen the verdict had arrived.
  ///
  /// Own-server only, because it is the only provider whose availability
  /// depends on a probe. `current` is null between one probe finishing and
  /// its replacement registering — two keystore reads wide, documented on
  /// the runner — and this returns rather than polling: the answer it would
  /// have waited for is already stored, so the re-resolve above read it.
  Future<void> _resolveAgainWhenProbeLands() async {
    const provider = AiProvider.ownServer;
    if (await locator<AiCredentialStorage>().activeProvider() != provider) {
      return;
    }

    final running = locator<AiEndpointProbeRunner>().current(provider);
    if (running == null) return;

    await running;
    if (!mounted) return;
    _resolveAiAnswers();
  }

  @override
  void initState() {
    super.initState();
    _scaleFollow = _bloc.stream.listen(_onScaleState);
  }

  /// A read starting takes a new scale; a photo's rows arriving are its
  /// base, and every later state is followed: what the user changed is
  /// pinned, and rows a breakdown wrote or a put-back food take the size.
  void _onScaleState(BulkAddState state) {
    if (state is! BulkAddLoadedState) {
      _mealScale = MealScale(note: _photoNote);
      _amountQuestion = null;
      _amountAsked = false;
      _readSerial++;
      _history = null;
      _historyAsked = false;
      _historyUndo = null;
      _arrivalDish = null;
      _photoRows.clear();
      _usual = null;
      _usualRows.clear();
      _usualFoods = const [];
      _photoBases = null;
      _usualBases = null;
      _firstAmounts.clear();
      _amountChanged = false;
      _fatAsk = null;
      _fatAsked = false;
      _fatClosed = false;
      _fatItem = null;
      _fatPending = null;
      return;
    }
    if (state.source != BulkAddReadSource.photo) return;
    _followAmountQuestion(state);
    _askCookingFat(state);
    _askHistory(state);
    final amounts = _mealScale.follow(state.rows);
    _followAmountChanges(state.rows);
    if (amounts.isNotEmpty) _bloc.add(ScaleRowsEvent(amounts));
    if (mounted) setState(() {});
  }

  /// A photo's rows as they first arrive are matched against the meals the
  /// user corrected before; the match is offered once it is found.
  void _askHistory(BulkAddLoadedState state) {
    if (_historyAsked || state.rows.isEmpty) return;
    _historyAsked = true;
    _arrivalDish = readDishName(state.rows);
    if (state.modelFailure != null) return;
    for (final row in state.rows) {
      final meal = row.meal;
      if (meal == null) continue;
      _photoRows[row.resolved] = (
        key: foodKeyOf(meal),
        unit: row.effectiveUnit,
        base: baseAmountOf(row),
        text: row.amountText,
        sizable: isScalableRow(row, note: _photoNote),
      );
    }
    unawaited(_findHistory(_readSerial, state.rows, _photoNote));
  }

  Future<void> _findHistory(
    int read,
    List<BulkAddRow> rows,
    String? note,
  ) async {
    final List<PhotoMealRecord> records;
    try {
      records = await forkPhotoMealMemory().records();
    } catch (e, stackTrace) {
      _log.warning('Reading the photo meal memory failed', e, stackTrace);
      return;
    }
    if (!mounted || read != _readSerial) return;
    final now = DateTime.now();
    final match = photoMealMatchFor(rows, records, note: note, now: now);
    if (match != null) setState(() => _history = match);
    _applyUsual(usualSizesOf(records, now: now));
  }

  /// The photo's amounts sized the way the user usually corrects them: each
  /// row the Size may change, still at the photo's amount, takes its usual
  /// amount as its base, at 1×, which reads "Your usual". Not once a size
  /// was chosen or earlier amounts used: the user has sized this meal.
  void _applyUsual(UsualSizes usual) {
    final state = _bloc.state;
    if (usual.isEmpty || state is! BulkAddLoadedState) return;
    if (state.source != BulkAddReadSource.photo) return;
    if (_mealScale.factor != 1 || _historyUndo != null) return;
    final amounts = usualAmounts(
      state.rows,
      usual,
      note: _photoNote,
      canTake: (row) =>
          _mealScale.canScale(row) &&
          _photoRows[row.resolved]?.text == row.amountText,
    );
    if (amounts.isEmpty) return;
    final foods = <String, ({String name, double factor})>{};
    for (final row in state.rows) {
      if (!amounts.containsKey(row.resolved)) continue;
      final key = foodKeyOf(row.meal!);
      if (usual.foods[key] case final factor?) {
        foods.putIfAbsent(key, () => (name: _rowTitle(row), factor: factor));
      }
    }
    final before = _mealScale.snapshot();
    final scaled = _mealScale.rebase(state.rows, amounts);
    setState(() {
      _usual = usual;
      _usualRows
        ..clear()
        ..addAll(amounts.keys);
      _usualFoods = [...foods.values];
      _photoBases = before;
      _usualBases = null;
    });
    // not said: nothing was tapped, and the line is read with the card
    if (scaled.isNotEmpty) _bloc.add(ScaleRowsEvent(scaled));
  }

  /// Whether the usual sizes' line is shown: some row they sized is still
  /// one the Size changes, and no earlier amounts are used.
  bool _usualShown(List<BulkAddRow> rows) =>
      _usual != null &&
      _historyUndo == null &&
      rows.any(
        (row) => _usualRows.contains(row.resolved) && _mealScale.canScale(row),
      );

  /// "Use the photo's amounts": the bases before the usual sizes back, the
  /// rows the user set left as set.
  void _usePhotoAmounts() {
    final state = _bloc.state;
    final photo = _photoBases;
    if (state is! BulkAddLoadedState || photo == null || !_usualInForce) {
      return;
    }
    final usual = _mealScale.snapshot();
    final amounts = _mealScale.restore(state.rows, photo);
    setState(() => _usualBases = usual);
    _sendScaled(state.rows, amounts);
  }

  /// Back to the usual sizes, and the size chosen with them.
  void _useUsualSizes() {
    final state = _bloc.state;
    final usual = _usualBases;
    if (state is! BulkAddLoadedState || usual == null) return;
    final amounts = _mealScale.restore(state.rows, usual);
    setState(() => _usualBases = null);
    _sendScaled(state.rows, amounts);
  }

  /// The photo's own grams or millilitres for [row], kept with the meal on
  /// Log: none for a row the read did not give, nor one whose match or
  /// unit changed, nor one no size could change (its amount was not the
  /// photo's estimate).
  double? _photoAmountOf(BulkAddRow row) {
    final photo = _photoRows[row.resolved];
    final meal = row.meal;
    if (photo == null || !photo.sizable || meal == null) return null;
    if (foodKeyOf(meal) != photo.key || row.effectiveUnit != photo.unit) {
      return null;
    }
    return photo.base;
  }

  /// The whole-meal size at Log against the photo's amounts; none when no
  /// row of the read could be sized.
  double? _loggedSize() {
    if (!_photoRows.values.any((row) => row.sizable)) return null;
    return _mealScale.factor * (_usualInForce ? _usual!.meal : 1);
  }

  /// Notes each new row's amount, and whether a row the user set has moved
  /// from it: what makes a logged meal "corrected".
  void _followAmountChanges(List<BulkAddRow> rows) {
    for (final row in rows) {
      final first = _firstAmounts.putIfAbsent(
        row.resolved,
        () => baseAmountOf(row),
      );
      if (_amountChanged || !_mealScale.isPinned(row)) continue;
      if (_moved(first, baseAmountOf(row))) _amountChanged = true;
    }
  }

  static bool _moved(double? first, double? now) {
    if (first == null || now == null) return false;
    return (now - first).abs() > 0.02 * (now > first ? now : first);
  }

  /// Whether the user changed the photo's amounts: a size other than "As
  /// shown", an amount they set that differs, or their earlier amounts used.
  bool _photoCorrected(List<BulkAddRow> rows) =>
      _historyUndo != null ||
      _amountChanged ||
      (_mealScale.factor != 1 && rows.any(_mealScale.canScale)) ||
      rows.any(
        (row) =>
            _mealScale.isPinned(row) &&
            _moved(_firstAmounts[row.resolved], baseAmountOf(row)),
      );

  /// Whether the earlier meal is offered on [rows]: while its amounts are
  /// used, or while enough of its foods are there and one of them is a row
  /// the Size may change.
  bool _historyShown(List<BulkAddRow> rows) {
    final match = _history;
    if (match == null) return false;
    if (_historyUndo != null) return true;
    return photoMealMatchStands(rows, match) &&
        photoMealAmounts(
          rows,
          match.record,
          canTake: _mealScale.canScale,
        ).isNotEmpty;
  }

  /// [rows] as "Use your amounts" would leave them: the earlier meal's
  /// amounts on the rows that would take them, the photo's on the other
  /// rows the Size changes, and the amounts the user set kept.
  List<BulkAddRow> _withHistory(List<BulkAddRow> rows) {
    final match = _history;
    if (match == null) return rows;
    final amounts = _mealScale.rebaseTargets(
      rows,
      _historyTaken(
        rows,
        photoMealAmounts(rows, match.record, canTake: _mealScale.canScale),
      ),
    );
    return [
      for (final row in rows)
        switch (amounts[row.resolved]) {
          final text? => row.copyWith(amountText: text),
          null => row,
        },
    ];
  }

  /// "Use your amounts": each shared row the Size may change takes the
  /// earlier meal's amount as its new base, unpinned, at "As shown", and
  /// the other rows it may change go back to the photo's amounts; the
  /// question on a shared row goes, and the meal's energy is said.
  void _useHistory() {
    final state = _bloc.state;
    final match = _history;
    if (state is! BulkAddLoadedState || match == null) return;
    final taken = photoMealAmounts(
      state.rows,
      match.record,
      canTake: _mealScale.canScale,
    );
    if (taken.isEmpty) return;
    final before = _mealScale.snapshot();
    final amounts = _mealScale.rebase(
      state.rows,
      _historyTaken(state.rows, taken),
    );
    setState(() {
      _historyUndo = before;
      if (_amountQuestion case final question?
          when state.rows.any(
            (row) => question.isFor(row) && taken.containsKey(row.resolved),
          )) {
        _amountQuestion = null;
      }
    });
    _sendScaled(state.rows, amounts);
  }

  /// [taken] and, while the usual sizes are in force, the photo's amount
  /// for each other row they sized: the earlier amounts are the user's own,
  /// and every other food goes back to the photo's, as without them.
  Map<ResolvedMealItem, String> _historyTaken(
    List<BulkAddRow> rows,
    Map<ResolvedMealItem, String> taken,
  ) {
    if (!_usualInForce) return taken;
    final all = LinkedHashMap<ResolvedMealItem, String>.identity()
      ..addAll(taken);
    for (final row in rows) {
      if (all.containsKey(row.resolved) ||
          !_usualRows.contains(row.resolved) ||
          !_mealScale.canScale(row)) {
        continue;
      }
      if (_photoRows[row.resolved]?.text case final text?) {
        all[row.resolved] = text;
      }
    }
    return all;
  }

  /// Undo: the photo's bases and the size before, back.
  void _undoHistory() {
    final state = _bloc.state;
    final before = _historyUndo;
    if (state is! BulkAddLoadedState || before == null) return;
    final amounts = _mealScale.restore(state.rows, before);
    setState(() => _historyUndo = null);
    _sendScaled(state.rows, amounts);
  }

  /// Sets [amounts] on [rows] in one go, and says the meal's energy once
  /// the card is built.
  void _sendScaled(
    List<BulkAddRow> rows,
    Map<ResolvedMealItem, String> amounts,
  ) {
    if (amounts.isNotEmpty) _bloc.add(ScaleRowsEvent(amounts));
    _mealSizeSaid = [
      for (final row in rows)
        switch (amounts[row.resolved]) {
          final text? => row.copyWith(amountText: text),
          null => row,
        },
    ];
  }

  /// Every amount the user has not set at [factor] times the photo's, and
  /// the meal's new energy said to a screen reader.
  void _setMealSize(double factor) {
    final state = _bloc.state;
    if (state is! BulkAddLoadedState) return;
    setState(() => _mealScale.factor = factor);
    final amounts = _mealScale.retarget(state.rows);
    if (amounts.isNotEmpty) _bloc.add(ScaleRowsEvent(amounts));
    // said once the card is built: the energy is formatted per profile
    _mealSizeSaid = [
      for (final row in state.rows)
        switch (amounts[row.resolved]) {
          final text? => row.copyWith(amountText: text),
          null => row,
        },
    ];
  }

  /// "Meal now 150 kcal" to a screen reader, after a size was chosen.
  void _sayMealSize(BuildContext context) {
    final rows = _mealSizeSaid;
    if (rows == null) return;
    _mealSizeSaid = null;
    final message = DishStrings.mealNow(
      EnergyDisplay.formatSumWithUnit(context, loggedKcals(rows)),
    );
    final view = View.of(context);
    final direction = Directionality.of(context);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => SemanticsService.sendAnnouncement(view, message, direction),
    );
  }

  /// The user set row [index]'s amount: the meal's Size leaves it, and a
  /// question on it is answered another way, so it goes for good.
  void _pinRow(int index) {
    final state = _bloc.state;
    if (state is BulkAddLoadedState && index < state.rows.length) {
      final row = state.rows[index];
      _mealScale.pin(row);
      if (_amountQuestion?.isFor(row) ?? false) {
        setState(() => _amountQuestion = null);
      }
    }
  }

  /// The question asked of a photo's rows as they first arrive (before
  /// any size), and ended once its row is broken down or matched anew.
  void _followAmountQuestion(BulkAddLoadedState state) {
    if (!_amountAsked) {
      if (state.rows.isEmpty) return;
      _amountAsked = true;
      _amountQuestion = state.modelFailure != null
          ? null
          : amountQuestionFor(
              state.rows,
              note: _photoNote,
              imperial: state.usesImperialUnits,
              pinned: _mealScale.isPinned,
            );
      return;
    }
    if (_amountQuestion case final question?
        when !question.standsIn(state.rows)) {
      _amountQuestion = null;
    }
  }

  /// Chip [choice] of the question on row [index] tapped: the row takes its
  /// amount as a typed one, in the unit it is shown in, and the meal's Size
  /// leaves it.
  void _answerAmount(int index, int choice) {
    final state = _bloc.state;
    final question = _amountQuestion;
    if (state is! BulkAddLoadedState || question == null) return;
    if (index >= state.rows.length || !question.isFor(state.rows[index])) {
      return;
    }
    final row = state.rows[index];
    final chip = question.answer(row, choice);
    if (chip == null) return;
    _setRowTo(state, index, chip);
  }

  /// Row [index] of [state] set to [chip] as the user's amount, in the unit
  /// it is shown in: the meal's Size leaves it, and the amount and the
  /// meal's energy are said.
  void _setRowTo(BulkAddLoadedState state, int index, AmountChoice chip) {
    final row = state.rows[index];
    _mealScale.pin(row);
    if (_quantityErrors.containsKey(index)) _clearQuantityError(index);
    setState(() {});
    // said once the row is built: the energy is formatted per profile
    _amountSaid = (
      amount: chip.spoken,
      rows: [
        for (final (i, r) in state.rows.indexed)
          i == index ? r.copyWith(unit: chip.unit, amountText: chip.text) : r,
      ],
    );
    if (chip.unit == row.effectiveUnit) {
      _bloc.add(ChangeRowAmountEvent(index, chip.text));
    } else if (chip.unit == shownEditUnit(row, state.usesImperialUnits)) {
      _bloc.add(SetRowInShownUnitEvent(index, chip.unit, chip.text));
    } else {
      _bloc
        ..add(ChangeRowUnitEvent(index, chip.unit))
        ..add(ChangeRowAmountEvent(index, chip.text));
    }
  }

  /// The usual serving offered on row [row] of a photo's review (D47): not
  /// once the user set it, nor on the row the amount question is on.
  AmountChoice? _usualServingOn(BulkAddLoadedState state, BulkAddRow row) {
    if (state.source != BulkAddReadSource.photo) return null;
    if (_mealScale.isPinned(row)) return null;
    if (_amountQuestion?.isFor(row) ?? false) return null;
    return usualServingFor(
      row,
      note: _photoNote,
      imperial: state.usesImperialUnits,
    );
  }

  /// The usual serving taken on row [index], as an amount the user set.
  void _takeUsualServing(int index, AmountChoice serving) {
    final state = _bloc.state;
    if (state is! BulkAddLoadedState || index >= state.rows.length) return;
    _setRowTo(state, index, serving);
  }

  /// The fat question for a photo's rows as they first arrive (D48).
  void _askCookingFat(BulkAddLoadedState state) {
    if (_fatAsked || state.rows.isEmpty) return;
    _fatAsked = true;
    if (state.modelFailure != null) return;
    _fatAsk = cookingFatAskFor(state.rows, note: _photoNote);
  }

  /// The fat row the chips added, as it is on the review; null when none.
  BulkAddRow? _fatRow(List<BulkAddRow> rows) {
    final item = _fatItem;
    if (item == null) return null;
    for (final row in rows) {
      if (identical(row.resolved, item)) return row;
    }
    return null;
  }

  /// The chip of the fat question that shows as chosen: the one at the
  /// added row's amount, or the one tapped while its oil is looked up.
  /// None while the row is in another unit than the chips' grams.
  int? _fatChosen(List<BulkAddRow> rows) => switch (_fatRow(rows)) {
    final row? when row.effectiveUnit == row.resolved.parsed.unit =>
      cookingFatChipOf(row.amountText),
    final _? => null,
    null => _fatPending,
  };

  /// None (-1) takes the added row off and ends the question; an amount
  /// adds the table's oil at it, pinned as the user's (the Size leaves
  /// it), or sets the row it added before to it.
  Future<void> _chooseCookingFat(int choice) async {
    final state = _bloc.state;
    if (state is! BulkAddLoadedState) return;
    final current = _fatRow(state.rows);
    if (choice < 0) {
      setState(() {
        _fatClosed = true;
        _fatPending = null;
      });
      if (current != null) _bloc.add(PutRowEvent(current.resolved, null));
      return;
    }
    final grams = cookingFatGrams[choice];
    if (current != null) {
      // the user's amount, not a correction of the photo's
      _firstAmounts.remove(current.resolved);
      _bloc.add(
        PutRowEvent(
          current.resolved,
          // in the grams the row was added in, whatever unit it is in now
          current.copyWith(
            amountText: cookingFatText(grams),
            unit: current.resolved.parsed.unit,
          ),
        ),
      );
      return;
    }
    final looking = _fatPending != null;
    setState(() => _fatPending = choice);
    if (looking) return;
    final read = _readSerial;
    ResolvedMealItem? found;
    try {
      found = await forkCookingFatFood(grams);
    } catch (e, stackTrace) {
      _log.warning('Looking up the cooking fat failed', e, stackTrace);
    }
    if (!mounted || read != _readSerial) return;
    final pending = _fatPending;
    setState(() => _fatPending = null);
    if (pending == null || _fatClosed) return;
    if (found == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(DishStrings.fatNotFound)));
      return;
    }
    final row = _cookingFatRow(found, cookingFatGrams[pending]);
    _mealScale.pin(row);
    setState(() => _fatItem = row.resolved);
    _bloc.add(PutRowEvent(row.resolved, row));
  }

  /// An ordinary row of [found] at [grams], as the user's amount: in grams,
  /// or grams-or-millilitres for a food that has no grams.
  BulkAddRow _cookingFatRow(ResolvedMealItem found, double grams) {
    final g = UnitDropdownItem.g.toString();
    final probe = BulkAddRow(
      resolved: found,
      selectedIndex: found.selectedIndex,
      amountText: '',
      unit: g,
    );
    final unit = probe.allowedUnits.contains(g)
        ? g
        : UnitDropdownItem.gml.toString();
    final item = ResolvedMealItem(
      parsed: ParsedMealItem(
        query: found.parsed.query,
        quantity: grams,
        unit: unit,
      ),
      candidates: found.candidates,
      selectedIndex: found.selectedIndex,
      // the user asked for it: no "uncertain" on it
      confidence: 1,
    );
    return BulkAddRow(
      resolved: item,
      selectedIndex: item.selectedIndex,
      amountText: cookingFatText(grams),
      unit: unit,
      amountEditedByUser: true,
      fromPhoto: true,
    );
  }

  /// "150 grams. Meal now 450 kcal" to a screen reader, after an answer.
  void _sayAmountAnswer(BuildContext context) {
    final said = _amountSaid;
    if (said == null) return;
    _amountSaid = null;
    final message = DishStrings.amountSaid(
      said.amount,
      EnergyDisplay.formatSumWithUnit(context, loggedKcals(said.rows)),
    );
    final view = View.of(context);
    final direction = Directionality.of(context);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => SemanticsService.sendAnnouncement(view, message, direction),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _args =
        ModalRoute.of(context)!.settings.arguments as BulkAddScreenArguments;
    // straight to the photo sheet, once
    if (_args.startWithPhoto && !_forkPhotoStarted) {
      _forkPhotoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (await _photoAvailable && mounted) {
          await _onPhotoPressed();
        } else if (mounted) {
          // the Photo log shortcut is there whether or not photos can be read
          _showNoPhotoModel();
        }
      });
    }
    // what another app shared, once, waiting for send like anything
    // typed or taken: text in the box, a photo after the camera's disclosure
    if (_forkSharedTaken) return;
    _forkSharedTaken = true;
    if (_args.sharedText case final text?) _textController.text = text;
    if (_args.sharedPhotoPath case final path?) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (await _photoAvailable && mounted) {
          await _onPhotoPressed(sharedPath: path);
          return;
        }
        _discardShared(path);
        if (mounted) _showNoPhotoModel();
      });
    }
  }

  /// No set-up offer to someone who hid the AI features (#1518): only why
  /// the photo is not read.
  Future<void> _showNoPhotoModel() async {
    final hidden = await locator<AiCredentialStorage>().isHidden();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hidden
              ? 'Reading a photo needs the AI features, which are hidden '
                    'in Settings.'
              : 'Reading a photo needs a model that sees images: set one up '
                    'in Settings › AI meal logging.',
        ),
      ),
    );
  }

  /// A shared photo not read is not kept.
  void _discardShared(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  bool _forkPhotoStarted = false;
  bool _forkSharedTaken = false;

  @override
  void dispose() {
    // registerFactory hands out a new instance per navigation, so this
    // screen owns it and has to close it.
    // before the bloc it listens to
    _dishBreakdown.dispose();
    _stagedRead.cancel();
    _scaleFollow.cancel();
    _bloc.close();
    _textController.dispose();
    _noteFocus.dispose();
    for (final controller in _amountControllers.values) {
      controller.dispose();
    }
    for (final controller in _portionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // which meal the items go to, as the add sheet named it
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<bool>(
              future: _aiAdd,
              builder: (context, ai) => Text(
                ai.data == true ? aiAddLabel : S.of(context).bulkAddTitle,
              ),
            ),
            Text(
              _mealName(context),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          // every ready row as one recipe
          BlocBuilder<BulkAddBloc, BulkAddState>(
            bloc: _bloc,
            builder: (context, state) =>
                state is BulkAddLoadedState && state.rows.isNotEmpty
                ? IconButton(
                    key: const Key('fork-save-all-as-recipe'),
                    onPressed: () => _saveAllAsRecipe(state),
                    icon: const Icon(Icons.menu_book_outlined),
                    tooltip: DishStrings.saveAllAsRecipe,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<BulkAddBloc, BulkAddState>(
          bloc: _bloc,
          builder: (context, state) => LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                // Back asks before found foods are lost
                DiscardGuard(
                  pending:
                      !_submitting &&
                      state is BulkAddLoadedState &&
                      state.rows.isNotEmpty,
                ),
                // The **field** is bounded, not the block. At 2x on a 320dp
                // screen the entry block measured 388px — a four-line field
                // plus a full-height button — against about 595px of body,
                // and with the submit bar's 192 that left the rows nothing
                // and overflowed by 14px. #820.
                // Capping the whole block was tried first and is worse: the
                // Search button falls below the fold inside the scroll view,
                // so the primary action of the screen has to be scrolled to.
                // Bounding the field alone keeps the button where it is.
                // A ceiling rather than fewer `maxLines`: shrinking the field
                // at large text scales would take multi-line entry away from
                // exactly the users who need the biggest text, on a screen
                // that exists for typing several items at once.
                _buildInput(
                  context,
                  state,
                  maxFieldHeight: constraints.maxHeight * 0.3,
                ),
                const Divider(height: 1),
                Expanded(child: _buildBody(context, state)),
              ],
            ),
          ),
        ),
      ),
      // In the bar's slot, so a snackbar (a left-out food's Undo, D36)
      // shows above Log rather than over it.
      bottomNavigationBar: BlocBuilder<BulkAddBloc, BulkAddState>(
        bloc: _bloc,
        builder: (context, state) => state is BulkAddLoadedState
            ? _buildSubmitBar(context, state)
            : const SizedBox.shrink(),
      ),
    );
  }

  /// Puts the hint above [body] without letting it push anything off screen.
  ///
  /// It lives in the body rather than in the entry block above, which is
  /// fixed: adding a standing line there overflowed the column by 184px at 2x
  /// on a 320dp screen, the same defect #820 fixed and the same one #824
  /// uncovered under it. This region is the one that can give ground.
  Widget _withModelHint(BuildContext context, Widget body) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _buildModelHint(context),
      Expanded(child: body),
    ],
  );

  /// The line that says a model could read this, for a user who has never
  /// configured one.
  ///
  /// It names the API key requirement before the tap. The app ships no model,
  /// so a reader who follows this without knowing that lands in a third-party
  /// signup nothing warned them about — the qualifier is what keeps a
  /// standing offer from being a bait.
  ///
  /// It carries the same Experimental marker every other AI surface carries.
  /// This is the most-seen of them, and marking the quiet surfaces while
  /// leaving the loudest one bare would invert the emphasis.
  ///
  /// It says nothing about where nutrition values come from. A model may
  /// never produce them, and that guarantee is reassurance rather than
  /// something that changes whether this tap leads anywhere — it belongs on
  /// the agreement, which is where it is.
  Widget _buildModelHint(BuildContext context) => FutureBuilder<bool>(
    future: _modelUnknown,
    builder: (context, snapshot) {
      // Nothing until the keystore read lands, and nothing for anyone who has
      // configured a provider. A line that appeared and then vanished would
      // resize the screen under someone already typing.
      if (snapshot.data != true) return const SizedBox.shrink();
      final s = S.of(context);
      final theme = Theme.of(context);
      return Semantics(
        identifier: 'bulk-add-model-hint',
        child: Padding(
          // The screen's 16 dp edge, which the list below it has not
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: InkWell(
            // Asks for the AI dialog by name, the same way the failure
            // notices below have since #852. Plain Settings opens with the
            // AI row several category groups down, and of this screen's two
            // audiences the one reading this hint is the one that knows
            // least about where it is going — sending it the longer way
            // round was exactly backwards. #992.
            onTap: () => _openSettings(
              arguments: const SettingsScreenArguments(openAiAssist: true),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The marker as Settings shows it
                        BadgedTitle(
                          title: s.bulkAddModelHintLabel,
                          badge: s.aiAssistExperimentalLabel,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          s.bulkAddModelHintKeyLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  // Capture and gallery, the box, one send (AI add, after MacroFactor's
  // AI tab): only offered when the user has a key enabled. There is no
  // offline way to read a photo, so showing the photo buttons to everyone
  // would advertise buttons that can only ever apologise.
  Widget _buildInput(
    BuildContext context,
    BulkAddState state, {
    required double maxFieldHeight,
  }) => FutureBuilder<bool>(
    future: _photoAvailable,
    builder: (context, snapshot) {
      final photos = snapshot.data == true;
      final staged = _stagedPhoto;
      final busy = state is BulkAddLoadingState;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photos) ...[
              _buildPhotoRow(context, staged, busy: busy),
              const SizedBox(height: 12),
            ],
            // Scrolls past its ceiling rather than being clipped: what is
            // typed must stay reachable, and at ordinary text sizes four
            // lines are far below this so nothing changes.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxFieldHeight),
              child: Semantics(
                identifier: 'bulk-add-input',
                child: TextField(
                  controller: _textController,
                  focusNode: _noteFocus,
                  minLines: 2,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: staged != null
                        ? 'Describe it (optional)'
                        : S.of(context).bulkAddInputHint,
                    // what the field does with a photo (H10)
                    helperText: photos
                        ? 'With a photo, this is sent as its note'
                        : null,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                    // Dictate the meal, then match it straight away; with a
                    // photo waiting, what is said is its note, sent by hand.
                    suffixIcon: VoiceInputButton(
                      key: _voice,
                      controller: _textController,
                      onDictated: (_) {
                        if (_stagedPhoto == null) _onParsePressed();
                      },
                    ),
                  ),
                ),
              ),
            ),
            // words for the photo's note (D49)
            if (staged != null && !busy) ...[
              const SizedBox(height: 8),
              NoteChipsView(controller: _textController, focus: _noteFocus),
            ],
            const SizedBox(height: 12),
            // nothing to send on an empty box, or while a read runs
            ListenableBuilder(
              listenable: _textController,
              builder: (context, _) => Semantics(
                identifier: 'bulk-add-parse',
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : staged != null
                      ? _readStagedPhoto
                      : _textController.text.trim().isEmpty
                      ? null
                      : _onParseButtonPressed,
                  icon: Icon(
                    staged != null ? Icons.send_rounded : Icons.search,
                  ),
                  label: Text(
                    _readingStaged
                        ? 'Reading the photo…'
                        : staged != null
                        ? S.of(context).bulkAddPhotoLabel
                        : S.of(context).bulkAddParseLabel,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  /// Capture wide, the gallery beside it; a photo waiting to be sent sits
  /// first, with a way to take it back.
  Widget _buildPhotoRow(
    BuildContext context,
    MealPhoto? staged, {
    required bool busy,
  }) {
    const height = 48.0;
    final s = S.of(context);
    return Row(
      children: [
        if (staged != null) ...[
          Semantics(
            identifier: 'bulk-add-photo-staged',
            image: true,
            label: 'Photo to read',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                staged.bytes,
                width: height,
                height: height,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Semantics(
            identifier: 'bulk-add-photo-remove',
            child: IconButton(
              onPressed: busy
                  ? null
                  : () => setState(() => _stagedPhoto = null),
              icon: const Icon(Icons.close_rounded),
              tooltip: s.mealImageRemove,
            ),
          ),
        ],
        Expanded(
          child: Semantics(
            identifier: 'bulk-add-photo',
            child: FilledButton.tonalIcon(
              // muted, so "Find foods" stays the one primary action
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(height),
                backgroundColor: paletteOf(context).surfaceMuted,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: busy ? null : _onPhotoPressed,
              icon: const Icon(Icons.photo_camera_rounded),
              label: Text(
                staged != null ? s.mealImageReplace : s.mealImageTakePhoto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          identifier: 'bulk-add-gallery',
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(
              minimumSize: const Size.square(height),
              backgroundColor: paletteOf(context).surfaceMuted,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(height / 2),
              ),
            ),
            onPressed: busy
                ? null
                : () => _onPhotoPressed(from: ImageSource.gallery),
            icon: const Icon(Icons.photo_library_rounded),
            tooltip: s.mealImagePickFromGallery,
          ),
        ),
      ],
    );
  }

  void _clearQuantityError(int index) =>
      setState(() => _quantityErrors.remove(index));

  Widget _buildSubmitBar(BuildContext context, BulkAddLoadedState state) {
    final count = loggedEntries(state.rows, separate: _separateDishes);
    // What the button will log, summed as the rows show it (#1469). Not at a
    // large font: a second line on the button comes out of the rows above.
    final showTotal = MediaQuery.textScalerOf(context).scale(1) <= 1.5;
    final rowKcals = loggedKcals(state.rows);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(
          identifier: 'bulk-add-submit',
          child: FilledButton.icon(
            onPressed: count == 0 || _submitting
                ? null
                : () => _onSubmitPressed(state),
            icon: const Icon(Icons.add_rounded),
            label: Text(
              count == 0 || !showTotal
                  ? S.of(context).bulkAddSubmitLabel(count)
                  : '${S.of(context).bulkAddSubmitLabel(count)} · '
                        '${EnergyDisplay.formatSumWithUnit(context, rowKcals)}',
            ),
          ),
        ),
      ),
    );
  }

  /// Find foods pressed by hand. Dictation in progress ends first, or its
  /// pause timeout would match the text again and reset the rows the user
  /// may already be correcting.
  void _onParseButtonPressed() {
    _voice.currentState?.cancel();
    _onParsePressed();
  }

  void _onParsePressed() {
    FocusScope.of(context).unfocus();
    // a recipe link reads as its ingredient lines
    if (recipeLinkIn(_textController.text) case final link?) {
      _readRecipeLink(link);
      return;
    }
    if (_textController.text != _forkLinkedRecipe?.ingredients.join('\n')) {
      _forkLinkedRecipe = null;
    }
    _resetAmountControllers();
    _forkMealPhoto = null;
    _bloc.add(
      ParseBulkTextEvent(
        text: _textController.text,
        usesImperialUnits: _args.usesImperialUnits,
        localeCode: Localizations.localeOf(context).languageCode,
      ),
    );
  }

  /// Takes or picks a photo (or takes a shared one) and holds it until
  /// send, so the box can describe it.
  Future<void> _onPhotoPressed({
    String? sharedPath,
    ImageSource from = ImageSource.camera,
  }) async {
    FocusScope.of(context).unfocus();
    final destination = await _photoDestination;
    if (!mounted) return;
    // Refusing rather than guessing: with no identifiable destination there
    // is no honest sentence to put in the sheet, and the sheet is the last
    // moment the user can decline.
    if (destination == null) {
      if (sharedPath != null) _discardShared(sharedPath);
      return;
    }
    // say so when the photo is kept for leftovers
    final keepsPhoto = await MealPhotoCache().keepsPhotos;
    if (!mounted) return;
    final disclosure = switch (destination.provider) {
      AiProvider.anthropic => S.of(context).bulkAddPhotoDisclosureAnthropic,
      AiProvider.openrouter =>
        S.of(context).bulkAddPhotoDisclosureOpenRouter(destination.name),
      // No placeholder: a direct path has no serving vendor to name, so this
      // string is flat where OpenRouter's is parameterised.
      AiProvider.openai => S.of(context).bulkAddPhotoDisclosureOpenAI,
      // The address, and nothing beyond it. Not "no third party receives it",
      // however tempting: the app cannot tell a local runtime from a
      // self-hosted proxy forwarding to OpenAI, and #732 ruled those out of
      // scope by making no claim about them rather than by detecting them.
      // The no-copy sentence below is about this app and still holds.
      AiProvider.ownServer =>
        S.of(context).bulkAddPhotoDisclosureOwnServer(destination.name),
    };
    final shouldOpenCamera = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            // The disclosure sits here rather than in a dialog the user has
            // to dismiss: this is the moment a photograph would leave the
            // device, and it is the last moment they can decline.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '$disclosure '
                '${keepsPhoto ? keptPhotoDisclosure : S.of(sheetContext).bulkAddPhotoDisclosureCommon}\n\n'
                // The photo path has no deterministic fallback, so this is
                // the only surface besides Settings where a user opts into a
                // model. The stability note belongs on both.
                '${S.of(sheetContext).aiAssistExperimentalNote}',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
            ),
            Semantics(
              identifier: 'bulk-add-photo-camera',
              child: ListTile(
                leading: Icon(switch ((sharedPath, from)) {
                  (null, ImageSource.camera) => Icons.photo_camera_rounded,
                  (null, ImageSource.gallery) => Icons.photo_library_rounded,
                  _ => Icons.photo_rounded,
                }),
                title: Text(switch ((sharedPath, from)) {
                  (null, ImageSource.camera) =>
                    S.of(sheetContext).mealImageTakePhoto,
                  (null, ImageSource.gallery) =>
                    S.of(sheetContext).mealImagePickFromGallery,
                  _ => 'Use the shared photo',
                }),
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
            ),
          ],
        ),
      ),
    );
    if (shouldOpenCamera != true || !mounted) {
      if (sharedPath != null) _discardShared(sharedPath);
      return;
    }

    final String source;
    if (sharedPath != null) {
      source = sharedPath;
    } else {
      final XFile? picked;
      try {
        picked = await ImagePicker().pickImage(source: from);
      } catch (e, stackTrace) {
        _log.warning('Opening the meal photo camera failed', e, stackTrace);
        if (!mounted) return;
        _bloc.add(const ReadMealPhotoFailedEvent(BulkAddPhotoError.camera));
        return;
      }
      // A cancelled picker is not a failure and says nothing to the user.
      if (picked == null || !mounted) return;
      source = picked.path;
    }

    final MealPhoto? photo;
    try {
      // Discards the picker's cache copy once it has been encoded — see
      // [MealPhotoEncoder.encodeAndDiscardSource]. Without it the app leaves
      // the photo on disk, which the settings disclosure says it does not.
      photo = await MealPhotoEncoder.encodeAndDiscardSource(
        source,
        // Per destination, not per app: a server the user runs may be
        // llama.cpp, which cannot decode WebP at all (#747).
        format: MealPhotoFormat.forProvider(destination.provider),
      );
    } catch (e, stackTrace) {
      // Never logged with the path: on Android the picker's temp filename
      // can carry the original image name.
      _log.warning('Encoding a meal photo failed', e, stackTrace);
      if (!mounted) return;
      _bloc.add(const ReadMealPhotoFailedEvent(BulkAddPhotoError.unreadable));
      return;
    }
    if (!mounted) return;

    if (photo == null) {
      _bloc.add(const ReadMealPhotoFailedEvent(BulkAddPhotoError.unreadable));
      return;
    }

    setState(() => _stagedPhoto = photo);
  }

  /// Sends the photo waiting by the buttons, with the box as its note.
  /// The photo stays until rows come back; the note leaves the box.
  void _readStagedPhoto() {
    final photo = _stagedPhoto;
    if (photo == null) return;
    // A note still being dictated would land after the photo went.
    _voice.currentState?.cancel();
    FocusScope.of(context).unfocus();
    final note = _textController.text.trim();
    _photoNote = note.isEmpty ? null : note;
    _textController.clear();
    // These rows are the photo's, not a page's read before.
    _forkLinkedRecipe = null;
    _sendPhoto(photo);
  }

  /// Reads [photo] with [_photoNote], in place of the rows there. A failure
  /// keeps the photo, to send again.
  void _sendPhoto(MealPhoto photo) {
    // the subscription starts with the first read
    _stagedRead;
    setState(() {
      _stagedPhoto = photo;
      _readingStaged = true;
    });
    // A photo replaces the previous batch, so the old controllers go with it.
    _resetAmountControllers();
    _forkMealPhoto = photo;
    _bloc.add(
      ReadMealPhotoEvent(
        photo: photo,
        usesImperialUnits: _args.usesImperialUnits,
        localeCode: Localizations.localeOf(context).languageCode,
        note: _photoNote,
      ),
    );
  }

  /// Rows clear the waiting photo; a failed read puts the note back
  /// beside it, ready to send again.
  void _onStagedReadState(BulkAddState state) {
    if (!_readingStaged || !mounted || state is BulkAddLoadingState) return;
    setState(() {
      _readingStaged = false;
      // a read that found no food keeps the photo and the note
      if (state is BulkAddLoadedState && state.rows.isNotEmpty) {
        _stagedPhoto = null;
      } else if (_textController.text.isEmpty) {
        _textController.text = _photoNote ?? '';
      }
    });
  }

  /// The photo just read, read again with what the user names in it as
  /// the note.
  Future<void> _rereadPhotoWithNote() async {
    final photo = _forkMealPhoto;
    if (photo == null) return;
    final note = await askDishName(context, initial: _photoNote ?? '');
    if (note == null || !mounted) return;
    _photoNote = note;
    _sendPhoto(photo);
  }

  void _resetAmountControllers() {
    for (final controller in _amountControllers.values) {
      controller.dispose();
    }
    _amountControllers.clear();
    for (final controller in _portionControllers.values) {
      controller.dispose();
    }
    _portionControllers.clear();
    _portionBase.clear();
    // Both are keyed by row index, so both belong to the batch that is
    // being replaced. A mark left behind would land on whichever row
    // happens to take that index next.
    _quantityErrors.clear();
  }

  Future<void> _showCandidatePicker(int index, BulkAddRow row) async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        // Label the surface, not each row — identifiers would churn with
        // the candidate count.
        child: Semantics(
          identifier: 'bulk-add-candidate-list',
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  S.of(context).bulkAddChooseFoodLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (var i = 0; i < row.resolved.candidates.length; i++)
                ListTile(
                  title: Text(row.resolved.candidates[i].name ?? ''),
                  subtitle: row.resolved.candidates[i].brands != null
                      ? Text(row.resolved.candidates[i].brands!)
                      : null,
                  trailing: i == row.selectedIndex
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(i),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) _bloc.add(ChangeRowCandidateEvent(index, chosen));
  }

  /// Quick add for [row]: the other rows stay to review, and [row] is done.
  void _showQuickAdd(BulkAddRow row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickAddBottomSheet(
        intakeType: _args.intakeTypeEntity,
        day: _args.day,
        onAdded: () {
          if (_bloc.state case BulkAddLoadedState(:final rows)) {
            final index = rows.indexWhere(
              (r) => identical(r.resolved, row.resolved),
            );
            if (index >= 0 && !rows[index].skipped) {
              _bloc.add(ToggleRowSkippedEvent(index));
            }
          }
        },
      ),
    );
  }

  /// Validate the whole batch, then write it.
  ///
  /// `MealDetailBloc.addIntake` calls `double.parse` with no guard, so a
  /// single bad row throws mid-loop and leaves the rows before it already
  /// written — a half-logged meal with no rollback. Checking every row up
  /// front is what makes the batch all-or-nothing.
  Future<void> _onSubmitPressed(BulkAddLoadedState state) async {
    // Validate the whole batch before writing any of it. addIntake parses
    // the amount with `double.parse` and no guard, so one bad row would
    // otherwise throw mid-loop and leave the rows before it already
    // written, with no rollback.
    // Every row is checked, and the loop no longer stops at the first
    // failure. It refuses the batch either way, so stopping early only
    // decided how many times the user has to submit it to find out what is
    // wrong: one field fixed, one more refusal, one more field. #1013.
    // Indexed over `rows` rather than `loggableRows`, because the failures
    // are marked on the rows themselves and a filtered iterable cannot say
    // which row it came from.
    final invalid = <int, BulkAddQuantityError>{};
    final writes = <({String unit, double amount, MealEntity meal})>[];
    // where each dish logged as one goes in [writes]
    final dishes = <({int at, Object group})>[];
    for (var index = 0; index < state.rows.length; index++) {
      final row = state.rows[index];
      if (!row.willBeLogged) continue;

      final error = row.quantityError;
      if (error != null) {
        invalid[index] = error;
        continue;
      }
      // Cannot throw: `quantityError` returned null, which required this
      // same text to parse.
      final quantity = double.parse(row.amountText.trim().replaceAll(',', '.'));
      if (row.dishIngredient?.group case final group?
          when !_separateDishes.contains(group)) {
        if (!dishes.any((d) => identical(d.group, group))) {
          dishes.add((at: writes.length, group: group));
        }
        continue;
      }
      // Store the value the intake is actually written with: nutriment
      // values are per gram/millilitre, so oz / fl.oz / serving have to be
      // converted first. Logging the raw amount stores 4 g for 4 oz.
      writes.add((
        unit: row.effectiveUnit,
        amount: convertQuantityToBaseUnit(
          quantity,
          row.effectiveUnit,
          row.meal!,
        ),
        meal: row.meal!,
      ));
    }

    if (invalid.isNotEmpty) {
      setState(() {
        _quantityErrors
          ..clear()
          ..addAll(invalid);
      });
      // The marks are on the rows, and a row can be off screen — a button
      // that refuses in silence is the state this screen was already in.
      // Naming each food and its reason keeps the snackbar honest about how
      // many rows are waiting.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            // Bounded: nothing limits how many rows a paste produces, and a
            // snackbar does not scroll — an unbounded join would cover the
            // list the marks are on. The marks carry every failure; this
            // carries as many as fit and ellipsizes the rest.
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            invalid.entries
                .map(
                  (entry) =>
                      '${_rowTitle(state.rows[entry.key])}: '
                      '${_quantityErrorText(context, entry.value)}',
                )
                .join('\n'),
          ),
        ),
      );
      return;
    }

    // A dish is one entry: its rows combined as a recipe, at its portion.
    for (final dish in dishes.reversed) {
      final meal = dishMeal(state.rows, dish.group);
      final grams = dishPortion(
        state.rows,
        dishMembers(state.rows, dish.group),
      );
      if (meal == null || grams <= 0) continue;
      writes.insert(dish.at, (unit: 'g', amount: grams, meal: meal));
    }

    setState(() {
      _quantityErrors.clear();
      _submitting = true;
    });

    // the photo's meal as logged, for a read like it later
    final memory = state.source == BulkAddReadSource.photo
        ? photoMealRecordOf(
            state.rows,
            day: _args.day,
            loggedAt: DateTime.now(),
            slot: _args.intakeTypeEntity.name,
            dish: _arrivalDish,
            corrected: _photoCorrected(state.rows),
            photoAmountOf: _photoAmountOf,
            size: _loggedSize(),
          )
        : null;

    final mealDetailBloc = locator<MealDetailBloc>();
    // set when a profile switch dropped a write
    var dropped = false;
    try {
      // Sequential, not concurrent. The tracked-day totals are accumulated
      // with a read-modify-write, so overlapping writes lose updates and
      // the day silently under-counts.
      final intakeIds = <String>[];
      for (final write in writes) {
        final intake = await mealDetailBloc.addIntake(
          context,
          // The suffix is a display device; the stored vocabulary stays
          // the closed set the export format and QR payload were written
          // against. #864 decision 3.
          storedUnit(write.unit),
          write.amount.toString(),
          _args.intakeTypeEntity,
          write.meal,
          _args.day,
        );
        // none when a profile switch dropped it; the
        // rest would go to the profile switched to
        if (intake == null) {
          dropped = true;
          break;
        }
        intakeIds.add(intake.id);
      }
      // kept beside the meal, not before it: neither waits on the other,
      // and a store that fails or never opens leaves the meal logged
      if (!dropped && memory != null) {
        unawaited(rememberPhotoMeal(memory, forkPhotoMealMemory()));
      }
      // a group in the profile its entries are in
      if (!dropped) await recordMealGroup(intakeIds, photo: _forkMealPhoto);
    } catch (e, stackTrace) {
      _log.severe('Bulk intake write failed', e, stackTrace);
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).bulkAddSearchFailedLabel)),
      );
      return;
    }

    if (!mounted) return;

    locator<HomeBloc>().add(const LoadItemsEvent());
    locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dropped
              ? 'Not all added: the profile changed.'
              : 'Added to ${_mealName(context)}',
        ),
      ),
    );
    Navigator.of(
      context,
    ).popUntil(ModalRoute.withName(NavigationOptions.mainRoute));
  }

  String _mealName(BuildContext context) =>
      AddMealExtension.fromIntakeTypeEntity(
        _args.intakeTypeEntity,
      ).getTypeName(context);
}
