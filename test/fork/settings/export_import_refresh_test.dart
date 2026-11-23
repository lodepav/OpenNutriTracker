// Export / import after the G6 audit (seam S580): the screens reload once
// when an import finishes, also after the dialog has closed; not on each
// rebuild of the success state and not after an export. Export and Import
// wait while one runs, and Cancel reads Close once one has finished.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/export_import_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/export_import_dialog.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Ends an export or an import in success, as the real bloc does.
class _ExportImportBloc extends Fake implements ExportImportBloc {
  final _states = StreamController<ExportImportState>.broadcast();

  @override
  ExportImportState state = ExportImportInitial();

  @override
  Stream<ExportImportState> get stream => _states.stream;

  void _emit(ExportImportState next) {
    state = next;
    _states.add(next);
  }

  /// When set, an import stays loading until it completes.
  Completer<void>? hold;

  /// When set, an import ends in this state, as a cancelled picker does.
  ExportImportState? importEnd;

  @override
  void add(ExportImportEvent event) {
    if (event is ResetExportImportStateEvent) _emit(ExportImportInitial());
    if (event is ExportDataEvent || event is ImportDataEvent) {
      _emit(ExportImportLoadingState());
      final wait = hold;
      final end = importEnd;
      if (event is ImportDataEvent && end != null) {
        _emit(end);
      } else if (wait == null) {
        _emit(ExportImportSuccess());
      } else {
        wait.future.then((_) => _emit(ExportImportSuccess()));
      }
    }
  }
}

final _events = <Object>[];

class _HomeBloc extends Fake implements HomeBloc {
  @override
  void add(HomeEvent event) => _events.add(event);
}

class _DiaryBloc extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) => _events.add(event);
}

class _CalendarDayBloc extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) => _events.add(event);
}

class _SettingsBloc extends Fake implements SettingsBloc {
  @override
  void add(SettingsEvent event) => _events.add(event);
}

class _ProfileBloc extends Fake implements ProfileBloc {
  @override
  void add(ProfileEvent event) => _events.add(event);
}

TrendsState _trends = const TrendsInitial();

const _loaded = TrendsLoaded(
  rangeDays: 30,
  windowDays: 30,
  days: [],
  priorWeek: [],
  weight: [],
  bodyWeightUnit: BodyWeightUnit.kg,
  targetWeightKg: null,
  waterByDay: {},
  waterGoalMl: 2000,
);

class _TrendsBloc extends Fake implements TrendsBloc {
  @override
  TrendsState get state => _trends;

  @override
  void add(TrendsEvent event) => _events.add(event);
}

void main() {
  setUp(() {
    _events.clear();
    _trends = _loaded;
    locator
      ..registerSingleton<ExportImportBloc>(_ExportImportBloc())
      ..registerSingleton<HomeBloc>(_HomeBloc())
      ..registerSingleton<DiaryBloc>(_DiaryBloc())
      ..registerSingleton<CalendarDayBloc>(_CalendarDayBloc())
      ..registerSingleton<SettingsBloc>(_SettingsBloc())
      ..registerSingleton<ProfileBloc>(_ProfileBloc())
      ..registerSingleton<TrendsBloc>(_TrendsBloc());
  });

  tearDown(locator.reset);

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en')],
        home: Scaffold(body: ExportImportDialog()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a finished import reloads the screens once', (tester) async {
    await pumpDialog(tester);
    expect(_events, isEmpty);

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(_events.whereType<LoadItemsEvent>(), hasLength(1));
    expect(_events.whereType<LoadSettingsEvent>(), hasLength(1));
    expect(_events.whereType<LoadProfileEvent>(), hasLength(1));
    expect(_events.whereType<LoadDiaryYearEvent>(), hasLength(1));
    expect(_events, contains(const LoadTrendsEvent(rangeDays: 30)));

    // A rebuild of the success state reloads nothing more.
    final count = _events.length;
    tester.element(find.byType(ExportImportDialog)).markNeedsBuild();
    await tester.pumpAndSettle();
    expect(_events, hasLength(count));
  });

  testWidgets('Trends is left to load itself when it never has', (
    tester,
  ) async {
    _trends = const TrendsInitial();
    await pumpDialog(tester);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(_events.whereType<LoadItemsEvent>(), hasLength(1));
    expect(_events.whereType<LoadTrendsEvent>(), isEmpty);
  });

  testWidgets('a cancelled import reloads nothing', (tester) async {
    (locator<ExportImportBloc>() as _ExportImportBloc).importEnd =
        ExportImportInitial();
    await pumpDialog(tester);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(_events, isEmpty);
  });

  testWidgets('a finished export reloads nothing', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(_events, isEmpty);
  });
  testWidgets('an import that ends after the dialog closed still reloads, '
      'once', (tester) async {
    final bloc = locator<ExportImportBloc>() as _ExportImportBloc;
    bloc.hold = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ExportImportDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import'));
    await tester.pump();
    // While it runs, a second Export or Import cannot start
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Import'))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Export'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ExportImportDialog), findsNothing);
    expect(_events, isEmpty);

    bloc.hold!.complete();
    await tester.pumpAndSettle();
    expect(_events.whereType<LoadItemsEvent>(), hasLength(1));
    expect(_events.whereType<LoadSettingsEvent>(), hasLength(1));
  });

  testWidgets('the description says what each format holds and points at '
      'the diary CSV', (tester) async {
    await pumpDialog(tester);
    expect(find.textContaining('A CSV backup leaves out recipes'), findsOneWidget);
    expect(find.textContaining('Export diary as CSV'), findsOneWidget);
    expect(find.textContaining('backup your data'), findsNothing);
  });

  testWidgets('switching format mid-import keeps its reload', (tester) async {
    final bloc = locator<ExportImportBloc>() as _ExportImportBloc;
    bloc.hold = Completer<void>();
    await pumpDialog(tester);
    await tester.tap(find.text('Import'));
    await tester.pump();
    await tester.tap(find.text('CSV backup'));
    await tester.pump();
    bloc.hold!.complete();
    await tester.pumpAndSettle();
    expect(_events.whereType<LoadItemsEvent>(), hasLength(1));
  });

  testWidgets('Cancel reads Close once an import has finished', (
    tester,
  ) async {
    await pumpDialog(tester);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });
}
