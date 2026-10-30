import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
// [fork] S64 weekday-targets: a row made for another day
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
// [/fork]
// [fork] S133 quick-add
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/add/quick_add.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart' show mealLabel;
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/widget/meal_picker_chip.dart';
import 'package:opennutritracker/fork/display/sheet_inset.dart'; // [fork] S160
// [/fork]

class QuickAddBottomSheet extends StatefulWidget {
  final IntakeTypeEntity intakeType;
  final DateTime day;

  /// The add-food screen's "To log" list. With one, the entry goes on the
  /// list and the sheet closes, instead of logging and leaving for home —
  /// which would drop everything already on the list.
  final LogTray? logTray;

  const QuickAddBottomSheet({
    super.key,
    required this.intakeType,
    required this.day,
    this.logTray,
  });

  @override
  State<QuickAddBottomSheet> createState() => _QuickAddBottomSheetState();
}

class _QuickAddBottomSheetState extends State<QuickAddBottomSheet> {
  final _log = Logger('QuickAddBottomSheet');

  final _titleController = TextEditingController();
  final _energyController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();
  final _proteinController = TextEditingController();

  bool _saving = false;

  // [fork] S133 quick-add: the meal can change here, and the energy can
  // come from the macros
  late IntakeTypeEntity _type = widget.intakeType;

  double? get _kcal {
    final typed = _parsed(_energyController);
    return quickAddKcal(
      typedKcal: typed == null ? null : kcalFromInput(context, typed),
      carbs: _parsed(_carbsController),
      fat: _parsed(_fatController),
      protein: _parsed(_proteinController),
    );
  }

  List<TextEditingController> get _macroControllers => [
    _carbsController,
    _fatController,
    _proteinController,
  ];
  // [/fork]

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onRequiredFieldChanged);
    _energyController.addListener(_onRequiredFieldChanged);
    // [fork] S133 quick-add
    for (final c in _macroControllers) {
      c.addListener(_onRequiredFieldChanged);
    }
    // [/fork]
  }

  @override
  void dispose() {
    _titleController.removeListener(_onRequiredFieldChanged);
    _energyController.removeListener(_onRequiredFieldChanged);
    // [fork] S133 quick-add
    for (final c in _macroControllers) {
      c.removeListener(_onRequiredFieldChanged);
    }
    // [/fork]
    _titleController.dispose();
    _energyController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _proteinController.dispose();
    super.dispose();
  }

  void _onRequiredFieldChanged() => setState(() {});

  double? _parsed(TextEditingController c) {
    final raw = c.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || value < 0) return null;
    return value;
  }

  // [fork] S133 quick-add: the name is optional, the energy may be the
  // macros'
  bool get _canSubmit => !_saving && _kcal != null;
  // [/fork]

  Future<void> _onSubmit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);

    // [fork] S133 quick-add
    final kcal = _kcal!;
    final carbs = _parsed(_carbsController);
    final fat = _parsed(_fatController);
    final protein = _parsed(_proteinController);
    final typedTitle = _titleController.text.trim();
    final title = typedTitle.isEmpty
        ? S.of(context).quickAddDefaultName
        : typedTitle;
    // [/fork]

    try {
      final intake = _buildIntake(
        kcal: kcal,
        carbs: carbs,
        fat: fat,
        protein: protein,
        title: title,
      );
      final logTray = widget.logTray;
      if (logTray != null) {
        logTray.add(
          LogTrayItem(
            meal: intake.meal,
            unit: intake.unit,
            amount: intake.amount,
            amountLabel: S.of(context).quickAddCardLabel,
          ),
        );
        Navigator.of(context).pop();
        return;
      }
      // The entry and its row together, so no reconciliation counts the
      // entry before the row has it (#1317).
      final saved = await withTrackedDayLockOnProfile(() async {
        await locator<AddIntakeUsecase>().addIntake(intake);
        await _updateTrackedDay(intake);
        return true;
      });
      if (saved != true) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      locator<HomeBloc>().add(const LoadItemsEvent());
      locator<DiaryBloc>().add(const LoadDiaryYearEvent());
      locator<CalendarDayBloc>().add(RefreshCalendarDayEvent());

      if (!mounted) return;
      // [fork] S133 quick-add
      final mealTypeLabel = _intakeTypeLabel(context, _type);
      // [/fork]
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      // Resolve the localized message before navigating: the push below
      // removes every route (including this sheet's), so reading from
      // context afterwards would be looking up a deactivated widget.
      final addedMessage = S.of(context).quickAddAddedSnack(mealTypeLabel);
      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
        NavigationOptions.mainRoute,
        (route) => false,
      );
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(addedMessage),
        ),
      );
    } catch (e, st) {
      _log.severe('Quick Add save failed', e, st);
      Sentry.captureException(e, stackTrace: st);
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  IntakeEntity _buildIntake({
    required double kcal,
    required double? carbs,
    required double? fat,
    required double? protein,
    required String title,
  }) {
    // Store per-100g, intake amount = 100g, so totals math returns the
    // exact values the user typed.
    final nutriments = MealNutrimentsEntity(
      energyKcal100: kcal,
      carbohydrates100: carbs,
      fat100: fat,
      proteins100: protein,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    );
    final meal = MealEntity(
      code: IdGenerator.getUniqueID(),
      name: title,
      url: null,
      mealQuantity: '100',
      mealUnit: 'gml',
      servingQuantity: null,
      servingUnit: 'gml',
      servingSize: '',
      nutriments: nutriments,
      source: MealSourceEntity.custom,
    );
    return IntakeEntity(
      id: IdGenerator.getUniqueID(),
      unit: 'g',
      amount: 100,
      // [fork] S133 quick-add
      type: _type,
      // [/fork]
      meal: meal,
      dateTime: widget.day,
    );
  }

  Future<void> _updateTrackedDay(IntakeEntity intake) async {
    final addTrackedDay = locator<AddTrackedDayUsecase>();
    final hasTrackedDay = await addTrackedDay.hasTrackedDay(widget.day);
    if (!hasTrackedDay) {
      // [fork] S64 weekday-targets: the weekday of the day added to
      final kcalGoal = await forkGoalOnDay(
        await locator<GetKcalGoalUsecase>().getKcalGoal(),
        widget.day,
      );
      // [/fork]
      final macroGoal = locator<GetMacroGoalUsecase>();
      await addTrackedDay.addNewTrackedDayIfAbsent(
        widget.day,
        kcalGoal,
        await macroGoal.getCarbsGoal(kcalGoal),
        await macroGoal.getFatsGoal(kcalGoal),
        await macroGoal.getProteinsGoal(kcalGoal),
      );
    }
    await addTrackedDay.addDayCaloriesTracked(widget.day, intake.totalKcal);
    await addTrackedDay.addDayMacrosTracked(
      widget.day,
      carbsTracked: intake.totalCarbsGram,
      fatTracked: intake.totalFatsGram,
      proteinTracked: intake.totalProteinsGram,
    );
  }

  String _intakeTypeLabel(BuildContext context, IntakeTypeEntity type) {
    switch (type) {
      case IntakeTypeEntity.breakfast:
        return S.of(context).breakfastLabel;
      case IntakeTypeEntity.lunch:
        return S.of(context).lunchLabel;
      case IntakeTypeEntity.dinner:
        return S.of(context).dinnerLabel;
      case IntakeTypeEntity.snack:
        return S.of(context).snackLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // [fork] S133 quick-add: the canvas's Quick add A
    final macrosKcal = quickAddKcal(
      carbs: _parsed(_carbsController),
      fat: _parsed(_fatController),
      protein: _parsed(_proteinController),
    );
    final kcal = _kcal;

    return Padding(
      padding: EdgeInsets.only(
        bottom: sheetBottomInset(context), // [fork] S160 above the nav bar
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.quickAddBottomSheetTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                MealPickerChip(
                  key: const ValueKey('quick-add-meal'),
                  type: _type,
                  onChanged: (type) => setState(() => _type = type),
                ),
              ],
            ),
            const SizedBox(height: Dimens.spacing8),
            QuickAddEnergyField(
              controller: _energyController,
              macrosKcal: macrosKcal,
            ),
            const SizedBox(height: Dimens.spacing16),
            QuickAddMacroFields(
              carbs: _carbsController,
              fat: _fatController,
              protein: _proteinController,
            ),
            const SizedBox(height: Dimens.spacing12),
            Semantics(
              identifier: 'quick-add-title',
              child: TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: '${s.quickAddTitleHint} (optional)',
                  hintText: s.quickAddDefaultName,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: Dimens.spacing16),
            Semantics(
              identifier: 'quick-add-submit',
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                ),
                onPressed: _canSubmit ? _onSubmit : null,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        kcal == null
                            ? s.quickAddSubmitLabel
                            : 'Add ${energyText(context, kcal)} to '
                                  '${mealLabel(context, _type)}',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
    // [/fork]
  }
}
