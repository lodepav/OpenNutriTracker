import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/share_qr_dialog.dart';
import 'package:opennutritracker/features/home/domain/entity/shared_activity_payload.dart';
import 'package:opennutritracker/features/home/domain/entity/shared_meal_payload.dart';
import 'package:opennutritracker/features/recipes/domain/entity/shared_recipe_payload.dart';

import '../../helpers/ux_checks.dart';

// Copying is confirmed on the button inside the dialog, not by a snackbar
// behind it, a line says where the receiver scans the code, and the image says
// what it is for.

String _mealCode() => SharedMealPayload.fromJsonString(
  jsonEncode([
    2,
    [
      ['4001724039143', 90, 'g'],
    ],
    [
      [
        'Oats', 'Brand', 'g', 125.5, 210.2, 10, 3, 4, //
        null, null, null, null, null, 'fdc', 'fdc-42',
      ],
    ],
    [],
  ]),
).toJsonString();

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

String _workoutCode() => const SharedActivityPayload(
  version: 1,
  items: [SharedActivityItem(code: '01003', duration: 30)],
).toJsonString();

void main() {
  String? copied;

  setUp(() {
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester tester, String code) async {
    await pumpOnPhone(
      tester,
      ShareQrDialog(title: 'Share', code: code, fileBaseName: 'qr'),
      textScale: 1,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Copy says "Copied" in the dialog for a moment', (tester) async {
    final code = _mealCode();
    await pump(tester, code);
    await tester.tap(find.text('Copy code'));
    await tester.pump();

    expect(copied, code);
    expect(find.text('Copied'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copy code'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
  });

  for (final (kind, code, where) in [
    ('meal', _mealCode, "a meal's menu › Import shared meal"),
    ('recipe', _recipeCode, 'Recipes › Import recipe'),
    ('workout', _workoutCode, 'the Activity menu › Import workout'),
  ]) {
    testWidgets('a $kind code says where to scan it', (tester) async {
      await pump(tester, code());
      expect(find.textContaining(where), findsOneWidget);
    });
  }

  for (final (kind, code, label) in [
    ('meal', _mealCode, 'QR code for this meal'),
    ('recipe', _recipeCode, 'QR code for Soup'),
    ('workout', _workoutCode, 'QR code for this workout'),
  ]) {
    testWidgets('a $kind QR image says what it is for', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, code());
      expect(find.bySemanticsLabel(label), findsOneWidget);
      semantics.dispose();
    });
  }

  testWidgets('the dialog with its line passes the screen checks', (
    tester,
  ) async {
    await checkScreen(
      tester,
      ShareQrDialog(title: 'Share', code: _recipeCode(), fileBaseName: 'qr'),
    );
  });
}
