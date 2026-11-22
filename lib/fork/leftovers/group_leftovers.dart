import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_photo_encoder.dart';
import 'package:opennutritracker/fork/add/chosen_chips.dart';
import 'package:opennutritracker/fork/leftovers/ai_leftovers.dart';
import 'package:opennutritracker/fork/leftovers/meal_groups.dart';
import 'package:opennutritracker/fork/leftovers/meal_photo_cache.dart';
import 'package:opennutritracker/fork/units/amount_text.dart';

/// English only, like the rest of the fork's strings.
abstract final class LeftoverStrings {
  /// Some of the reply fit no food, so a food may read as eaten up wrongly.
  static String unplaced(int count) =>
      "AI estimate: $count ${count == 1 ? 'item' : 'items'} didn't match a "
      'food. Check each amount.';

  static const title = 'Left over from the meal';
  static const hint = 'Pick what share is left, then adjust any item.';
  static const left = 'Left';
  static String leftOf(String food) => food.isEmpty ? left : 'Left of $food';
  static const save = 'Save';
  static const cancel = 'Cancel';
  static const readPhoto = "Photo of what's left";
  static const aiEstimate = 'AI estimate: check each amount before saving.';
  static const readFailed =
      "Couldn't read the photo. Try again or set the amounts yourself.";
}

/// The fractions offered, as in upstream's single-entry dialog.
const leftoverFractions = {'¼': 0.25, '⅓': 1 / 3, '½': 0.5, '¾': 0.75};

/// What each entry's amount becomes: its amount less [fraction] of it, or
/// less the amount left that [overrides] gives for it. An override above
/// the amount logged, or below zero, is ignored.
Map<String, double> amountsAfterLeftovers(
  List<IntakeEntity> intakes, {
  double fraction = 0,
  Map<String, double> overrides = const {},
}) => {
  for (final intake in intakes)
    intake.id: switch (overrides[intake.id]) {
      final left? when left >= 0 && left <= intake.amount =>
        intake.amount - left,
      _ => intake.amount * (1 - fraction),
    },
};

/// A meal group and those of its entries that still exist.
typedef MealGroupEntries = ({MealGroup group, List<IntakeEntity> members});

/// Seams S9 (diary) and S10 (home): the meal [intake] was logged as part
/// of, with its entries that still exist, or null when there is no meal of
/// two or more. The edit dialog offers the whole meal's leftovers on it.
Future<MealGroupEntries?> mealGroupEntriesOf(
  IntakeEntity intake, {
  MealGroupStore? store,
  Future<IntakeEntity?> Function(String id)? intakeById,
}) async {
  try {
    final group = await (store ?? MealGroupStore()).groupOf(intake.id);
    if (group == null) return null;
    final byId = intakeById ?? locator<GetIntakeUsecase>().getIntakeById;
    final members = [for (final id in group.intakeIds) ?await byId(id)];
    // Entries deleted since leave a group of one, which is just this entry.
    return members.length < 2 ? null : (group: group, members: members);
  } catch (e, stackTrace) {
    // Like S8: a failed lookup only loses the grouping, and the entry is
    // still edited on its own.
    Logger('MealGroups').warning('Reading a meal group failed', e, stackTrace);
    return null;
  }
}

/// Seams S9 (diary) and S10 (home): the leftovers of the whole [meal],
/// saved through [update] for each entry whose amount changed.
Future<void> editWholeMealLeftovers(
  BuildContext context,
  MealGroupEntries meal, {
  required Future<void> Function(String intakeId, double amount) update,
  ReadLeftoversUseCase? leftovers,
  MealPhotoCache? photoCache,
  bool usesImperialUnits = false,
  Future<MealPhoto?> Function(AiSelection selection)? takePhoto,
}) async {
  final (:group, :members) = meal;
  final reader =
      leftovers ?? ReadLeftoversUseCase(locator(), locator<http.Client>());
  final selection = await reader.selection;
  if (!context.mounted) return;
  final amounts = await showDialog<Map<String, double>>(
    context: context,
    builder: (_) => GroupLeftoversDialog(
      intakes: members,
      usesImperialUnits: usesImperialUnits,
      readLeftoverPhoto: selection == null
          ? null
          : () async {
              final photo = await (takePhoto ?? _takePhoto)(selection);
              if (photo == null) return null;
              return reader.read(
                members,
                photo,
                meal: await (photoCache ?? MealPhotoCache()).read(
                  group.photoPath,
                ),
              );
            },
    ),
  );
  if (amounts == null) return;
  for (final member in members) {
    final amount = amounts[member.id]!;
    // Sequential: the day totals are a read-modify-write.
    if (amount != member.amount) await update(member.id, amount);
  }
}

/// The camera, encoded as a meal photo is for the same destination; null
/// when the user backs out.
Future<MealPhoto?> _takePhoto(AiSelection selection) async {
  final picked = await ImagePicker().pickImage(source: ImageSource.camera);
  if (picked == null) return null;
  return MealPhotoEncoder.encodeAndDiscardSource(
    picked.path,
    format: MealPhotoFormat.forProvider(selection.provider),
  );
}

class GroupLeftoversDialog extends StatefulWidget {
  final List<IntakeEntity> intakes;

  /// Reads a photo of the leftovers into the amount left of each entry,
  /// or null when none was taken. Absent when no model is set up.
  final Future<LeftoversReading?> Function()? readLeftoverPhoto;
  final bool usesImperialUnits;

  const GroupLeftoversDialog({
    super.key,
    required this.intakes,
    this.readLeftoverPhoto,
    this.usesImperialUnits = false,
  });

  @override
  State<GroupLeftoversDialog> createState() => _GroupLeftoversDialogState();
}

class _GroupLeftoversDialogState extends State<GroupLeftoversDialog> {
  static final _log = Logger('GroupLeftoversDialog');

  double _fraction = 0;
  bool _reading = false;
  String? _photoNote;
  final _overrides = <String, double>{};
  late final _shown = {
    for (final intake in widget.intakes)
      intake.id: shownUnit(intake, widget.usesImperialUnits),
  };
  late final _controllers = {
    for (final intake in widget.intakes) intake.id: TextEditingController(),
  };

  Map<String, double> get _amounts => amountsAfterLeftovers(
    widget.intakes,
    fraction: _fraction,
    overrides: _overrides,
  );

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _pickFraction(double fraction) => setState(() {
    _fraction = fraction;
    _overrides.clear();
    for (final intake in widget.intakes) {
      _controllers[intake.id]!.text = _formatShown(
        intake.id,
        intake.amount * fraction,
      );
    }
  });

  Future<void> _readPhoto() async {
    setState(() {
      _reading = true;
      _photoNote = null;
    });
    String? note;
    try {
      final reading = await widget.readLeftoverPhoto!();
      if (reading != null) {
        final left = reading.left;
        // An entry the model left out has nothing left.
        _fraction = 0;
        _overrides
          ..clear()
          ..addAll({for (final i in widget.intakes) i.id: left[i.id] ?? 0});
        for (final intake in widget.intakes) {
          _controllers[intake.id]!.text = _formatShown(
            intake.id,
            _overrides[intake.id]!,
          );
        }
        note = reading.unplaced > 0
            ? LeftoverStrings.unplaced(reading.unplaced)
            : LeftoverStrings.aiEstimate;
      }
    } catch (e, stackTrace) {
      _log.warning('Reading a leftovers photo failed', e, stackTrace);
      note = LeftoverStrings.readFailed;
    }
    if (!mounted) return;
    setState(() {
      _reading = false;
      _photoNote = note;
    });
  }

  void _override(String id, String text) => setState(() {
    final left = double.tryParse(text.replaceAll(',', '.'));
    if (left == null || !left.isFinite) {
      _overrides.remove(id);
    } else {
      _overrides[id] = left / _shown[id]!.factor;
    }
  });

  String _formatShown(String id, double amount) =>
      _format(amount * _shown[id]!.factor);

  static String _format(double value) => value == value.roundToDouble()
      ? '${value.toInt()}'
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final amounts = _amounts;
    return AlertDialog(
      title: const Text(LeftoverStrings.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(LeftoverStrings.hint),
            if (widget.readLeftoverPhoto != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _reading ? null : _readPhoto,
                icon: _reading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_rounded),
                label: const Text(LeftoverStrings.readPhoto),
              ),
            ],
            if (_photoNote case final note?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  note,
                  // light tertiary is under 4.5:1 as text
                  style: TextStyle(color: paletteOf(context).warningText),
                ),
              ),
            const SizedBox(height: 8),
            // the chosen fraction in the accent; the theme's fill was the rest's
            chosenChips(
              context,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final MapEntry(key: label, value: fraction)
                      in leftoverFractions.entries)
                    ChoiceChip(
                      label: Text(label),
                      selected: _fraction == fraction,
                      onSelected: _reading
                          ? null
                          : (_) => _pickFraction(fraction),
                    ),
                ],
              ),
            ),
            for (final intake in widget.intakes)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            intake.meal.name ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_formatShown(intake.id, intake.amount)} '
                            '${_shown[intake.id]!.unit} → '
                            '${_formatShown(intake.id, amounts[intake.id]!)} '
                            '${_shown[intake.id]!.unit}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 112,
                      child: TextField(
                        key: ValueKey('left-${intake.id}'),
                        controller: _controllers[intake.id],
                        // A reply would replace what is typed while it comes.
                        enabled: !_reading,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (text) => _override(intake.id, text),
                        decoration: InputDecoration(
                          isDense: true,
                          // Shown short beside the name, said with it.
                          label: Semantics(
                            label: LeftoverStrings.leftOf(
                              intake.meal.name ?? '',
                            ),
                            excludeSemantics: true,
                            child: const Text(LeftoverStrings.left),
                          ),
                          hintText: '0',
                          suffixText: _shown[intake.id]!.unit,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(LeftoverStrings.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, amounts),
          child: const Text(LeftoverStrings.save),
        ),
      ],
    );
  }
}
