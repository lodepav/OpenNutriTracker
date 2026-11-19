import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/home_appbar.dart';
import 'package:opennutritracker/core/presentation/widgets/main_appbar.dart';
import 'package:opennutritracker/generated/l10n.dart';

Widget _app(PreferredSizeWidget appBar, {double scale = 1}) => MaterialApp(
  localizationsDelegates: const [S.delegate],
  supportedLocales: S.supportedLocales,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(appBar: appBar),
    ),
  ),
);

void main() {
  testWidgets('the Diary tab bar has no leading icon; its title starts at 16 '
      'as on pushed pages', (tester) async {
    await tester.pumpWidget(
      _app(const MainAppbar(title: 'Diary', iconData: Icons.book)),
    );

    expect(find.byIcon(Icons.book), findsNothing);
    expect(tester.getTopLeft(find.text('Diary')).dx, 16);
  });

  testWidgets("Home's title grows with the text size", (tester) async {
    // RichText before, Text after: both put a RichText under the title.
    final title = find.descendant(
      of: find.byType(Expanded),
      matching: find.byType(RichText),
    );

    await tester.pumpWidget(_app(const HomeAppbar()));
    final normal = tester.getSize(title).height;

    await tester.pumpWidget(_app(const HomeAppbar(), scale: 2));
    await tester.pump();
    final large = tester.getSize(title).height;

    // AppBar caps a title's scale (about 1.34), so taller, not doubled.
    expect(large, greaterThan(normal));
  });
}
