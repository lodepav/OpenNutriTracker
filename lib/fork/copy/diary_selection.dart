import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The Diary's entries picked to copy, move or delete together, on the
/// Diary's own rows (seam S177), in place of a screen of their own. On
/// while [active]: a tap on a food or a section starts it with those picked,
/// the date's "Select" button with none, and taking the last one back ends
/// it, so a stray tap costs one more tap. The Diary ends it when the day
/// changes.
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

  /// Picks all of [intakes], or takes them back when all are picked.
  void toggleAll(Iterable<IntakeEntity> intakes) {
    final on = stateOf(intakes) != true;
    for (final intake in intakes) {
      on ? _picked[intake.id] = intake : _picked.remove(intake.id);
    }
    _active = _picked.isNotEmpty;
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

/// The bar under the Diary while selecting: how many, Copy, Move and Delete
/// for them all, and Edit for one, the tap path beside a food's long-press.
class DiarySelectionBar extends StatelessWidget {
  final DiarySelection selection;

  /// The logical day the entries are listed under.
  final DateTime day;
  final void Function(IntakeEntity intake, DateTime day) onDelete;
  final void Function(BuildContext context, IntakeEntity intake) onEdit;

  const DiarySelectionBar({
    super.key,
    required this.selection,
    required this.day,
    required this.onDelete,
    required this.onEdit,
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
                if (count == 1)
                  (
                    'edit',
                    'Edit',
                    Icons.edit_outlined,
                    (List<IntakeEntity> picked) =>
                        onEdit(context, picked.single),
                  ),
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
