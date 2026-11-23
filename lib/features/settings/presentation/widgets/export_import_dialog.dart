import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/domain/usecase/export_data_usecase.dart';
// [fork] S413 import-confirm
import 'package:opennutritracker/features/settings/domain/usecase/import_data_usecase.dart';
// [/fork]
import 'package:opennutritracker/features/settings/presentation/bloc/export_import_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/export_import_error_text.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
// [fork] S38 restore-settings-live: import
import 'package:opennutritracker/fork/backup/after_restore.dart';
// [/fork]
// [fork] S511 import-replace-destructive: Replace loses data, so it is drawn
// as the other destructive confirms
import 'package:opennutritracker/fork/recipe/recipe_delete.dart'
    show destructiveFilledStyle;
// [/fork]
import 'package:opennutritracker/generated/l10n.dart';

/// Export / Import App Data dialog. A SegmentedButton at the top picks
/// which format the user is working with — JSON (the canonical
/// backup-and-restore format the app round-trips through) or CSV (a
/// spreadsheet-friendly view).
///
/// Both segments support Export and Import. The asymmetry is that CSV
/// export omits recipes (the nested-ingredient shape doesn't flatten
/// cleanly) and CSV import therefore doesn't restore recipes either —
/// a user who wants their recipes in a backup should pick JSON.
class ExportImportDialog extends StatefulWidget {
  const ExportImportDialog({super.key});

  @override
  State<ExportImportDialog> createState() => _ExportImportDialogState();
}

class _ExportImportDialogState extends State<ExportImportDialog> {
  final _exportImportBloc = locator<ExportImportBloc>();
  final _homeBloc = locator<HomeBloc>();
  final _diaryBloc = locator<DiaryBloc>();
  final _calendarDayBloc = locator<CalendarDayBloc>();

  ExportFormat _exportFormat = ExportFormat.json;

  // [fork] S413 import-confirm: a picked file is confirmed before it
  // replaces anything, since at 200% the warning can be off screen
  ImportDataUsecase? get _forkImporter =>
      locator.isRegistered<ImportDataUsecase>()
      ? locator<ImportDataUsecase>()
      : null;

  @override
  void initState() {
    super.initState();
    _forkImporter?.forkConfirmImport = _forkConfirmImport;
  }

  @override
  void dispose() {
    final importer = _forkImporter;
    if (importer?.forkConfirmImport == _forkConfirmImport) {
      importer!.forkConfirmImport = null;
    }
    super.dispose();
  }

  Future<bool> _forkConfirmImport() async {
    if (!mounted) return false;
    // A CSV backup holds no goal settings
    final goals = _exportFormat == ExportFormat.json;
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          goals
              ? 'Replace your goals and the entries this file shares?'
              : 'Replace the entries this file shares?',
        ),
        content: const Text(
          'Entries in the file overwrite the same ones here. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(S.of(context).dialogCancelLabel),
          ),
          FilledButton(
            style: destructiveFilledStyle(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    return mounted && replace == true;
  }
  // [/fork]

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.of(context).exportImportAppDataLabel,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
      // [fork] S315 export-dialog-scrolls: at 200% text the warning ran under
      // the buttons. Not `scrollable: true`: its IntrinsicWidth cannot
      // measure the SegmentedButton and throws
      // content: Wrap(
      content: SingleChildScrollView(
        child: Wrap(
      // [/fork]
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<ExportFormat>(
                segments: const [
                  ButtonSegment(
                    value: ExportFormat.json,
                    label: Text('JSON'),
                  ),
                  ButtonSegment(
                    value: ExportFormat.csv,
                    // [fork] S414 csv-backup-words: a backup to restore, not
                    // the diary's CSV export one row above in Settings
                    // label: Text('CSV'),
                    label: Text('CSV backup'),
                    // [/fork]
                  ),
                ],
                selected: {_exportFormat},
                onSelectionChanged: (next) {
                  // [fork] S580 import-refresh-once: its reset mid-run would
                  // drop the running import's reload
                  if (_exportImportBloc.state is ExportImportLoadingState) {
                    return;
                  }
                  // [/fork]
                  setState(() => _exportFormat = next.first);
                  // Clear any success/error chrome left over from a
                  // previous export so the description re-appears under
                  // the new format selection.
                  _exportImportBloc.add(ResetExportImportStateEvent());
                },
              ),
              if (_exportFormat == ExportFormat.csv) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        S.of(context).exportImportCsvRecipesNote,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              // [fork] S414 csv-backup-words: the accent was
                              // 4.0:1 at this size; the icon keeps it
                              // color: Theme.of(context).colorScheme.secondary,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              // [/fork]
                            ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              BlocBuilder<ExportImportBloc, ExportImportState>(
                bloc: _exportImportBloc,
                builder: (context, state) {
                  if (state is ExportImportInitial) {
                    // [fork] S142 import-says: what a backup holds; what an
                    // import replaces is asked once the file is picked
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // What the two formats hold, and how this backup
                        // differs from the diary's CSV export (G6-7)
                        // Text(
                        //   S.of(context).exportImportDescription,
                        //   overflow: TextOverflow.ellipsis,
                        //   maxLines: 15,
                        // ),
                        const Text(
                          'Export saves a backup to import here or on another '
                          'phone. A CSV backup leaves out recipes; for a '
                          'spreadsheet, use Export diary as CSV.\n\nNothing '
                          'is kept in a cloud.',
                        ),
                      ],
                    );
                    // [/fork]
                  } else if (state is ExportImportLoadingState) {
                    return const LinearProgressIndicator();
                  } else if (state is ExportImportSuccess) {
                    // [fork] S580 import-refresh-once: reloads from
                    // _forkImport, once per import, not on each build
                    // refreshScreens();
                    // [/fork]
                    return Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(S.of(context).exportImportSuccessLabel),
                        ),
                      ],
                    );
                  } else if (state is ExportImportError) {
                    return Row(
                      children: [
                        Icon(
                          Icons.error,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            exportImportErrorText(
                              S.of(context),
                              state.reason,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ],
      // [fork] S315 export-dialog-scrolls
      ),
      // [/fork]
      ),
      actions: <Widget>[
        // [fork] S315 export-dialog-scrolls: an exit that does neither;
        // Close once one has finished (S580)
        _forkWatch(
          (state) => TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              state is ExportImportSuccess
                  ? 'Close'
                  : S.of(context).dialogCancelLabel,
            ),
          ),
        ),
        // [/fork]
        // [fork] S580 import-refresh-once: no second run while one runs; an
        // import reloads the screens when it ends
        // TextButton(
        //   onPressed: () => _exportImportBloc.add(
        //     ExportDataEvent(format: _exportFormat),
        //   ),
        //   child: Text(S.of(context).exportAction),
        // ),
        // TextButton(
        //   onPressed: () => _exportImportBloc.add(
        //     ImportDataEvent(format: _exportFormat),
        //   ),
        //   child: Text(S.of(context).importAction),
        // ),
        _forkWatch(
          (state) => TextButton(
            onPressed: state is ExportImportLoadingState
                ? null
                : () => _exportImportBloc.add(
                    ExportDataEvent(format: _exportFormat),
                  ),
            child: Text(S.of(context).exportAction),
          ),
        ),
        _forkWatch(
          (state) => TextButton(
            onPressed: state is ExportImportLoadingState ? null : _forkImport,
            child: Text(S.of(context).importAction),
          ),
        ),
        // [/fork]
      ],
    );
  }

  // [fork] S580 import-refresh-once
  Widget _forkWatch(Widget Function(ExportImportState state) build) =>
      BlocBuilder<ExportImportBloc, ExportImportState>(
        bloc: _exportImportBloc,
        builder: (context, state) => build(state),
      );

  /// Starts an import and reloads the screens when it succeeds, also when
  /// the dialog was closed while it ran: the app's context, not this one.
  void _forkImport() {
    final appContext = Navigator.of(context, rootNavigator: true).context;
    final ended = _exportImportBloc.stream.firstWhere(
      (state) => state is! ExportImportLoadingState,
    );
    _exportImportBloc.add(ImportDataEvent(format: _exportFormat));
    ended.then(
      (state) {
        if (state is ExportImportSuccess && appContext.mounted) {
          refreshScreens(appContext);
        }
      },
      // The bloc closed first: nothing finished, nothing to reload
      onError: (Object _) {},
    );
  }
  // [/fork]

  // [fork] S580 import-refresh-once: the context outlives the dialog
  // void refreshScreens() {
  void refreshScreens(BuildContext context) {
  // [/fork]
    _homeBloc.add(const LoadItemsEvent());
    _diaryBloc.add(const LoadDiaryYearEvent());
    _calendarDayBloc.add(RefreshCalendarDayEvent());
    // A restore can replace the goal settings (#1363): the Settings
    // dialogs, the Profile water goal and Trends' goal lines read them
    // from blocs that keep their loaded state until told to reload.
    locator<SettingsBloc>().add(LoadSettingsEvent());
    locator<ProfileBloc>().add(LoadProfileEvent());
    final trendsBloc = locator<TrendsBloc>();
    final trendsState = trendsBloc.state;
    if (trendsState is TrendsLoaded) {
      trendsBloc.add(LoadTrendsEvent(rangeDays: trendsState.rangeDays));
    }
    // [fork] S38 restore-settings-live: theme, units and language now
    afterRestore(context);
    // [/fork]
  }
}
