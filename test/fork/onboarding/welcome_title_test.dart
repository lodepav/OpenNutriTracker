import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/onboarding/welcome_title.dart';

/// The intro page's Welcome title is a heading, as every later step's is
/// (seam S464).
void main() {
  testWidgets('the Welcome title is a heading', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WelcomeTitle('Welcome', style: TextStyle())),
      ),
    );
    expect(
      tester.getSemantics(find.text('Welcome')),
      isSemantics(label: 'Welcome', isHeader: true),
    );
    handle.dispose();
  });
}
