import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/demo_mode_banner.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/generated/l10n.dart';

// The demo banner's action reads at 4.5:1 on its tint with a pale accent:
// with yellow it was yellow on pale yellow.

void main() {
  for (final base in [AppPalette.light, AppPalette.dark]) {
    testWidgets('with yellow in ${base.brightness.name} the banner action '
        'reads at 4.5:1', (tester) async {
      const yellow = Color(0xFFFDD835);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(base.withAccent(yellow)),
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: const Scaffold(body: DemoModeBanner()),
        ),
      );
      await tester.pumpAndSettle();
      final action = tester
          .renderObject<RenderParagraph>(find.text('Set up your profile'))
          .text
          .style!
          .color!;
      final tint = Color.alphaBlend(
        yellow.withValues(alpha: 0.12),
        base.canvas,
      );
      expect(contrastRatio(action, tint), greaterThanOrEqualTo(4.5));
    });
  }
}
