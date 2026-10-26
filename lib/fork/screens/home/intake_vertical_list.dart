// Fork-owned copy of lib/features/home/presentation/widgets/intake_vertical_list.dart
// (D23); upstream's later changes to it are ported by hand:
// fork/tools/upstream-copies.sh.
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
// upstream's CopyDialog import, unused since
// import 'package:opennutritracker/core/presentation/widgets/copy_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/copy_to_profile_sheet.dart';
// upstream's DeleteAllDialog import, unused since
// import 'package:opennutritracker/core/presentation/widgets/delete_all_dialog.dart';
import 'package:opennutritracker/fork/screens/home/intake_card.dart';
import 'package:opennutritracker/core/presentation/widgets/placeholder_card.dart';
import 'package:opennutritracker/core/presentation/widgets/share_qr_dialog.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/core/utils/vertical_list_popup_menu_selections.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/diary_sort_type.dart';
import 'package:opennutritracker/features/home/domain/entity/shared_meal_payload.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/home/presentation/screens/import_meal_scanner_screen.dart';
import 'package:opennutritracker/features/home/presentation/widgets/shared_meal_import_dialogs.dart';
import 'package:opennutritracker/features/home/presentation/widgets/shared_meal_importer.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';

class IntakeVerticalList extends StatefulWidget {
  final DateTime day;
  final String title;
  final IconData listIcon;
  final AddMealType addMealType;
  final List<IntakeEntity> intakeList;
  final bool usesImperialUnits;
  final bool showMealMacros;
  final Function(IntakeEntity intake, TrackedDayEntity? trackedDayEntity)
  onDeleteIntakeCallback;
  final Function(BuildContext, IntakeEntity)? onItemLongPressedCallback;
  final Function(bool)? onItemDragCallback;
  final Function(BuildContext, IntakeEntity, bool)? onItemTappedCallback;
  final Function(
    IntakeEntity intake,
    TrackedDayEntity? trackedDayEntity,
    AddMealType? type,
  )?
  onCopyIntakeCallback;
  final TrackedDayEntity? trackedDayEntity;
  // #150: optional recommended kcal target for this meal section. When
  // supplied and > 0, the section header shows "consumed / target kcal" so
  // someone scanning the day can see at a glance whether breakfast (or any
  // other meal) sat inside the share they had planned for it.
  final double? mealKcalTarget;

  /// Current sort applied to [intakeList]. When non-null (and
  /// [onSortTypeChanged] is also provided), a small sort menu is rendered in
  /// the section header. Callers are responsible for sorting [intakeList]
  /// before it reaches the widget — this field only drives the menu's
  /// highlighted selection.
  final DiarySortType? sortType;

  /// Called when the user picks a new sort option from the section header.
  /// When null, the sort menu is hidden.
  final ValueChanged<DiarySortType>? onSortTypeChanged;

  // an hour's section has no add row of its own,
  // and shows each food's time
  final bool hourSection;

  // the time the meal sits at on the Diary's
  // timeline, shown in place of its icon; its add button is in the header
  final DateTime? forkTime;

  const IntakeVerticalList({
    super.key,
    required this.day,
    required this.title,
    required this.listIcon,
    required this.addMealType,
    required this.intakeList,
    required this.usesImperialUnits,
    this.showMealMacros = true,
    required this.onDeleteIntakeCallback,
    this.onItemLongPressedCallback,
    this.onItemDragCallback,
    this.onItemTappedCallback,
    this.onCopyIntakeCallback,
    this.trackedDayEntity,
    this.mealKcalTarget,
    this.sortType,
    this.onSortTypeChanged,
    this.hourSection = false,
    this.forkTime,
  });

  /// Whether a meal section is rendered on Home and in the Diary. A 0 % share
  /// hides an empty section the user opted out of (OMAD, two-meal), but one
  /// that already holds intakes always shows: otherwise those entries count
  /// toward the day's totals with no way to see, edit or delete them (#1305).
  static bool isShown({
    required int sharePct,
    required List<IntakeEntity> intakes,
  }) => sharePct > 0 || intakes.isNotEmpty;

  @override
  State<IntakeVerticalList> createState() => _IntakeVerticalListState();
}

class _IntakeVerticalListState extends State<IntakeVerticalList> {
  late MealDetailBloc _mealDetailBloc;
  late HomeBloc _homeBloc;

  @override
  void initState() {
    _mealDetailBloc = locator<MealDetailBloc>();
    _homeBloc = locator<HomeBloc>();
    super.initState();
  }

  double get totalKcal {
    return widget.intakeList.fold(
      0,
      (previousValue, element) => previousValue + element.totalKcal,
    );
  }

  double get totalCarbsGram {
    return widget.intakeList.fold(
      0,
      (previousValue, element) => previousValue + element.totalCarbsGram,
    );
  }

  double get totalFatsGram {
    return widget.intakeList.fold(
      0,
      (previousValue, element) => previousValue + element.totalFatsGram,
    );
  }

  double get totalProteinsGram {
    return widget.intakeList.fold(
      0,
      (previousValue, element) => previousValue + element.totalProteinsGram,
    );
  }

  // #150: only show a header when we have something to say — either some
  // food was logged, or a recommended target exists so the section can read
  // "0 / 600 kcal" before anything is logged.
  bool get _hasMealKcalTarget =>
      widget.mealKcalTarget != null && widget.mealKcalTarget! > 0;

  bool get _shouldShowHeaderSummary => totalKcal > 0 || _hasMealKcalTarget;

  String _buildHeaderSummary(BuildContext context) {
    final consumed = EnergyDisplay.formatValue(context, totalKcal);
    final kcalLine = _hasMealKcalTarget
        // the string has "kcal" written into it
        ? inEnergyUnit(
            context,
            S
                .of(context)
                .diaryMealKcalConsumedOfTarget(
                  consumed,
                  EnergyDisplay.formatValue(context, widget.mealKcalTarget!),
                ),
          )
        : EnergyDisplay.formatWithUnit(context, totalKcal);
    if (widget.showMealMacros && totalKcal > 0) {
      return '$kcalLine\n${inMacroOrder(carbs: '${totalCarbsGram.toInt()} ${S.of(context).carbsLabelShort}', fat: '${totalFatsGram.toInt()} ${S.of(context).fatLabelShort}', protein: '${totalProteinsGram.toInt()} ${S.of(context).proteinLabelShort}').join('  ')}';
    }
    return kcalLine;
  }

  // the summary on a line of its own under
  // the header's row, lined up with the title
  Widget _forkTimelineHeader(BuildContext context, Widget row) {
    if (widget.forkTime == null || totalKcal <= 0) return row;
    final palette = paletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        // Up under the title: the row is as tall as its buttons.
        Transform.translate(
          offset: const Offset(0, -10),
          child: Padding(
            padding: const EdgeInsets.only(left: 48 + Dimens.spacing12),
            child: Text(
              _timelineSummary(context),
              semanticsLabel: _headerSummaryLabel(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: palette.textMuted),
            ),
          ),
        ),
      ],
    );
  }

  // the summary on one line,
  // "1166 kcal · C 215 · F 15 · P 39"; the meal's target is left to the
  // spoken label, the day's to the card above
  String _timelineSummary(BuildContext context) {
    final kcalLine = EnergyDisplay.formatWithUnit(context, totalKcal);
    if (!widget.showMealMacros || totalKcal <= 0) return kcalLine;
    return [
      kcalLine,
      ...inMacroOrder(
        carbs: 'C ${totalCarbsGram.toInt()}',
        fat: 'F ${totalFatsGram.toInt()}',
        protein: 'P ${totalProteinsGram.toInt()}',
      ),
    ].join(' · ');
  }

  // the summary in words, not "22 p 41 f 175 c"
  String _headerSummaryLabel(BuildContext context) {
    final s = S.of(context);
    final consumed = EnergyDisplay.formatValue(context, totalKcal);
    final kcalLine = _hasMealKcalTarget
        ? inEnergyUnit(
            context,
            s.diaryMealKcalConsumedOfTarget(
              consumed,
              EnergyDisplay.formatValue(context, widget.mealKcalTarget!),
            ),
          )
        : EnergyDisplay.formatWithUnit(context, totalKcal);
    if (!widget.showMealMacros || totalKcal <= 0) return kcalLine;
    return [
      kcalLine,
      ...inMacroOrder(
        carbs: '${totalCarbsGram.toInt()} g ${s.carbsLabel}',
        fat: '${totalFatsGram.toInt()} g ${s.fatLabel}',
        protein: '${totalProteinsGram.toInt()} g ${s.proteinLabel}',
      ),
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Container(
          // closer together on the timeline
          padding: EdgeInsets.fromLTRB(
            Dimens.spacing16,
            widget.forkTime == null ? Dimens.spacing20 : Dimens.spacing8,
            Dimens.spacing12,
            widget.forkTime == null ? Dimens.spacing8 : 0,
          ),
          alignment: Alignment.centerLeft,
          child: _forkTimelineHeader(
            context,
            Row(
              children: [
                if (widget.forkTime case final time?)
                  SizedBox(
                    width: 48,
                    child: Text(
                      DateFormat.Hm().format(time),
                      style: textTheme.labelMedium?.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(Dimens.spacing8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: Dimens.borderRadiusS,
                    ),
                    child: Icon(widget.listIcon, size: 20, color: accent),
                  ),
                const SizedBox(width: Dimens.spacing12),
                Expanded(
                  // a heading TalkBack can jump between
                  // a smaller title
                  child: widget.forkTime != null
                      ? Semantics(
                          header: true,
                          child: Text(
                            widget.title,
                            style: textTheme.titleMedium?.copyWith(
                              color: palette.textStrong,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : // [/fork]
                        Semantics(
                          header: true,
                          child: AutoSizeText(
                            widget.title,
                            maxLines: 1,
                            minFontSize: 14,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleLarge?.copyWith(
                              color: palette.textStrong,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: Dimens.spacing8),
                if (_shouldShowHeaderSummary &&
                    widget.forkTime == null) //: under the title
                  Flexible(
                    child: Text(
                      _buildHeaderSummary(context),
                      // read as words; at a large font
                      // the macros wrap as far as they need rather than cut off
                      semanticsLabel: _headerSummaryLabel(context),
                      // (no ellipsis: with no line limit it cuts to one line)
                      maxLines: null,
                      style: textTheme.labelMedium?.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                if (widget.onSortTypeChanged != null && totalKcal > 0)
                  _buildSortMenu(context),
                // the add row's button
                if (widget.forkTime != null)
                  IconButton(
                    key: const ValueKey('timeline-add'),
                    tooltip: S.of(context).addToSectionLabel(widget.title),
                    icon: Icon(Icons.add_rounded, color: accent),
                    onPressed: () => _onPlaceholderCardTapped(context),
                  ),
                Semantics(
                  identifier: 'intake-section-menu',
                  // Tight bounds: without this the node inherits the flex
                  // Row's full-width box and coordinate taps miss the button.
                  container: true,
                  child: PopupMenuButton<VerticalListPopupMenuSelections>(
                    tooltip: S.of(context).sectionOptionsLabel(widget.title),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: palette.textMuted,
                    ),
                    shape: Dimens.shapeM,
                    onSelected:
                        (VerticalListPopupMenuSelections selection) async {
                          // The section as it was when the menu was used: the
                          // Diary can move on to another day while a dialog is
                          // open (#1360), rebuilding this list for that day.
                          final intakes = widget.intakeList;
                          final onDeleteIntake = widget.onDeleteIntakeCallback;
                          final trackedDay = widget.trackedDayEntity;
                          switch (selection) {
                            case VerticalListPopupMenuSelections.onCopy:
                              // any day and meal, one
                              // entry after another (fork/copy)
                              await copyIntakesWithDialog(
                                context,
                                intakes,
                                widget.addMealType.getIntakeType(),
                              );
                              break;
                            case VerticalListPopupMenuSelections.onDelete:
                              // deleted at once, in
                              // place of upstream's DeleteAllDialog; each
                              // delete's Undo bar gathers the meal into one
                              for (IntakeEntity intake in intakes) {
                                onDeleteIntake(intake, trackedDay);
                              }
                            case VerticalListPopupMenuSelections.onShare:
                              if (context.mounted) {
                                final code = SharedMealPayload.fromIntakeList(
                                  widget.intakeList,
                                  recipeRepository: locator<RecipeRepository>(),
                                ).toJsonString();
                                final hasOtherProfiles =
                                    locator<GetProfilesUsecase>()
                                        .getProfiles()
                                        .length >
                                    1;
                                await showDialog(
                                  context: context,
                                  builder: (_) => ShareQrDialog(
                                    title: S.of(context).shareMealLabel,
                                    code: code,
                                    fileBaseName: 'meal_qr',
                                    onCopyToProfile: hasOtherProfiles
                                        ? () => showCopyToProfileSheet(
                                            context,
                                            widget.intakeList,
                                          )
                                        : null,
                                  ),
                                );
                              }
                            case VerticalListPopupMenuSelections.onImport:
                              if (context.mounted) {
                                Navigator.of(context).pushNamed(
                                  NavigationOptions.importMealScannerRoute,
                                  arguments: ImportMealScannerArguments(
                                    widget.addMealType.getIntakeType(),
                                    widget.addMealType,
                                    widget.day,
                                  ),
                                );
                              }
                            case VerticalListPopupMenuSelections.onImportCode:
                              final payload =
                                  await showDialog<SharedMealPayload>(
                                    context: context,
                                    builder: (_) =>
                                        const SharedMealCodeDialog(),
                                  );
                              if (payload != null && context.mounted) {
                                final imported = await SharedMealImporter(
                                  context,
                                  widget.addMealType.getIntakeType(),
                                  widget.addMealType,
                                  widget.day,
                                ).importPayload(payload);
                                if (imported && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        S.of(context).importMealSuccessLabel,
                                      ),
                                    ),
                                  );
                                }
                              }
                          }
                        },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<VerticalListPopupMenuSelections>>[
                          if (widget.onCopyIntakeCallback != null &&
                              totalKcal > 0)
                            PopupMenuItem<VerticalListPopupMenuSelections>(
                              value: VerticalListPopupMenuSelections.onCopy,
                              // it asks for the day
                              child: const Text('Copy…'),
                            ),
                          if (totalKcal > 0)
                            PopupMenuItem<VerticalListPopupMenuSelections>(
                              value: VerticalListPopupMenuSelections.onDelete,
                              child: Text(S.of(context).deleteAllLabel),
                            ),
                          if (totalKcal > 0)
                            PopupMenuItem<VerticalListPopupMenuSelections>(
                              value: VerticalListPopupMenuSelections.onShare,
                              child: Text(S.of(context).shareMealLabel),
                            ),
                          PopupMenuItem<VerticalListPopupMenuSelections>(
                            value: VerticalListPopupMenuSelections.onImport,
                            child: Text(S.of(context).importMealLabel),
                          ),
                          PopupMenuItem<VerticalListPopupMenuSelections>(
                            value: VerticalListPopupMenuSelections.onImportCode,
                            child: Semantics(
                              identifier: 'intake-import-meal-code',
                              child: Text(S.of(context).pasteCodeLabel),
                            ),
                          ),
                        ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DragTarget<IntakeEntity>(
          onAcceptWithDetails: (intake) {
            _onItemDropped(intake.data);
          },
          builder: (context, candidateData, rejectedData) {
            return Column(
              children: [
                for (final intakeEntity in widget.intakeList)
                  LongPressDraggable<IntakeEntity>(
                    key: ValueKey(intakeEntity.id),
                    data: intakeEntity,
                    onDragStarted: () => widget.onItemDragCallback?.call(true),
                    onDragEnd: (_) => widget.onItemDragCallback?.call(false),
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width,
                        child: Opacity(
                          opacity: 0.85,
                          child: IntakeCard(
                            key: ValueKey('fb-${intakeEntity.id}'),
                            intake: intakeEntity,
                            firstListElement: false,
                            usesImperialUnits: widget.usesImperialUnits,
                            sortType: widget.sortType,
                          ),
                        ),
                      ),
                    ),
                    childWhenDragging: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Dimens.spacing16,
                        vertical: Dimens.spacing4,
                      ),
                      child: Container(
                        height: 76,
                        decoration: BoxDecoration(
                          color: palette.surfaceMuted,
                          borderRadius: Dimens.borderRadiusM,
                          border: Border.all(
                            color: palette.border,
                            width: Dimens.hairline,
                          ),
                        ),
                      ),
                    ),
                    child: IntakeCard(
                      key: ValueKey(intakeEntity.id),
                      intake: intakeEntity,
                      onItemLongPressed: widget.onItemLongPressedCallback,
                      onItemTapped: widget.onItemTappedCallback,
                      firstListElement: false,
                      usesImperialUnits: widget.usesImperialUnits,
                      sortType: widget.sortType,
                      showTime: widget.hourSection,
                    ),
                  ),
                if (!widget.hourSection && widget.forkTime == null) // S118
                  PlaceholderCard(
                    day: widget.day,
                    onTap: () => _onPlaceholderCardTapped(context),
                    firstListElement: true,
                    semanticIdentifier: 'add-meal-placeholder',
                    label: S.of(context).addToSectionLabel(widget.title),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSortMenu(BuildContext context) {
    final current = widget.sortType ?? DiarySortType.timeAdded;
    final palette = paletteOf(context);
    return Semantics(
      identifier: 'diary-section-sort-menu',
      child: PopupMenuButton<DiarySortType>(
        tooltip: S.of(context).diarySortByLabel,
        icon: Icon(Icons.sort_rounded, color: palette.textMuted),
        shape: Dimens.shapeM,
        initialValue: current,
        onSelected: (sort) => widget.onSortTypeChanged?.call(sort),
        itemBuilder: (context) => <PopupMenuEntry<DiarySortType>>[
          CheckedPopupMenuItem<DiarySortType>(
            value: DiarySortType.timeAdded,
            checked: current == DiarySortType.timeAdded,
            child: Text(S.of(context).diarySortByTime),
          ),
          CheckedPopupMenuItem<DiarySortType>(
            value: DiarySortType.kcal,
            checked: current == DiarySortType.kcal,
            child: Text(S.of(context).diarySortByKcal),
          ),
          CheckedPopupMenuItem<DiarySortType>(
            value: DiarySortType.protein,
            checked: current == DiarySortType.protein,
            child: Text(S.of(context).diarySortByProtein),
          ),
          CheckedPopupMenuItem<DiarySortType>(
            value: DiarySortType.carbs,
            checked: current == DiarySortType.carbs,
            child: Text(S.of(context).diarySortByCarbs),
          ),
          CheckedPopupMenuItem<DiarySortType>(
            value: DiarySortType.fat,
            checked: current == DiarySortType.fat,
            child: Text(S.of(context).diarySortByFat),
          ),
        ],
      ),
    );
  }

  void _onPlaceholderCardTapped(BuildContext context) {
    Navigator.pushNamed(
      context,
      NavigationOptions.addMealRoute,
      arguments: AddMealScreenArguments(widget.addMealType, widget.day),
    );
  }

  Future<void> _onItemDropped(IntakeEntity entity) async {
    // One move under one tracked-day lock (#1317): taken apart, a profile
    // switch queued during the add could run before the delete, which
    // would then debit the incoming profile and leave the outgoing one
    // with the entry in both meals. The refreshes below wait for both,
    // so Home does not reload with the entry in both meals either.
    await withTrackedDayLockOnProfile(() async {
      await _mealDetailBloc.addIntake(
        context,
        entity.unit,
        entity.amount.toString(),
        widget.addMealType.getIntakeType(),
        entity.meal,
        entity.dateTime,
      );
      await _homeBloc.deleteIntakeItem(entity);
    });

    // Refresh Home Page
    locator<HomeBloc>().add(const LoadItemsEvent());

    // Refresh Diary Page
    locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    locator<CalendarDayBloc>().add(RefreshCalendarDayEvent());
  }
}
