// Export / import after the round-3 settings critique (2026-11-21, G6):
// the overwrite sentence comes first and is on screen at 200% without
// scrolling, a picked file is confirmed before it replaces anything, the
// CSV note is in body text colour, and the CSV option says it is a backup.
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/data/data_source/custom_activity_template_data_source.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/favourite_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/data_source/tracked_day_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_data_source.dart';
import 'package:opennutritracker/core/data/data_source/weight_log_data_source.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/custom_activity_template_repository.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/settings/domain/export_import_failure.dart';
import 'package:opennutritracker/features/settings/domain/usecase/export_data_usecase.dart';
import 'package:opennutritracker/features/settings/domain/usecase/import_data_usecase.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/export_import_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/export_import_dialog.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

class _IdleExportImportBloc extends Fake implements ExportImportBloc {
  @override
  ExportImportState get state => ExportImportInitial();

  @override
  Stream<ExportImportState> get stream =>
      const Stream<ExportImportState>.empty();

  /// The import the dialog's Import button started, through the
  /// registered usecase as the real bloc's handler runs it.
  Future<bool>? started;

  @override
  void add(ExportImportEvent event) {
    if (event is! ImportDataEvent) return;
    final usecase = locator<ImportDataUsecase>();
    started = event.format == ExportFormat.csv
        ? usecase.importDataCsv()
        : _importJson(usecase);
    // Read by the test once the dialog has answered; not an uncaught error
    started!.ignore();
  }
}

class _HomeBloc extends Fake implements HomeBloc {}

class _DiaryBloc extends Fake implements DiaryBloc {}

class _CalendarDayBloc extends Fake implements CalendarDayBloc {}

/// A pick whose path is derived from its URI by [PlatformFile] itself.
final class _PickedFile extends PlatformFile {
  _PickedFile(String path) : uri = Uri.file(path);

  @override
  final Uri uri;

  @override
  String get name => 'backup.zip';

  @override
  Never get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => null;

  @override
  Future<int> length() => File(path!).length();

  @override
  Future<Uint8List> readAsBytes() => File(path!).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() => File(path!).openRead().cast();
}

/// Real repositories over a box-less provider: one that is written to
/// throws, so a declined import that wrote anything fails the test.
ImportDataUsecase _usecase(Future<PlatformFile?> Function() pickFile) {
  final provider = FakeHiveDBProvider();
  return ImportDataUsecase(
    UserActivityRepository(UserActivityDataSource(provider)),
    IntakeRepository(IntakeDataSource(provider)),
    TrackedDayRepository(TrackedDayDataSource(provider)),
    RecipeRepository(RecipeDataSource(provider)),
    WeightLogRepository(WeightLogDataSource(provider)),
    CustomActivityTemplateRepository(
      CustomActivityTemplateDataSource(provider),
    ),
    ConfigRepository(ConfigDataSource(provider)),
    FavouriteMealRepository(
      FavouriteMealDataSource(provider),
      CustomMealDataSource(provider),
      RecipeDataSource(provider),
    ),
    pickFile: pickFile,
  );
}

Future<bool> _importJson(ImportDataUsecase usecase) => usecase.importData(
  ExportImportBloc.userActivityJsonFileName,
  ExportImportBloc.userIntakeJsonFileName,
  ExportImportBloc.trackedDayJsonFileName,
  ExportImportBloc.recipeJsonFileName,
  ExportImportBloc.weightLogJsonFileName,
  ExportImportBloc.customActivityTemplateJsonFileName,
);

Matcher _failsWith(ExportImportFailureReason reason) => throwsA(
  isA<ExportImportFailure>().having((f) => f.reason, 'reason', reason),
);

const _description =
    'Export saves a backup to import here or on another phone. A CSV backup '
    'leaves out recipes; for a spreadsheet, use Export diary as CSV.\n\n'
    'Nothing is kept in a cloud.';

void main() {
  group('the import usecase', () {
    test('a declined file is a cancel, before anything is read or written',
        () async {
      var asked = 0;
      final usecase = _usecase(
        () async => _PickedFile('/no/such/backup.zip'),
      )..forkConfirmImport = () async {
          asked++;
          return false;
        };

      await expectLater(
        _importJson(usecase),
        _failsWith(ExportImportFailureReason.cancelled),
      );
      await expectLater(
        usecase.importDataCsv(),
        _failsWith(ExportImportFailureReason.cancelled),
      );
      expect(asked, 2);
    });

    test('an accepted file goes on to be read', () async {
      final usecase = _usecase(
        () async => _PickedFile('/no/such/backup.zip'),
      )..forkConfirmImport = () async => true;

      await expectLater(
        _importJson(usecase),
        _failsWith(ExportImportFailureReason.unreadableOrWrongFormat),
      );
    });

    test('a dialog closed while the picker was open still answers', () async {
      var asked = 0;
      late ImportDataUsecase usecase;
      usecase = _usecase(() async {
        usecase.forkConfirmImport = null; // the dialog's dispose
        return _PickedFile('/no/such/backup.zip');
      })..forkConfirmImport = () async {
          asked++;
          return false; // unmounted
        };

      await expectLater(
        _importJson(usecase),
        _failsWith(ExportImportFailureReason.cancelled),
      );
      expect(asked, 1);
    });

    test('a dismissed picker is not asked about', () async {
      var asked = false;
      final usecase = _usecase(() async => null)
        ..forkConfirmImport = () async => asked = true;

      await expectLater(
        _importJson(usecase),
        _failsWith(ExportImportFailureReason.cancelled),
      );
      expect(asked, isFalse);
    });
  });

  group('the dialog', () {
    late ImportDataUsecase usecase;
    late _IdleExportImportBloc bloc;

    setUp(() {
      usecase = _usecase(() async => _PickedFile('/no/such/backup.zip'));
      bloc = _IdleExportImportBloc();
      locator
        ..registerSingleton<ExportImportBloc>(bloc)
        ..registerSingleton<HomeBloc>(_HomeBloc())
        ..registerSingleton<DiaryBloc>(_DiaryBloc())
        ..registerSingleton<CalendarDayBloc>(_CalendarDayBloc())
        ..registerSingleton<ImportDataUsecase>(usecase);
    });
    tearDown(locator.reset);

    /// On the critique's phone in the app's fonts, which measure as there.
    Future<void> open(WidgetTester tester, {double scale = 1}) async {
      await pumpOnPhone(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const ExportImportDialog(),
            ),
            child: const Text('Open'),
          ),
        ),
        textScale: scale,
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    for (final csv in [false, true]) {
      testWidgets(
        'at 200% the description starts above the buttons '
        '(${csv ? 'CSV' : 'JSON'})',
        (tester) async {
          await open(tester, scale: 2);
          if (csv) {
            await tester.tap(find.text('CSV backup'));
            await tester.pumpAndSettle();
          }

          final description = tester.getRect(find.text(_description));
          final buttons = tester.getRect(find.text(l10nEn.exportAction));
          expect(description.top, lessThan(buttons.top));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('the CSV option says it is a backup', (tester) async {
      await open(tester);

      expect(find.text('CSV backup'), findsOneWidget);
      expect(find.text('CSV'), findsNothing);
    });

    testWidgets('the CSV note is in body text colour, the icon in accent', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('CSV backup'));
      await tester.pumpAndSettle();

      final scheme = Theme.of(
        tester.element(find.byType(ExportImportDialog)),
      ).colorScheme;
      final note = tester.widget<Text>(
        find.text(l10nEn.exportImportCsvRecipesNote),
      );
      expect(note.style?.color, scheme.onSurfaceVariant);
      final icon = tester.widget<Icon>(find.byIcon(Icons.info_outline));
      expect(icon.color, scheme.secondary);
    });

    testWidgets('a picked backup is confirmed before it replaces anything', (
      tester,
    ) async {
      await open(tester);
      final confirm = usecase.forkConfirmImport;
      expect(confirm, isNotNull);

      var answer = confirm!();
      await tester.pumpAndSettle();
      expect(
        find.text('Replace your goals and the entries this file shares?'),
        findsOneWidget,
      );
      await tester.tap(find.text(l10nEn.dialogCancelLabel).last);
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
      expect(find.byType(ExportImportDialog), findsOneWidget);

      answer = confirm();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(await answer, isTrue);
    });

    testWidgets('Replace is a filled button in the error colour', (
      tester,
    ) async {
      await open(tester);
      final answer = usecase.forkConfirmImport!();
      await tester.pumpAndSettle();
      final label = find.text('Replace');
      final replace = tester.widget<FilledButton>(
        find.ancestor(of: label, matching: find.byType(FilledButton)),
      );
      expect(
        replace.style?.backgroundColor?.resolve(const {}),
        Theme.of(tester.element(label)).colorScheme.error,
      );
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(await answer, isTrue);
    });

    testWidgets('Import asks once the file is picked; Cancel keeps the data',
        (tester) async {
      await open(tester);

      await tester.tap(find.text(l10nEn.importAction));
      await tester.pumpAndSettle();
      expect(
        find.text('Replace your goals and the entries this file shares?'),
        findsOneWidget,
      );
      await tester.tap(find.text(l10nEn.dialogCancelLabel).last);
      await tester.pumpAndSettle();

      await expectLater(
        bloc.started!,
        _failsWith(ExportImportFailureReason.cancelled),
      );
    });

    testWidgets('at 200% the CSV option and the question show in full', (
      tester,
    ) async {
      await open(tester, scale: 2);
      await tester.tap(find.text('CSV backup'));
      await tester.pumpAndSettle();
      // The title's cut at 200% is upstream's (maxLines: 2), not this change's
      final title = l10nEn.exportImportAppDataLabel;
      expect(cutText(tester).where((t) => t != title), isEmpty);

      await tester.tap(find.text(l10nEn.importAction));
      await tester.pumpAndSettle();
      expect(find.text('Replace the entries this file shares?'), findsOneWidget);
      expect(cutText(tester).where((t) => t != title), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a CSV backup holds no goals, so the question leaves them out',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('CSV backup'));
      await tester.pumpAndSettle();

      final answer = usecase.forkConfirmImport!();
      await tester.pumpAndSettle();
      expect(find.text('Replace the entries this file shares?'), findsOneWidget);
      await tester.tap(find.text(l10nEn.dialogCancelLabel).last);
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
    });

    testWidgets('closed, the dialog asks nothing', (tester) async {
      await open(tester);
      await tester.tap(find.text(l10nEn.dialogCancelLabel));
      await tester.pumpAndSettle();

      expect(usecase.forkConfirmImport, isNull);
    });
  });
}
