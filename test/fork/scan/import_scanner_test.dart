import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_physical_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/features/activity_detail/presentation/bloc/activity_detail_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/home/presentation/screens/import_activity_scanner_screen.dart';
import 'package:opennutritracker/features/home/presentation/screens/import_meal_scanner_screen.dart';
import 'package:opennutritracker/features/recipes/domain/entity/shared_recipe_payload.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/import_recipe_scanner_screen.dart';
import 'package:opennutritracker/fork/scan/scanner_error.dart';
import 'package:opennutritracker/fork/scan/shared_code_dialog.dart';

import '../../helpers/ux_checks.dart';

// A refused camera shows a way on instead of a black box, the recipe and
// workout paste dialogs say what they take and keep a bad code in the field,
// and the recipe confirm reads "Import".

class _Fake
    implements ActivityDetailBloc, GetPhysicalActivityUsecase, GetUserUsecase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _channel = MethodChannel('dev.steenbakker.mobile_scanner/scanner/method');
// The scanner's streams cancel after a test ends, so they stay answered.
const _streams = [
  MethodChannel('dev.steenbakker.mobile_scanner/scanner/event'),
  MethodChannel('dev.steenbakker.mobile_scanner/scanner/deviceOrientation'),
];

String _recipeCode() => SharedRecipePayload.fromJsonString(
  jsonEncode([
    1,
    'Soup',
    null,
    4,
    240,
    [210.2, 10, 3, 4, null, null, null],
    [
      [
        'Ingredient',
        'Brand',
        300,
        'g',
        300,
        210.2,
        10,
        3,
        4,
        null,
        null,
        null,
        null,
      ],
    ],
    1,
  ]),
).toJsonString();

void main() {
  final getIt = GetIt.instance;
  var requests = 0;

  setUp(() async {
    await getIt.reset();
    final fake = _Fake();
    getIt
      ..registerSingleton<ActivityDetailBloc>(fake)
      ..registerSingleton<GetPhysicalActivityUsecase>(fake)
      ..registerSingleton<GetUserUsecase>(fake);
    requests = 0;
    for (final stream in _streams) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(stream, (_) async => null);
    }
    // The camera is refused: denied state, and asking again is refused too.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'state') return 2;
          if (call.method == 'request') {
            requests++;
            return false;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    await getIt.reset();
  });

  Future<void> pump(WidgetTester tester, Widget screen, [Object? args]) async {
    await pumpOnPhone(
      tester,
      Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(
          settings: RouteSettings(arguments: args),
          builder: (_) => screen,
        ),
      ),
      textScale: 1,
    );
    await tester.pumpAndSettle();
  }

  final screens = <String, (Widget, Object?)>{
    'recipe': (const ImportRecipeScannerScreen(), null),
    'meal': (
      const ImportMealScannerScreen(),
      ImportMealScannerArguments(
        IntakeTypeEntity.lunch,
        AddMealType.lunchType,
        DateTime(2026, 11, 21),
      ),
    ),
    'workout': (const ImportActivityScannerScreen(), null),
  };

  for (final MapEntry(key: kind, value: (screen, args)) in screens.entries) {
    testWidgets('a refused camera on the $kind importer offers a way on', (
      tester,
    ) async {
      await pump(tester, screen, args);
      expect(find.text('Camera access is off'), findsOneWidget);
      expect(find.text('Allow camera'), findsOneWidget);

      await tester.tap(find.text('Allow camera'));
      await tester.pumpAndSettle();
      expect(requests, 2, reason: 'Allow camera asks again');

      await tester.tap(find.text('Paste a code instead'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  }

  testWidgets('the camera message passes the screen checks', (tester) async {
    await checkScreen(
      tester,
      ScannerError(
        error: const MobileScannerException(
          errorCode: MobileScannerErrorCode.permissionDenied,
        ),
        controller: MobileScannerController(autoStart: false),
        onPaste: () {},
      ),
    );
  });

  testWidgets('another camera error offers only the paste dialog', (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      ScannerError(
        error: const MobileScannerException(
          errorCode: MobileScannerErrorCode.genericError,
        ),
        controller: MobileScannerController(autoStart: false),
        onPaste: () {},
      ),
    );
    expect(find.text('Allow camera'), findsNothing);
    expect(find.text('Paste a code instead'), findsOneWidget);
  });

  Future<void> openPaste(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Paste code'));
    await tester.pumpAndSettle();
  }

  for (final (kind, screen, hint, error) in [
    (
      'recipe',
      const ImportRecipeScannerScreen(),
      'Paste the shared recipe code here',
      "This isn't a recipe code",
    ),
    (
      'workout',
      const ImportActivityScannerScreen(),
      'Paste the shared workout code here',
      "This isn't a workout code",
    ),
  ]) {
    testWidgets('a bad $kind code stays in the open paste dialog', (
      tester,
    ) async {
      await pump(tester, screen);
      await openPaste(tester);
      expect(find.text(hint), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'not a code');
      await tester.tap(
        find
            .text(kind == 'recipe' ? 'Import recipe' : 'Import shared workout')
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(error), findsOneWidget);
      expect(find.text('not a code'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets('the paste dialog with its error passes the screen checks', (
    tester,
  ) async {
    await checkScreen(
      tester,
      SharedCodeDialog(
        hint: 'Paste the shared recipe code here',
        actionLabel: 'Import recipe',
        invalidLabel: "This isn't a recipe code",
        isValid: (_) => false,
      ),
    );
    await tester.tap(find.text('Import recipe'));
    await tester.pumpAndSettle();
    expect(find.text("This isn't a recipe code"), findsOneWidget);
    expect(cutText(tester), isEmpty);
    await expectAccessible(tester);
  });

  testWidgets('the recipe confirm imports with "Import"', (tester) async {
    await pump(tester, const ImportRecipeScannerScreen());
    await openPaste(tester);
    await tester.enterText(find.byType(TextField), _recipeCode());
    await tester.tap(find.text('Import recipe').last);
    await tester.pumpAndSettle();

    expect(find.text('Soup'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Import'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'OK'), findsNothing);
  });
}
