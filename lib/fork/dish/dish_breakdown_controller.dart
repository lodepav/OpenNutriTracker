import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/fork/dish/break_down_dish_usecase.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';

enum DishBreakdownOutcome { replaced, empty, noModel, failed }

/// Runs breakdowns for the review screen (phase 1c.2): automatically for a
/// row the model named but nothing matched, and on demand for a doubtful
/// one. Owns the in-flight set the rows show a progress line for; the swap
/// itself is a bloc event, so it lands in the same state stream as every
/// other edit.
class DishBreakdownController extends ChangeNotifier {
  static final _log = Logger('DishBreakdownController');

  final BulkAddBloc _bloc;
  final Future<DishBreakdown?> Function(String dish) _breakDown;
  final Future<bool> Function() _modelConfigured;
  late final StreamSubscription<BulkAddState> _subscription;

  final _pending = Set<ResolvedMealItem>.identity();
  final _tried = Set<ResolvedMealItem>.identity();
  bool _modelReady = false;

  DishBreakdownController(
    this._bloc, {
    Future<DishBreakdown?> Function(String dish)? breakDown,
    Future<bool> Function()? modelConfigured,
  }) : _breakDown =
           breakDown ?? ((dish) => BreakDownDishUseCase.fromLocator()(dish)),
       _modelConfigured = modelConfigured ?? _modelSelected {
    _subscription = _bloc.stream.listen(_onState);
    _modelConfigured().then((ready) {
      if (_disposed) return;
      _modelReady = ready;
      notifyListeners();
      // Built lazily by the screen, possibly after the rows arrived.
      _onState(_bloc.state);
    });
  }

  /// Read through the locator only when it holds the storage: upstream's
  /// screen tests build the screen without it.
  static Future<bool> _modelSelected() async =>
      locator.isRegistered<AiCredentialStorage>() &&
      await locator<AiCredentialStorage>().readSelection() != null;

  bool isPending(BulkAddRow row) => _pending.contains(row.resolved);

  /// Whether to offer "Break into ingredients" on [row]: a model is set up,
  /// the row is not an ingredient already, and nothing matched or only
  /// weakly. A confident match stays one food, a product included: a
  /// "mozzarella" that found a mozzarella is not a dish.
  bool canBreakDown(BulkAddRow row) =>
      _modelReady &&
      row.dishIngredient == null &&
      !isPending(row) &&
      (!row.isResolved || row.isLowConfidence);

  Future<DishBreakdownOutcome> breakDown(BulkAddRow row) async {
    final target = row.resolved;
    if (!_pending.add(target)) return DishBreakdownOutcome.empty;
    _tried.add(target);
    notifyListeners();
    try {
      final breakdown = await _breakDown(target.parsed.query);
      if (breakdown == null) return DishBreakdownOutcome.noModel;
      if (breakdown.ingredients.isEmpty) return DishBreakdownOutcome.empty;
      if (!_bloc.isClosed) {
        _bloc.add(ReplaceRowWithBreakdownEvent(target, breakdown));
      }
      return DishBreakdownOutcome.replaced;
    } on MealInterpreterException catch (e) {
      _log.info('Breakdown unavailable: ${e.reason}');
      return DishBreakdownOutcome.failed;
    } catch (e, stackTrace) {
      // A row the user can still log by hand is worth more than the
      // breakdown: never let it take the screen down.
      _log.warning('Breakdown failed', e, stackTrace);
      return DishBreakdownOutcome.failed;
    } finally {
      _pending.remove(target);
      notifyListeners();
    }
  }

  /// A model read named a food the tables lack: break it down once, without
  /// being asked. Not for the parser's rows: there the model was not used,
  /// or failed, and asking it again per row would repeat that.
  void _onState(BulkAddState state) {
    if (state is! BulkAddLoadedState || !_modelReady) return;
    if (state.source == BulkAddReadSource.parser) return;
    for (final row in state.rows) {
      if (!row.isResolved &&
          row.dishIngredient == null &&
          !_tried.contains(row.resolved)) {
        breakDown(row);
      }
    }
  }

  bool _disposed = false;

  /// Quiet once disposed: a breakdown or the model check can finish after
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
