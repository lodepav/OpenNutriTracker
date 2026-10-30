import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/fork/units/amount_text.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The Diary's entries picked to copy, move or delete together, on the
/// Diary's own rows (seam S177), in place of a screen of their own. On
/// while [active], with none picked yet when started from the date's
/// "Select" button; the Diary ends it when the day changes.
class DiarySelection extends ChangeNotifier {
  static final instance = DiarySelection();

  final _picked = <String, IntakeEntity>{};
  var _active = false;

  bool get active => _active;
  List<IntakeEntity> get picked => [..._picked.values];
  int get count => _picked.length;

  bool isPicked(IntakeEntity intake) => _picked.containsKey(intake.id);

  /// Starts selecting, with [intake] picked when given.
  void start([IntakeEntity? intake]) {
    _active = true;
    if (intake != null) _picked[intake.id] = intake;
    notifyListeners();
  }

  void toggle(IntakeEntity intake) => setAll([intake], !isPicked(intake));

  void setAll(Iterable<IntakeEntity> intakes, bool on) {
    for (final intake in intakes) {
      on ? _picked[intake.id] = intake : _picked.remove(intake.id);
    }
    notifyListeners();
  }

  /// All of [intakes] picked (true), some (null) or none (false).
  bool? stateOf(Iterable<IntakeEntity> intakes) {
    final picked = intakes.where(isPicked).length;
    if (picked == 0) return false;
    return picked == intakes.length ? true : null;
  }

  void end() {
    if (!_active) return;
    _active = false;
    _picked.clear();
    notifyListeners();
  }
}

/// The bar under the Diary while selecting: how many, and Copy, Move and
/// Delete for them all.
class DiarySelectionBar extends StatelessWidget {
  final DiarySelection selection;

  /// The logical day the entries are listed under.
  final DateTime day;
  final void Function(IntakeEntity intake, DateTime day) onDelete;

  const DiarySelectionBar({
    super.key,
    required this.selection,
    required this.day,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: selection,
    builder: (context, _) {
      if (!selection.active) return const SizedBox.shrink();
      final count = selection.count;
      void act(void Function(List<IntakeEntity>) action) {
        final picked = selection.picked;
        selection.end();
        action(picked);
      }

      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          // clear of the add button that sits over the navigation bar
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 32),
          child: Row(
            children: [
              IconButton(
                key: const Key('fork-selection-end'),
                tooltip: 'Stop selecting',
                icon: const Icon(Icons.close_rounded),
                onPressed: selection.end,
              ),
              Expanded(
                child: Text(
                  count == 0 ? 'Tap foods' : '$count selected',
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final (key, label, icon, action) in [
                (
                  'copy',
                  'Copy',
                  Icons.copy_rounded,
                  (List<IntakeEntity> picked) =>
                      copyOrMoveIntakes(context, picked, from: day),
                ),
                (
                  'move',
                  'Move',
                  Icons.drive_file_move_outline,
                  (List<IntakeEntity> picked) =>
                      copyOrMoveIntakes(context, picked, from: day, move: true),
                ),
                (
                  'delete',
                  S.of(context).dialogDeleteLabel,
                  Icons.delete_outline_rounded,
                  (List<IntakeEntity> picked) {
                    for (final intake in picked) {
                      onDelete(intake, day);
                    }
                  },
                ),
              ])
                IconButton(
                  key: Key('fork-selection-$key'),
                  tooltip: label,
                  icon: Icon(icon),
                  onPressed: count == 0 ? null : () => act(action),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// A long-pressed food's actions (seam S24): its meal as chips, one tap
/// moving it there at the same time, then copy or move it anywhere, start
/// selecting with it, or delete it.
Future<void> showEntryActions(
  BuildContext context,
  IntakeEntity intake,
  DateTime day, {
  required bool usesImperialUnits,
  required void Function(IntakeEntity intake, DateTime day) onDelete,
  DiarySelection? selection,
}) async {
  final action = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) {
      final textTheme = Theme.of(sheet).textTheme;
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  intake.meal.name ?? '?',
                  style: textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                child: Text(
                  '${amountText(intake, usesImperialUnits)} · '
                  '${EnergyDisplay.formatWithUnit(sheet, intake.totalKcal)}',
                  style: textTheme.bodyMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Meal', style: textTheme.titleSmall),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final meal in IntakeTypeEntity.values)
                      ChoiceChip(
                        key: Key('fork-entry-meal-${meal.name}'),
                        label: Text(mealLabel(sheet, meal)),
                        selected: meal == intake.type,
                        // the current one stays as it is, but reads as on
                        onSelected: (_) => meal == intake.type
                            ? null
                            : Navigator.of(sheet).pop(meal),
                      ),
                  ],
                ),
              ),
              const Divider(),
              for (final (key, icon, label) in [
                ('copy', Icons.copy_rounded, 'Copy to…'),
                ('move', Icons.drive_file_move_outline, 'Move to…'),
                if (selection != null)
                  ('select', Icons.checklist_rounded, 'Select more'),
                (
                  'delete',
                  Icons.delete_outline_rounded,
                  S.of(sheet).dialogDeleteLabel,
                ),
              ])
                ListTile(
                  key: Key('fork-entry-$key'),
                  leading: Icon(icon),
                  title: Text(label),
                  onTap: () => Navigator.of(sheet).pop(key),
                ),
            ],
          ),
        ),
      );
    },
  );
  // The delete asks nothing more, so it goes ahead even when the Diary
  // moved on while the sheet was open (#1360); the Diary shows the Undo.
  if (action == 'delete') return onDelete(intake, day);
  if (action == 'select') return selection?.start(intake);
  if (!context.mounted) return;
  switch (action) {
    case final IntakeTypeEntity meal:
      await moveToMeal(context, intake, day, meal);
    case 'copy':
      await copyOrMoveIntakes(context, [intake], from: day);
    case 'move':
      await copyOrMoveIntakes(context, [intake], from: day, move: true);
  }
}
