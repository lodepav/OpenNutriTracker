// At twice the font size the Export / import dialog scrolls, so its
// overwrite warning stays above the buttons, and Cancel leaves it (the
// 2026-11-21 G6 critique, ex_d2.png).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/export_import_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/export_import_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/test_l10n.dart';

class _IdleExportImportBloc extends Fake implements ExportImportBloc {
  @override
  ExportImportState get state => ExportImportInitial();

  @override
  Stream<ExportImportState> get stream =>
      const Stream<ExportImportState>.empty();
}

class _HomeBloc extends Fake implements HomeBloc {}

class _DiaryBloc extends Fake implements DiaryBloc {}

class _CalendarDayBloc extends Fake implements CalendarDayBloc {}

const _warning =
    'Import adds the file\'s entries to this profile, overwriting any it '
    'shares, and the goals it holds replace yours.';

void main() {
  setUp(() {
    locator
      ..registerSingleton<ExportImportBloc>(_IdleExportImportBloc())
      ..registerSingleton<HomeBloc>(_HomeBloc())
      ..registerSingleton<DiaryBloc>(_DiaryBloc())
      ..registerSingleton<CalendarDayBloc>(_CalendarDayBloc());
  });
  tearDown(locator.reset);

  Future<void> open(WidgetTester tester) async {
    // A 1080 x 2340 phone at 420 dpi, as the critique's emulator.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ExportImportDialog(),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('at 200% the warning scrolls into view above the buttons', (
    tester,
  ) async {
    await open(tester);

    await tester.ensureVisible(find.text(_warning));
    await tester.pumpAndSettle();
    final dialog = tester.getRect(find.byType(AlertDialog));
    final warning = tester.getRect(find.text(_warning));
    final buttons = tester.getRect(find.text(l10nEn.exportAction));
    expect(warning.bottom, lessThanOrEqualTo(buttons.top));
    expect(warning.bottom, lessThanOrEqualTo(dialog.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel closes it without exporting or importing', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text(l10nEn.dialogCancelLabel));
    await tester.pumpAndSettle();

    expect(find.byType(ExportImportDialog), findsNothing);
  });
}
