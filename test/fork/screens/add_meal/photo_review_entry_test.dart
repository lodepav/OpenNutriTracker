// A photo's review takes the screen: the entry block above it goes while
// the photo's foods show; another food is logged through Add again (D50).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory_store.dart';
import 'package:opennutritracker/fork/screens/add_meal/bulk_add_screen.dart';

import 'photo_review_harness.dart';

const _rice = ParsedMealItem(query: 'rice', quantity: 150, unit: 'g');
const _chicken = ParsedMealItem(query: 'chicken', quantity: 100, unit: 'g');

const _noteHint = 'With a photo, this is sent as its note';
final _parse = find.bySemanticsIdentifier('bulk-add-parse');
final _submit = find.bySemanticsIdentifier('bulk-add-submit');

void _expectEntryGone() {
  expect(find.byType(TextField), findsNothing);
  expect(_parse, findsNothing);
  expect(find.bySemanticsIdentifier('bulk-add-photo'), findsNothing);
  expect(find.bySemanticsIdentifier('bulk-add-gallery'), findsNothing);
  expect(find.text(_noteHint), findsNothing);
}

void _expectEntryShown() {
  expect(find.bySemanticsIdentifier('bulk-add-input'), findsOneWidget);
  expect(_parse, findsOneWidget);
}

/// A phone's screen, 360 × 780 dp.
void _phone(WidgetTester tester, {double textScale = 1}) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

class _MealDetailBloc extends Fake implements MealDetailBloc {
  static var written = 0;

  @override
  Future<IntakeEntity?> addIntake(
    BuildContext context,
    String unit,
    String amountText,
    IntakeTypeEntity intakeTypeEntity,
    MealEntity meal,
    DateTime day,
  ) async => IntakeEntity(
    id: 'intake-${++written}',
    unit: unit,
    amount: double.parse(amountText),
    type: intakeTypeEntity,
    meal: meal,
    dateTime: day,
  );
}

class _HomeBloc extends Fake implements HomeBloc {
  @override
  void add(HomeEvent event) {}
}

class _DiaryBloc extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _CalendarDayBloc extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

/// The photo meal memory in a list: Log's write to it is not awaited, and
/// a real box left opening outlives the test in a bundled run.
class _Memory implements PhotoMealMemoryStore {
  final kept = <PhotoMealRecord>[];

  @override
  Future<List<PhotoMealRecord>> records({DateTime? now}) async => [...kept];

  @override
  Future<void> add(PhotoMealRecord record, {DateTime? now}) async =>
      kept.add(record);
}

/// The screen opened again, as from the add sheet.
Future<void> _reopen(WidgetTester tester) async {
  renewReviewBloc();
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/bulk');
  await tester.pumpAndSettle();
}

void main() {
  setUpReviewHarness('photo_review_entry_test');

  group("a photo's foods on show", () {
    testWidgets('hide the entry block and keep the banner', (tester) async {
      await openWithStagedPhoto(tester);
      expect(find.text(_noteHint), findsOneWidget);
      await sendStagedPhoto(tester, const [_rice, _chicken]);

      _expectEntryGone();
      expect(find.bySemanticsIdentifier('bulk-add-model-notice'), findsOne);
      expect(find.text('Name the dish'), findsOneWidget);
    });

    testWidgets('leave the first food in view on a phone', (tester) async {
      await openWithStagedPhoto(tester);
      await sendStagedPhoto(tester, const [_rice, _chicken]);
      _phone(tester);
      await tester.pumpAndSettle();

      final row = tester.getRect(find.text('rice').first);
      expect(row.bottom, lessThan(tester.getRect(_submit).top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('give the review the screen at twice the text size', (
      tester,
    ) async {
      await openWithStagedPhoto(tester);
      await sendStagedPhoto(tester, const [_rice, _chicken]);
      _phone(tester, textScale: 2);
      await tester.pumpAndSettle();

      // At 2x the meal card alone is taller than the phone, so the foods are
      // scrolled to; what changed is that nothing sits between the app bar,
      // the banner and the list, and the list runs down to the Log bar.
      final notice = tester.getRect(
        find.bySemanticsIdentifier('bulk-add-model-notice'),
      );
      final list = tester.getRect(
        find.bySemanticsIdentifier('bulk-add-row-list'),
      );
      expect(notice.top, tester.getRect(find.byType(AppBar)).bottom);
      expect(list.top, notice.bottom);
      expect(list.bottom, greaterThan(tester.getRect(_submit).top - 32));
      await tester.scrollUntilVisible(
        find.text('rice'),
        200,
        scrollable: find.descendant(
          of: find.bySemanticsIdentifier('bulk-add-row-list'),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('rice'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('take the keyboard and the focus off the field', (
      tester,
    ) async {
      await openReview(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await readReviewPhoto(tester, const [_rice]);
      _expectEntryGone();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
    });
  });

  group('the entry block stays', () {
    testWidgets('for typed text', (tester) async {
      await openReview(tester);
      await tester.enterText(find.byType(TextField), 'salad, egg');
      await tester.pump();
      await tester.tap(_parse);
      await tester.pumpAndSettle();

      expect(reviewRows(), isNotEmpty);
      _expectEntryShown();
    });

    testWidgets('for a failed read, with the photo waiting', (tester) async {
      await openWithStagedPhoto(tester);
      reviewBloc.add(
        const ReadMealPhotoFailedEvent(BulkAddPhotoError.transient),
      );
      await tester.pumpAndSettle();

      _expectEntryShown();
      expect(find.bySemanticsIdentifier('bulk-add-photo-staged'), findsOne);
    });

    testWidgets('for a read that found no food', (tester) async {
      await openWithStagedPhoto(tester);
      await sendStagedPhoto(tester, const []);

      _expectEntryShown();
      expect(find.bySemanticsIdentifier('bulk-add-photo-staged'), findsOne);
    });

    testWidgets('for a staged photo, with its note chips', (tester) async {
      await openWithStagedPhoto(tester);

      _expectEntryShown();
      expect(find.text('Weighed'), findsOneWidget);
    });
  });

  group('the next visit has the entry block', () {
    testWidgets('after a discard', (tester) async {
      await openReview(tester);
      await readReviewPhoto(tester, const [_rice, _chicken]);
      _expectEntryGone();

      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BulkAddScreen), findsNothing);

      await _reopen(tester);
      _expectEntryShown();
    });

    testWidgets('after Log', (tester) async {
      final memory = _Memory();
      final before = forkPhotoMealMemory;
      forkPhotoMealMemory = () => memory;
      addTearDown(() => forkPhotoMealMemory = before);
      await openReview(tester);
      GetIt.instance
        ..registerFactory<MealDetailBloc>(_MealDetailBloc.new)
        ..registerFactory<HomeBloc>(_HomeBloc.new)
        ..registerFactory<DiaryBloc>(_DiaryBloc.new)
        ..registerFactory<CalendarDayBloc>(_CalendarDayBloc.new);
      // One food: two would be kept as a meal group in a Hive box, whose
      // opening never ends in fake time once an earlier file in a bundled
      // run has set Hive up on disk; the screen would never leave.
      await readReviewPhoto(tester, const [_rice]);
      _expectEntryGone();

      _MealDetailBloc.written = 0;
      await tapAndSettle(
        tester,
        find.widgetWithIcon(FilledButton, Icons.add_rounded),
      );
      expect(_MealDetailBloc.written, 1);
      expect(memory.kept, hasLength(1));
      expect(find.byType(BulkAddScreen), findsNothing);

      await _reopen(tester);
      _expectEntryShown();
    });
  });
}
