// Fork-owned copy of lib/features/add_meal/presentation/screens/bulk_add_screen.dart (D23); upstream's later changes to it
// are ported by hand: fork/tools/upstream-copies.sh.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
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
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_photo_encoder.dart';
import 'package:opennutritracker/features/add_meal/util/portion_label.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
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
import 'package:opennutritracker/fork/dish/dish_recipe.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';
import 'package:opennutritracker/fork/bulk/discard_guard.dart';
// remember which entries one save wrote (D14)
import 'package:opennutritracker/fork/leftovers/meal_groups.dart';
import 'package:opennutritracker/fork/leftovers/meal_photo_cache.dart';
// a recipe from typed lines or a recipe link
import 'package:http/http.dart' as http;
import 'package:opennutritracker/fork/recipe/recipe_link.dart';

part 'bulk_add_body.dart';
part 'bulk_add_row.dart';

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

class _BulkAddScreenState extends State<BulkAddScreen> {
  final _log = Logger('BulkAddScreen');
  final _bloc = locator<BulkAddBloc>();
  final _textController = TextEditingController();
  // the photo this batch was read from, kept with the meal
  MealPhoto? _forkMealPhoto;
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
  late final _dishBreakdown = DishBreakdownController(_bloc)
    ..addListener(() {
      if (mounted) setState(() {});
    });

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
    // Keyed by row index, which the swap moves.
    _quantityErrors.clear();
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
  late Future<bool> _modelUnknown = _resolveModelUnknown();

  Future<bool> _resolveModelUnknown() async {
    return !await locator<AiCredentialStorage>().hasAnyUsableProvider();
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _args =
        ModalRoute.of(context)!.settings.arguments as BulkAddScreenArguments;
    // straight to the photo sheet, once
    if (_args.startWithPhoto && !_forkPhotoStarted) {
      _forkPhotoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (await _photoAvailable && mounted) await _onPhotoPressed();
      });
    }
    // what another app shared, once: text is read as if typed, a photo
    // after the same disclosure as the camera's
    if (_forkSharedTaken) return;
    _forkSharedTaken = true;
    if (_args.sharedText case final text?) {
      _textController.text = text;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onParsePressed();
      });
    }
    if (_args.sharedPhotoPath case final path?) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (await _photoAvailable && mounted) {
          await _onPhotoPressed(sharedPath: path);
          return;
        }
        _discardShared(path);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Reading a photo needs a model that sees images: set one up '
              'in Settings › AI meal logging.',
            ),
          ),
        );
      });
    }
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
    _bloc.close();
    _textController.dispose();
    for (final controller in _amountControllers.values) {
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
            Text(S.of(context).bulkAddTitle),
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
          // Only offered when the user has a key enabled. There is no
          // offline way to read a photo, so showing the action to everyone
          // would advertise a button that can only ever apologise.
          FutureBuilder<bool>(
            future: _photoAvailable,
            builder: (context, snapshot) => snapshot.data == true
                ? Semantics(
                    identifier: 'bulk-add-photo',
                    child: IconButton(
                      onPressed: _onPhotoPressed,
                      icon: const Icon(Icons.photo_camera_rounded),
                      tooltip: S.of(context).bulkAddPhotoLabel,
                    ),
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
                  maxFieldHeight: constraints.maxHeight * 0.3,
                ),
                const Divider(height: 1),
                Expanded(child: _buildBody(context, state)),
                if (state is BulkAddLoadedState)
                  _buildSubmitBar(context, state),
              ],
            ),
          ),
        ),
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

  Widget _buildInput(
    BuildContext context, {
    required double maxFieldHeight,
  }) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Scrolls past its ceiling rather than being clipped: what is typed
        // must stay reachable, and at ordinary text sizes four lines are far
        // below this so nothing changes.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxFieldHeight),
          child: Semantics(
            identifier: 'bulk-add-input',
            child: TextField(
              controller: _textController,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: S.of(context).bulkAddInputHint,
                // what the field does with a photo (H10)
                helperText: 'With a photo, this is sent as its note',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          identifier: 'bulk-add-parse',
          child: FilledButton.icon(
            onPressed: _onParsePressed,
            icon: const Icon(Icons.search),
            label: Text(S.of(context).bulkAddParseLabel),
          ),
        ),
      ],
    ),
  );

  void _clearQuantityError(int index) =>
      setState(() => _quantityErrors.remove(index));

  Widget _buildSubmitBar(BuildContext context, BulkAddLoadedState state) {
    final count = state.loggableCount;
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
            label: Text(S.of(context).bulkAddSubmitLabel(count)),
          ),
        ),
      ),
    );
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

  Future<void> _onPhotoPressed({String? sharedPath}) async {
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
                leading: Icon(
                  sharedPath == null
                      ? Icons.photo_camera_rounded
                      : Icons.photo_rounded,
                ),
                title: Text(
                  sharedPath == null
                      ? S.of(sheetContext).mealImageTakePhoto
                      : 'Read the shared photo',
                ),
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
        picked = await ImagePicker().pickImage(source: ImageSource.camera);
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

    // A photo replaces the previous batch, so the old controllers go with it.
    _resetAmountControllers();
    _forkMealPhoto = photo;

    _bloc.add(
      ReadMealPhotoEvent(
        photo: photo,
        usesImperialUnits: _args.usesImperialUnits,
        localeCode: Localizations.localeOf(context).languageCode,
        note: _textController.text.trim().isEmpty
            ? null
            : _textController.text.trim(),
      ),
    );
  }

  void _resetAmountControllers() {
    for (final controller in _amountControllers.values) {
      controller.dispose();
    }
    _amountControllers.clear();
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

  void _showQuickAdd() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickAddBottomSheet(
        intakeType: _args.intakeTypeEntity,
        day: _args.day,
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
    final writes = <({BulkAddRow row, double amount})>[];
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
      // Store the value the intake is actually written with: nutriment
      // values are per gram/millilitre, so oz / fl.oz / serving have to be
      // converted first. Logging the raw amount stores 4 g for 4 oz.
      writes.add((
        row: row,
        amount: convertQuantityToBaseUnit(
          quantity,
          row.effectiveUnit,
          row.meal!,
        ),
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

    setState(() {
      _quantityErrors.clear();
      _submitting = true;
    });

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
          storedUnit(write.row.effectiveUnit),
          write.amount.toString(),
          _args.intakeTypeEntity,
          write.row.meal!,
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
