import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Checks of fork/UX_STANDARDS.md's A rules that need no emulator: a UX
/// review then spends its time on what a test can't judge.

var _fontLoaded = false;

/// The app's font, so text measures as it does on a phone: the test font's
/// square glyphs would clip what fits.
Future<void> _loadFont(WidgetTester tester) async {
  if (_fontLoaded) return;
  await tester.runAsync(() async {
    final loader = FontLoader('Poppins');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final bytes = await File('fonts/Poppins-$weight.ttf').readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });
  _fontLoaded = true;
}

/// Pumps [body] on a phone-sized screen at [textScale], in the app's theme.
Future<void> pumpOnPhone(
  WidgetTester tester,
  Widget body, {
  double textScale = 2,
  bool dark = false,
}) async {
  await _loadFont(tester);
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 2.625;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(dark ? AppPalette.dark : AppPalette.light),
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      home: Scaffold(body: body),
    ),
  );
  await tester.pump();
}

/// The text on screen that doesn't show in full (A6): past its line limit,
/// or wider than its box on a line that can't wrap.
List<String> cutText(WidgetTester tester) {
  final cut = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final wide =
        !paragraph.softWrap &&
        paragraph.size.width + 0.5 <
            paragraph.getMaxIntrinsicWidth(double.infinity);
    if (paragraph.didExceedMaxLines || wide) {
      cut.add(paragraph.text.toPlainText());
    }
  }
  return cut;
}

/// A1, A2 and A3 on what is on screen: tap targets of 48 dp, with a label,
/// and text that contrasts with its background.
Future<void> expectAccessible(WidgetTester tester) async {
  final semantics = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  semantics.dispose();
}
