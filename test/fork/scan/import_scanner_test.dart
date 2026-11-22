import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:opennutritracker/fork/scan/scan_hint.dart';
import 'package:opennutritracker/fork/scan/scanner_error.dart';
import 'package:opennutritracker/fork/scan/shared_code_dialog.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../helpers/ux_checks.dart';

// A refused camera shows a way on instead of a black box, the recipe, meal
// and workout paste dialogs say what they take and keep a bad code in the
// field with a next step until the text changes, and the recipe confirm
// reads "Import".

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

/// The camera permission as Android answers it, without the plugin.
class _FakePermission implements CameraPermission {
  // Refused once: the prompt shows, and the camera is allowed in it.
  bool prompts = true;
  PermissionStatus answer = PermissionStatus.granted;
  PermissionStatus now = PermissionStatus.denied;
  int settingsOpened = 0;

  @override
  Future<bool> canPrompt() async => prompts;

  @override
  Future<PermissionStatus> request() async => answer;

  @override
  Future<PermissionStatus> status() async => now;

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

void main() {
  final getIt = GetIt.instance;
  var requests = 0;
  late _FakePermission permission;

  setUp(() async {
    await getIt.reset();
    final fake = _Fake();
    getIt
      ..registerSingleton<ActivityDetailBloc>(fake)
      ..registerSingleton<GetPhysicalActivityUsecase>(fake)
      ..registerSingleton<GetUserUsecase>(fake);
    requests = 0;
    permission = _FakePermission();
    ScannerError.permission = permission;
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
    ScannerError.permission = const CameraPermission();
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

  // G3-20: refused for good, Allow camera opens the app's settings, and
  // coming back with the camera allowed starts it.
  testWidgets('a camera refused for good opens the app settings', (
    tester,
  ) async {
    await pump(tester, const ImportRecipeScannerScreen());
    // refused twice: no prompt, and the plugin reads plain "denied"
    permission
      ..prompts = false
      ..answer = PermissionStatus.denied;

    await tester.tap(find.text('Allow camera'));
    await tester.pumpAndSettle();
    expect(permission.settingsOpened, 1);
    expect(requests, 1, reason: 'no camera start while in settings');

    permission.now = PermissionStatus.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(requests, 2, reason: 'back from settings, the camera starts');
  });

  testWidgets('a refusal in the prompt just shown stays on the message', (
    tester,
  ) async {
    await pump(tester, const ImportRecipeScannerScreen());
    // the second refusal, given in the prompt this tap showed
    permission.answer = PermissionStatus.permanentlyDenied;
    await tester.tap(find.text('Allow camera'));
    await tester.pumpAndSettle();
    expect(permission.settingsOpened, 0);
    expect(requests, 1, reason: 'no camera start without the permission');
    expect(find.text('Camera access is off'), findsOneWidget);
  });

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

  for (final (kind, hint, action, error) in [
    (
      'recipe',
      'Paste the shared recipe code here',
      'Import recipe',
      "This isn't a recipe code",
    ),
    (
      'meal',
      'Paste the shared meal code here',
      'Import meal',
      "This isn't a meal code",
    ),
    (
      'workout',
      'Paste the shared workout code here',
      'Import workout',
      "This isn't a workout code",
    ),
  ]) {
    testWidgets('a bad $kind code stays in the open paste dialog', (
      tester,
    ) async {
      final (screen, args) = screens[kind]!;
      await pump(tester, screen, args);
      await openPaste(tester);
      expect(find.text(hint), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'not a code');
      await tester.tap(find.widgetWithText(TextButton, action));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(
          "$error. Copy the whole code from the sender's Share dialog.",
        ),
        findsOneWidget,
      );
      expect(find.text('not a code'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      await tester.enterText(find.byType(TextField), 'not a code either');
      await tester.pump();
      expect(find.textContaining(error), findsNothing);
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
    expect(find.textContaining("This isn't a recipe code"), findsOneWidget);
    expect(cutText(tester), isEmpty);
    await expectAccessible(tester);
  });

  group('with the camera running', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'state') return 1;
            if (call.method == 'start') {
              return <String, Object?>{
                'textureId': 1,
                'handlesCropAndRotation': true,
                'naturalDeviceOrientation': 'PORTRAIT_UP',
                'sensorOrientation': 0,
                'numberOfCameras': 1,
                'size': {'width': 480.0, 'height': 640.0},
              };
            }
            return null;
          });
    });

    for (final MapEntry(key: kind, value: (screen, args)) in screens.entries) {
      testWidgets('the $kind importer says what to scan over the feed', (
        tester,
      ) async {
        await pump(tester, screen, args);
        expect(find.text('Camera access is off'), findsNothing);
        expect(
          find.text('Point at the QR code from Share $kind'),
          findsOneWidget,
        );

        await tester.tap(find.text('Paste a code instead'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    }
  });

  testWidgets('the workout scanner title fits beside its actions', (
    tester,
  ) async {
    // G3-7: "Import shared wor…" at font 1.0
    await pump(tester, const ImportActivityScannerScreen());
    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Import workout'),
    );
    expect(title, findsOneWidget);
    // the app bar sets no maxLines, so an ellipsis shows only as a box
    // narrower than the text
    final paragraph = tester.renderObject<RenderParagraph>(title);
    expect(
      paragraph.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(paragraph.size.width),
    );
  });

  testWidgets('the line over the feed passes the screen checks', (
    tester,
  ) async {
    await checkScreen(
      tester,
      ScanHint(text: 'Point at the QR code from Share recipe', onPaste: () {}),
    );
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
