import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/activity_credit.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/screens/home/dashboard_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';

Widget _app(Widget child, {bool off = false}) => ChangeNotifierProvider(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: off),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  ),
);

DashboardWidget _dashboard(
  double left, {
  Future<ActivityCredit> Function()? loadCredit,
  Stream<void>? homeLoads,
}) => DashboardWidget(
  totalKcalSupplied: 2500 - left,
  totalKcalBurned: 0,
  totalKcalDaily: 2500,
  totalKcalLeft: left,
  totalCarbsIntake: 100,
  totalFatsIntake: 30,
  totalProteinsIntake: 60,
  totalCarbsGoal: 375,
  totalFatsGoal: 69,
  totalProteinsGoal: 93,
  loadCredit: loadCredit ?? () async => ActivityCredit.added,
  homeLoads: homeLoads ?? const Stream.empty(),
);

void main() {
  testWidgets('with animations on, a logged meal moves the ring', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_dashboard(2000)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(_dashboard(1500)));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('with Remove animations on, the ring and counter show the new '
      'value on the next frame', (tester) async {
    await tester.pumpWidget(_app(_dashboard(2000), off: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(_dashboard(1500), off: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(
      tester
          .widget<CircularPercentIndicator>(
            find.byType(CircularPercentIndicator),
          )
          .percent,
      // Left mode: 1500 of 2500 left
      closeTo(0.6, 1e-9),
    );
  });

  testWidgets('Remove animations switched on while Home is open', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_dashboard(2000)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(_dashboard(2000), off: true));
    await tester.pump();
    await tester.pumpWidget(_app(_dashboard(1500), off: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a rebuild with the same figures reads the credit once; a Home '
      'load reads it again', (tester) async {
    var reads = 0;
    final loads = StreamController<void>.broadcast();
    addTearDown(loads.close);
    Future<ActivityCredit> read() async {
      reads++;
      return ActivityCredit.added;
    }

    await tester.pumpWidget(
      _app(_dashboard(2000, loadCredit: read, homeLoads: loads.stream)),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _app(_dashboard(2000, loadCredit: read, homeLoads: loads.stream)),
    );
    await tester.pumpAndSettle();
    expect(reads, 1);

    loads.add(null);
    await tester.pumpAndSettle();
    expect(reads, 2);
  });

  testWidgets('a change to the target settings reads the credit again', (
    tester,
  ) async {
    final before = AdaptiveStore.settings.value;
    addTearDown(() => AdaptiveStore.settings.value = before);
    var reads = 0;
    await tester.pumpWidget(
      _app(
        _dashboard(
          2000,
          loadCredit: () async {
            reads++;
            return ActivityCredit.added;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    AdaptiveStore.settings.value = const AdaptiveSettings(fixedTarget: true);
    await tester.pumpAndSettle();
    expect(reads, 2);
  });
}
