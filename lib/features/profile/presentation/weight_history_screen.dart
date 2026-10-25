import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/reload_diary_and_trends.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/body_weight_input.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S113 weigh-in-delete
import 'package:opennutritracker/fork/health/weight_import_ui.dart';
import 'package:opennutritracker/fork/weight/weight_history_view.dart'; // S122 weight-history
// [/fork]

/// Screen for browsing and adding weight log entries.
///
/// Renders a 30-day trend chart above the date-sorted list of readings.
/// The list remains the source of truth — the chart is a complementary
/// visualisation. When the user has logged fewer than two days the chart
/// area gives way to a gentle nudge to log more data, because a single
/// point doesn't yet describe a trend.
///
/// Dependencies are resolved from the locator by default; the optional
/// constructor parameters exist so widget tests can inject fakes without
/// standing up the whole DI graph.
class WeightHistoryScreen extends StatefulWidget {
  final GetWeightLogUsecase? getUsecase;
  final AddWeightLogUsecase? addUsecase;
  final DeleteWeightLogUsecase? deleteUsecase;
  final ConfigRepository? configRepository;
  final GetUserUsecase? getUserUsecase;

  const WeightHistoryScreen({
    super.key,
    this.getUsecase,
    this.addUsecase,
    this.deleteUsecase,
    this.configRepository,
    this.getUserUsecase,
  });

  @override
  State<WeightHistoryScreen> createState() => _WeightHistoryScreenState();
}

class _WeightHistoryScreenState extends State<WeightHistoryScreen> {
  late final GetWeightLogUsecase _getUsecase =
      widget.getUsecase ?? locator<GetWeightLogUsecase>();
  late final AddWeightLogUsecase _addUsecase =
      widget.addUsecase ?? locator<AddWeightLogUsecase>();
  late final DeleteWeightLogUsecase _deleteUsecase =
      widget.deleteUsecase ?? locator<DeleteWeightLogUsecase>();
  late final ConfigRepository _configRepository =
      widget.configRepository ?? locator<ConfigRepository>();
  // Optional in tests so the harness doesn't need to register the
  // user usecase in the locator just to render the chart.
  late final GetUserUsecase? _getUserUsecase =
      widget.getUserUsecase ??
      (locator.isRegistered<GetUserUsecase>()
          ? locator<GetUserUsecase>()
          : null);

  bool _loading = true;
  BodyWeightUnit _bodyWeightUnit = BodyWeightUnit.kg;
  List<WeightLogEntity> _entries = const [];
  // Loaded once at mount time so the chart can draw a dashed reference
  // line for the user's #119 target weight. Null when unset.
  double? _targetWeightKg;
  // The profile's current weight, which Add entry starts from (#1367).
  double? _profileWeightKg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await _configRepository.getConfig();
    final unit = config.bodyWeightUnit;
    final entries = await _getUsecase.getAllEntries();
    // Newest first so the most recent reading sits at the top.
    entries.sort((a, b) => b.date.compareTo(a.date));
    final user = await _getUserUsecase?.getUserData();
    if (!mounted) return;
    setState(() {
      _bodyWeightUnit = unit;
      _entries = entries;
      _targetWeightKg = user?.targetWeightKg;
      _profileWeightKg = user?.weightKG;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // [fork] S122 weight-history: MacroFactor's (WeightB): range chips, the
    // trend over the weigh-ins, three stats, each weigh-in's change, swipe
    // to delete and a Weigh in button (upstream: a 30d-365d selector, the
    // dotted chart, a list with a bin on each row and a FAB).
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(S.of(context).profileWeightHistoryTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return WeightHistoryView(
      entries: _entries,
      unit: _bodyWeightUnit,
      targetWeightKg: _targetWeightKg,
      onAdd: _onAddEntry,
      onDelete: _onDelete,
    );
    // [/fork]
  }

  Future<void> _onAddEntry() async {
    // The profile weight is the current one: a reading for today updates
    // it, and so does editing it on the profile. A fixed 70 kg here
    // contradicted the profile on every log that had no entries (#1367).
    final initialWeightKg =
        _profileWeightKg ??
        (_entries.isNotEmpty ? _entries.first.weightKg : 70.0);
    final result = await showDialog<_NewWeightEntry>(
      context: context,
      builder: (context) => _AddWeightEntryDialog(
        initialDate: DateTime.now(),
        initialWeightKg: initialWeightKg,
        bodyWeightUnit: _bodyWeightUnit,
      ),
    );
    if (result == null) return;

    await _addUsecase.addEntry(
      WeightLogEntity(
        date: DateTime(result.date.year, result.date.month, result.date.day),
        weightKg: result.weightKg,
        note: result.note,
      ),
    );
    await _load();
    reloadDiaryAndTrends();
    refreshAfterWeightImport(); // [fork] S113: today's sets the weight
  }

  Future<void> _onDelete(WeightLogEntity entry) async {
    await _deleteUsecase.deleteEntry(entry);
    await _load();
    reloadDiaryAndTrends();
    // [fork] S113 weigh-in-delete: Home and the profile show the weight
    // the delete set. A tap deletes at once, so it can be undone; adding
    // it back sets today's profile weight again too
    refreshAfterWeightImport();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // Goes after its time, as the food undo's; an action alone
          // would keep it up on every screen.
          persist: false,
          content: const Text('Weigh-in deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await _addUsecase.addEntry(entry);
              await _load();
              reloadDiaryAndTrends();
              refreshAfterWeightImport();
            },
          ),
        ),
      );
    // [/fork]
  }
}

class _NewWeightEntry {
  final DateTime date;
  final double weightKg;
  final String? note;

  _NewWeightEntry({required this.date, required this.weightKg, this.note});
}

class _AddWeightEntryDialog extends StatefulWidget {
  final DateTime initialDate;
  final double initialWeightKg;
  final BodyWeightUnit bodyWeightUnit;

  const _AddWeightEntryDialog({
    required this.initialDate,
    required this.initialWeightKg,
    required this.bodyWeightUnit,
  });

  @override
  State<_AddWeightEntryDialog> createState() => _AddWeightEntryDialogState();
}

class _AddWeightEntryDialogState extends State<_AddWeightEntryDialog> {
  late DateTime _date;
  late TextEditingController _noteController;

  // The kg value from BodyWeightInput; null means invalid / empty.
  double? _weightKg;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _weightKg = widget.initialWeightKg;
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  void _submit() {
    final kg = _weightKg;
    if (kg == null || kg <= 0) {
      Navigator.of(context).pop();
      return;
    }
    final note = _noteController.text.trim();
    Navigator.of(context).pop(
      _NewWeightEntry(
        date: _date,
        weightKg: kg,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(_date);

    return AlertDialog(
      title: Text(S.of(context).weightHistoryAddEntry),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(S.of(context).weightHistoryDateLabel),
              subtitle: Text(dateLabel),
              onTap: _pickDate,
            ),
            BodyWeightInput(
              initialKg: widget.initialWeightKg,
              unit: widget.bodyWeightUnit,
              identifierPrefix: 'weight-history',
              autofocus: true,
              onChangedKg: (kg) => setState(() => _weightKg = kg),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: S.of(context).weightHistoryNoteLabel,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).dialogCancelLabel),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(S.of(context).dialogOKLabel),
        ),
      ],
    );
  }
}

