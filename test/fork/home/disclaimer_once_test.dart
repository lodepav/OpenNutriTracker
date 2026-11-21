import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/disclaimer_dialog.dart';
import 'package:opennutritracker/fork/launch/disclaimer_once.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Shows the disclaimer on every build, as Home does while it is not
/// accepted.
class _Home extends StatefulWidget {
  final ValueNotifier<int> rebuild;
  final List<bool> accepted;

  const _Home(this.rebuild, this.accepted);

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  final _disclaimer = DisclaimerOnce();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.rebuild,
    builder: (context, _, _) {
      _disclaimer.show(context, widget.accepted.add);
      return const Scaffold(body: Text('home'));
    },
  );
}

void main() {
  testWidgets('one dialog however often Home rebuilds, closed only by its '
      'button, not the barrier or Back', (tester) async {
    final rebuild = ValueNotifier(0);
    addTearDown(rebuild.dispose);
    final accepted = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: _Home(rebuild, accepted),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      rebuild.value++;
      await tester.pumpAndSettle();
    }
    expect(find.byType(DisclaimerDialog), findsOneWidget);

    // The barrier saves nothing, so it does not close the dialog.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(DisclaimerDialog), findsOneWidget);

    // Nor does system Back.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(DisclaimerDialog), findsOneWidget);

    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    expect(find.byType(DisclaimerDialog), findsNothing);
    expect(accepted, [true]);
  });
}
