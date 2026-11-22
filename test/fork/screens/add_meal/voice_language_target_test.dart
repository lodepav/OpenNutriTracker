import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/presentation/voice/voice_input_button.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../helpers/fake_dictation_service.dart';

// Seam S555 (G2-16): the dictation language button in the meal field is a
// 48 dp target (A1); it was 40.
void main() {
  testWidgets('the language button is 48 dp', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: TextField(
            controller: controller,
            decoration: InputDecoration(
              suffixIcon: VoiceInputButton(
                controller: controller,
                onDictated: (_) {},
                service: FakeDictationService(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(
      find.ancestor(of: find.text('EN'), matching: find.byType(TextButton)),
    );
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
