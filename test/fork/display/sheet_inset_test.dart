import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/display/sheet_inset.dart';

// A bottom sheet's foot clears the navigation bar, or the keyboard.

Future<double> _inset(
  WidgetTester tester, {
  required double bar,
  double keyboard = 0,
}) async {
  late double inset;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        viewPadding: EdgeInsets.only(bottom: bar),
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      child: Builder(
        builder: (context) {
          inset = sheetBottomInset(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return inset;
}

void main() {
  testWidgets('the navigation bar, with the keyboard down', (tester) async {
    expect(await _inset(tester, bar: 48), 48);
  });

  testWidgets('the keyboard, which already covers the bar', (tester) async {
    expect(await _inset(tester, bar: 48, keyboard: 320), 320);
  });

  testWidgets('nothing on a device with no bar', (tester) async {
    expect(await _inset(tester, bar: 0), 0);
  });
}
