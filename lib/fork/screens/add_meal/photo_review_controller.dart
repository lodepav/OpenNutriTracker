import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/bulk/amount_question.dart';
import 'package:opennutritracker/fork/bulk/cooking_fat.dart';
import 'package:opennutritracker/fork/bulk/meal_scale.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory.dart';
import 'package:opennutritracker/fork/bulk/put_row.dart';
import 'package:opennutritracker/fork/bulk/scale_rows.dart';
import 'package:opennutritracker/fork/bulk/shown_unit.dart';
import 'package:opennutritracker/fork/bulk/usual_sizes.dart';
import 'package:opennutritracker/fork/food/dish_name.dart';

/// A row as the photo's read gave it: its food, unit, grams or millilitres
/// and amount text, and whether a size could change it then.
typedef _PhotoRow = ({
  String key,
  String unit,
  double? base,
  String text,
  bool sizable,
});

/// Which amount a photo's review row carries: the meal's Size, the amount
/// question, a remembered meal, the usual sizes and the cooking fat
/// question, taken anew with each read. Follows the bloc's states; what it
/// changes goes to the bloc as events.
class PhotoReviewController extends ChangeNotifier {
  static final _log = Logger('PhotoReviewController');

  final BulkAddBloc _bloc;
  final String? Function() _note;
  final Future<List<PhotoMealRecord>> Function() _records;
  final Future<ResolvedMealItem?> Function(double grams) _cookingFatFood;
  late final StreamSubscription<BulkAddState> _subscription;

  /// [note] is what the photo was sent with; [records] the photo meal
  /// memory; [cookingFatFood] the food table's oil at a weight.
  PhotoReviewController(
    this._bloc, {
    required String? Function() note,
    required Future<List<PhotoMealRecord>> Function() records,
    required Future<ResolvedMealItem?> Function(double grams) cookingFatFood,
  }) : _note = note,
       _records = records,
       _cookingFatFood = cookingFatFood {
    _subscription = _bloc.stream.listen(_onState);
  }

  /// The meal's Size on a photo's review: taken anew with each read.
  MealScale get mealScale => _mealScale;
  var _mealScale = MealScale();

  /// The rows a size just set, for the card to say the meal's energy at.
  List<BulkAddRow>? _mealSizeSaid;

  /// The one amount a photo's review asks about, chosen once per read;
  /// null when none was, or once it ended.
  AmountQuestion? get amountQuestion => _amountQuestion;
  AmountQuestion? _amountQuestion;
  bool _amountAsked = false;

  /// An answer to say once built: the amount, and the rows it set.
  ({String amount, List<BulkAddRow> rows})? _amountSaid;

  /// A meal like this photo's that the user corrected before, found once
  /// per read as its rows arrive; null when none was.
  PhotoMealMatch? get history => _history;
  PhotoMealMatch? _history;
  bool _historyAsked = false;

  /// While its amounts are used: the bases and size they replaced.
  MealScaleSnapshot? _historyUndo;

  /// Whether the remembered meal's amounts are used now.
  bool get historyTaken => _historyUndo != null;

  /// Counts reads, so a memory found for one is not offered on the next.
  var _readSerial = 0;

  /// The dish the photo's read arrived as, kept with the meal on Log.
  String? get arrivalDish => _arrivalDish;
  String? _arrivalDish;

  /// The rows of a photo's read as they arrived, kept so the photo's own
  /// amounts can come back and be kept with the meal on Log.
  final _photoRows = LinkedHashMap<ResolvedMealItem, _PhotoRow>.identity();

  /// The rows the usual sizes changed on this read, and the foods the line
  /// names.
  final _usualRows = Set<ResolvedMealItem>.identity();
  List<({String name, double factor})> get usualFoods => _usualFoods;
  List<({String name, double factor})> _usualFoods = const [];

  /// The bases before the usual sizes, which "Use the photo's amounts"
  /// puts back, null when none were applied; and, while the photo's
  /// amounts are used, the usual ones.
  MealScaleSnapshot? _photoBases;
  MealScaleSnapshot? _usualBases;

  /// Whether the usual sizes are what the rows' bases are now.
  bool get usualInForce =>
      _photoBases != null && _usualBases == null && _historyUndo == null;

  /// Each row's grams or millilitres when it first appeared, and whether
  /// the user has changed any amount from it (a row they set that moved).
  final _firstAmounts = LinkedHashMap<ResolvedMealItem, double?>.identity();
  bool _amountChanged = false;

  /// The question about the fat the meal was cooked or dressed with,
  /// decided once per read as its rows arrive; null when not asked.
  CookingFatAsk? get fatAsk => _fatAsk;
  CookingFatAsk? _fatAsk;
  bool _fatAsked = false;

  /// Answered None: the question goes.
  bool get fatClosed => _fatClosed;
  bool _fatClosed = false;

  /// The fat row a chip added, while it is on the review.
  ResolvedMealItem? _fatItem;

  /// The chip tapped while the table's oil is looked up.
  int? _fatPending;

  /// The read's own oil or butter row the chips set, as it was before
  /// them, its grams then, and whether the user had set it.
  ({BulkAddRow row, double grams, bool pinned})? _fatTarget;

  /// A read starting takes a new scale; a photo's rows arriving are its
  /// base, and every later state is followed: what the user changed is
  /// pinned, and rows a breakdown wrote or a put-back food take the size.
  void _onState(BulkAddState state) {
    if (state is! BulkAddLoadedState) {
      _mealScale = MealScale(note: _note());
      _amountQuestion = null;
      _amountAsked = false;
      _readSerial++;
      _history = null;
      _historyAsked = false;
      _historyUndo = null;
      _arrivalDish = null;
      _photoRows.clear();
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
      _fatTarget = null;
      return;
    }
    if (state.source != BulkAddReadSource.photo) return;
    _followAmountQuestion(state);
    _askCookingFat(state);
    _askHistory(state);
    final amounts = _mealScale.follow(state.rows);
    _followAmountChanges(state.rows);
    if (amounts.isNotEmpty) _bloc.add(ScaleRowsEvent(amounts));
    notifyListeners();
  }

  /// A photo's rows as they first arrive are matched against the meals the
  /// user corrected before; the match is offered once it is found.
  void _askHistory(BulkAddLoadedState state) {
    if (_historyAsked || state.rows.isEmpty) return;
    _historyAsked = true;
    _arrivalDish = readDishName(state.rows);
    if (state.modelFailure != null) return;
    final note = _note();
    for (final row in state.rows) {
      final meal = row.meal;
      if (meal == null) continue;
      _photoRows[row.resolved] = (
        key: foodKeyOf(meal),
        unit: row.effectiveUnit,
        base: baseAmountOf(row),
        text: row.amountText,
        sizable: isScalableRow(row, note: note),
      );
    }
    unawaited(_findHistory(_readSerial, state.rows, note));
  }

  Future<void> _findHistory(
    int read,
    List<BulkAddRow> rows,
    String? note,
  ) async {
    final List<PhotoMealRecord> records;
    try {
      records = await _records();
    } catch (e, stackTrace) {
      _log.warning('Reading the photo meal memory failed', e, stackTrace);
      return;
    }
    if (_disposed || read != _readSerial) return;
    final now = DateTime.now();
    final match = photoMealMatchFor(rows, records, note: note, now: now);
    if (match != null) {
      _history = match;
      notifyListeners();
    }
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
      note: _note(),
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
        // named as the row's title reads
        final name = switch (row.meal) {
          final meal? when meal.name != null => shownDishName(meal),
          _ => row.resolved.parsed.query,
        };
        foods.putIfAbsent(key, () => (name: name, factor: factor));
      }
    }
    final before = _mealScale.snapshot();
    final scaled = _mealScale.rebase(state.rows, amounts);
    _usualRows
      ..clear()
      ..addAll(amounts.keys);
    _usualFoods = [...foods.values];
    _photoBases = before;
    _usualBases = null;
    notifyListeners();
    // not said: nothing was tapped, and the line is read with the card
    if (scaled.isNotEmpty) _bloc.add(ScaleRowsEvent(scaled));
  }

  /// Whether the usual sizes' line is shown: some row they sized is still
  /// one the Size changes, and no earlier amounts are used.
  bool usualShown(List<BulkAddRow> rows) =>
      _photoBases != null &&
      _historyUndo == null &&
      rows.any(
        (row) => _usualRows.contains(row.resolved) && _mealScale.canScale(row),
      );

  /// "Use the photo's amounts": the bases before the usual sizes back, the
  /// rows the user set left as set.
  void usePhotoAmounts() {
    final state = _bloc.state;
    final photo = _photoBases;
    if (state is! BulkAddLoadedState || photo == null || !usualInForce) {
      return;
    }
    final usual = _mealScale.snapshot();
    final amounts = _mealScale.restore(state.rows, photo);
    _usualBases = usual;
    notifyListeners();
    _sendScaled(state.rows, amounts);
  }

  /// Back to the usual sizes, and the size chosen with them.
  void useUsualSizes() {
    final state = _bloc.state;
    final usual = _usualBases;
    if (state is! BulkAddLoadedState || usual == null) return;
    final amounts = _mealScale.restore(state.rows, usual);
    _usualBases = null;
    notifyListeners();
    _sendScaled(state.rows, amounts);
  }

  /// The photo's own grams or millilitres for [row], kept with the meal on
  /// Log: none for a row the read did not give, nor one whose match or
  /// unit changed, nor one no size could change (its amount was not the
  /// photo's estimate).
  double? photoAmountOf(BulkAddRow row) {
    final photo = _photoRows[row.resolved];
    final meal = row.meal;
    if (photo == null || !photo.sizable || meal == null) return null;
    if (foodKeyOf(meal) != photo.key || row.effectiveUnit != photo.unit) {
      return null;
    }
    return photo.base;
  }

  /// Notes each new row's amount, and whether a row the user set has moved
  /// from it: what makes a logged meal "corrected".
  void _followAmountChanges(List<BulkAddRow> rows) {
    for (final row in rows) {
      final first = _firstAmounts.putIfAbsent(
        row.resolved,
        () => baseAmountOf(row),
      );
      // the fat chips' answer counts until None, which takes it back
      if (identical(row.resolved, _fatTarget?.row.resolved)) continue;
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
  bool photoCorrected(List<BulkAddRow> rows) =>
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
  bool historyShown(List<BulkAddRow> rows) {
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
  /// amounts on the rows that would take them, the other rows the Size
  /// changes at their bases (the usual sizes' while in force, else the
  /// photo's), and the amounts the user set kept.
  List<BulkAddRow> withHistory(List<BulkAddRow> rows) {
    final match = _history;
    if (match == null) return rows;
    final amounts = _mealScale.rebaseTargets(
      rows,
      photoMealAmounts(rows, match.record, canTake: _mealScale.canScale),
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
  /// the other rows it may change go back to their bases: a usual size in
  /// force is the user's too, so it stays, else the photo's amount. The
  /// question on a shared row goes, and the meal's energy is said.
  void useHistory() {
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
    final amounts = _mealScale.rebase(state.rows, taken);
    _historyUndo = before;
    if (_amountQuestion case final question?
        when state.rows.any(
          (row) => question.isFor(row) && taken.containsKey(row.resolved),
        )) {
      _amountQuestion = null;
    }
    notifyListeners();
    _sendScaled(state.rows, amounts);
  }

  /// Undo: the photo's bases and the size before, back.
  void undoHistory() {
    final state = _bloc.state;
    final before = _historyUndo;
    if (state is! BulkAddLoadedState || before == null) return;
    final amounts = _mealScale.restore(state.rows, before);
    _historyUndo = null;
    notifyListeners();
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
  void setMealSize(double factor) {
    final state = _bloc.state;
    if (state is! BulkAddLoadedState) return;
    _mealScale.factor = factor;
    notifyListeners();
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

  /// The rows a size just set, once: the card says the meal's energy at
  /// them. Called while building, so it does not notify.
  List<BulkAddRow>? takeMealSizeSaid() {
    final rows = _mealSizeSaid;
    _mealSizeSaid = null;
    return rows;
  }

  /// The user set row [index]'s amount: the meal's Size leaves it, and a
  /// question on it is answered another way, so it goes for good.
  void pinRow(int index) {
    final state = _bloc.state;
    if (state is BulkAddLoadedState && index < state.rows.length) {
      final row = state.rows[index];
      _mealScale.pin(row);
      if (_amountQuestion?.isFor(row) ?? false) {
        _amountQuestion = null;
        notifyListeners();
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
              note: _note(),
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

  /// Chip [choice] of the question on row [index] tapped. The amount the
  /// row shows is confirmed as it is: not pinned, so the Size keeps scaling
  /// it, and not "Set by you"; a pinned confirmed row took the Size's step
  /// off the meal's biggest food. Another amount is taken as a typed one,
  /// in the unit it is shown in, and the Size leaves it. Either way the
  /// amount and the meal's energy are said. True when the row was set to
  /// another amount, so the screen clears its refusal mark.
  bool answerAmount(int index, int choice) {
    final state = _bloc.state;
    final question = _amountQuestion;
    if (state is! BulkAddLoadedState || question == null) return false;
    if (index >= state.rows.length || !question.isFor(state.rows[index])) {
      return false;
    }
    final row = state.rows[index];
    final chip = question.answer(row, choice);
    if (chip == null) return false;
    if (chip.unit == row.effectiveUnit && chip.text == row.amountText) {
      _amountSaid = (amount: chip.spoken, rows: state.rows);
      notifyListeners();
      return false;
    }
    _setRowTo(state, index, chip);
    return true;
  }

  /// Row [index] of [state] set to [chip] as the user's amount, in the unit
  /// it is shown in: the meal's Size leaves it, and the amount and the
  /// meal's energy are said.
  void _setRowTo(BulkAddLoadedState state, int index, AmountChoice chip) {
    final row = state.rows[index];
    _mealScale.pin(row);
    // said once the row is built: the energy is formatted per profile
    _amountSaid = (
      amount: chip.spoken,
      rows: [
        for (final (i, r) in state.rows.indexed)
          i == index ? r.copyWith(unit: chip.unit, amountText: chip.text) : r,
      ],
    );
    notifyListeners();
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

  /// The answer to say, once: the amount, and the rows it set. Called while
  /// building, so it does not notify.
  ({String amount, List<BulkAddRow> rows})? takeAmountSaid() {
    final said = _amountSaid;
    _amountSaid = null;
    return said;
  }

  /// The fat question for a photo's rows as they first arrive (D48).
  void _askCookingFat(BulkAddLoadedState state) {
    if (_fatAsked || state.rows.isEmpty) return;
    _fatAsked = true;
    if (state.modelFailure != null) return;
    _fatAsk = cookingFatAskFor(state.rows, note: _note());
  }

  /// The fat row the chips added, as it is on the review; null when none.
  BulkAddRow? _fatRow(List<BulkAddRow> rows) {
    final item = _fatItem;
    return item == null ? null : _rowOf(rows, item);
  }

  /// The row of [rows] for [item]; null when it is not there.
  static BulkAddRow? _rowOf(List<BulkAddRow> rows, ResolvedMealItem item) {
    for (final row in rows) {
      if (identical(row.resolved, item)) return row;
    }
    return null;
  }

  /// The chip of the fat question that shows as chosen: the one at the
  /// added row's amount, or the one tapped while its oil is looked up.
  /// None while the row is in another unit than the chips' grams. For the
  /// read's own fat row, the one whose answer its grams are now.
  int? fatChosen(List<BulkAddRow> rows) {
    if (_fatTarget case (:final row, :final grams, pinned: _)) {
      final ask = _fatAsk;
      final now = _rowOf(rows, row.resolved);
      final at = now == null ? null : cookingFatGramsOf(now);
      return ask == null || at == null
          ? null
          : cookingFatChipAt(ask, grams, at);
    }
    return switch (_fatRow(rows)) {
      final row? when row.effectiveUnit == row.resolved.parsed.unit =>
        cookingFatChipOf(row.amountText),
      final _? => null,
      null => _fatPending,
    };
  }

  /// None (-1) takes the added row off and ends the question; an amount
  /// adds the table's oil at it, pinned as the user's (the Size leaves
  /// it), or sets the row it added before to it. With an oil or butter of
  /// the read's own, an amount goes into that row instead and None puts
  /// it back as it was. True when the table had no oil to add, for the
  /// screen to say so.
  Future<bool> chooseCookingFat(int choice) async {
    final state = _bloc.state;
    if (state is! BulkAddLoadedState) return false;
    final current = _fatRow(state.rows);
    // a row taken off the review or left out since takes no answer
    if (_fatTarget case (
      :final row,
      grams: _,
      pinned: _,
    ) when _rowOf(state.rows, row.resolved)?.skipped ?? true) {
      _fatTarget = null;
    }
    final target =
        _fatTarget ??
        switch (current == null && _fatPending == null
            ? cookingFatTargetIn(state.rows)
            : null) {
          (:final row, :final grams) => (
            row: row,
            grams: grams,
            pinned: _mealScale.isPinned(row),
          ),
          null => null,
        };
    if (choice < 0) {
      _fatClosed = true;
      _fatPending = null;
      notifyListeners();
      if (current != null) _bloc.add(PutRowEvent(current.resolved, null));
      if (_fatTarget case (:final row, grams: _, :final pinned)) {
        final now = _rowOf(state.rows, row.resolved)!;
        var back = now.copyWith(
          amountText: row.amountText,
          unit: row.unit,
          unitChosenByUser: row.unitChosenByUser,
          amountEditedByUser: row.amountEditedByUser,
        );
        if (!pinned) {
          // the Size's again, from the base it kept, at the size chosen now
          final bases = _mealScale.snapshot();
          _mealScale.setBase(back);
          final sized = _mealScale.restore([back], bases)[row.resolved];
          if (sized != null) back = back.copyWith(amountText: sized);
        }
        _bloc.add(PutRowEvent(row.resolved, back));
        _fatTarget = null;
      }
      return false;
    }
    if (target != null) {
      _fatTarget = target;
      _setFatTarget(_rowOf(state.rows, target.row.resolved)!, target, choice);
      return false;
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
      return false;
    }
    final looking = _fatPending != null;
    _fatPending = choice;
    notifyListeners();
    if (looking) return false;
    final read = _readSerial;
    ResolvedMealItem? found;
    try {
      found = await _cookingFatFood(grams);
    } catch (e, stackTrace) {
      _log.warning('Looking up the cooking fat failed', e, stackTrace);
    }
    if (_disposed || read != _readSerial) return false;
    final pending = _fatPending;
    _fatPending = null;
    notifyListeners();
    if (pending == null || _fatClosed) return false;
    if (found == null) return true;
    final row = _cookingFatRow(found, cookingFatGrams[pending]);
    _mealScale.pin(row);
    _fatItem = row.resolved;
    notifyListeners();
    _bloc.add(PutRowEvent(row.resolved, row));
    return false;
  }

  /// The read's own fat row at [choice]'s answer, in grams as the user's
  /// amount: the Size leaves it, and a photo's amount changed is learnt.
  void _setFatTarget(
    BulkAddRow row,
    ({BulkAddRow row, double grams, bool pinned}) target,
    int choice,
  ) {
    final grams = cookingFatAnswer(
      _fatAsk ?? CookingFatAsk.cooked,
      target.grams,
      choice,
    );
    final g = UnitDropdownItem.g.toString();
    final set = row.copyWith(
      amountText: cookingFatText(grams),
      unit: row.allowedUnits.contains(g) ? g : UnitDropdownItem.gml.toString(),
      unitChosenByUser: true,
      amountEditedByUser: true,
    );
    _mealScale.pin(set);
    notifyListeners();
    _bloc.add(PutRowEvent(row.resolved, set));
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

  bool _disposed = false;

  /// Quiet once disposed: the memory or the oil's lookup can finish after
  /// the screen has gone.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}
