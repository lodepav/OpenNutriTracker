// Day starts at offers the minutes as quarter-hour chips, not a 60-step
// slider too short to hit (the 2026-11-21 round 2 G6 critique, dayb.png).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/diary_day_boundary_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/fake_reload_blocs.dart';

class _FakeSettingsBloc extends Fake implements SettingsBloc {
  final int hours;
  final int minutes;
  (int, int)? saved;

  _FakeSettingsBloc(this.hours, this.minutes);

  @override
  Future<int> getDayStartOffsetHours() async => hours;

  @override
  Future<int> getDayStartOffsetMinutes() async => minutes;

  @override
  Future<void> setDayStartOffset(int hours, int minutes) async =>
      saved = (hours, minutes);

  @override
  void add(SettingsEvent event) {}
}

class _FakeHomeBloc extends Fake implements HomeBloc {
  @override
  void add(HomeEvent event) {}
}

void main() {
  setUp(() => ReloadRecorder().register());
  tearDown(() async => locator.reset());

  Future<_FakeSettingsBloc> open(
    WidgetTester tester, {
    int hours = 4,
    int minutes = 0,
  }) async {
    final bloc = _FakeSettingsBloc(hours, minutes);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: DiaryDayBoundaryDialog(
            settingsBloc: bloc,
            homeBloc: _FakeHomeBloc(),
            diaryBloc: locator<DiaryBloc>(),
            calendarDayBloc: locator<CalendarDayBloc>(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  bool selected(WidgetTester tester, int minute) => tester
      .widget<ChoiceChip>(
        find.descendant(
          of: find.bySemanticsIdentifier('day-boundary-minutes-$minute'),
          matching: find.byType(ChoiceChip),
        ),
      )
      .selected;

  testWidgets('one slider for the hour, four chips for the minutes', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(4));
    for (final label in ['00', '15', '30', '45']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(selected(tester, 0), isTrue);
    expect(
      find.textContaining('Choose the time your day begins.'),
      findsOneWidget,
    );
  });

  testWidgets('picking 30 saves the half hour', (tester) async {
    final bloc = await open(tester, hours: 3);
    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();
    expect(find.text('3:30'), findsOneWidget);
    expect(selected(tester, 30), isTrue);

    await tester.tap(find.bySemanticsIdentifier('day-boundary-save'));
    await tester.pumpAndSettle();
    expect(bloc.saved, (3, 30));
  });

  testWidgets('a stored 4:37 is kept until a chip is picked', (tester) async {
    final bloc = await open(tester, minutes: 37);
    expect(find.text('4:37'), findsOneWidget);
    for (final m in [0, 15, 30, 45]) {
      expect(selected(tester, m), isFalse);
    }

    await tester.tap(find.bySemanticsIdentifier('day-boundary-save'));
    await tester.pumpAndSettle();
    expect(bloc.saved, (4, 37));
  });

  testWidgets('fits a phone at 200% text', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('45'), findsOneWidget);
  });
}
