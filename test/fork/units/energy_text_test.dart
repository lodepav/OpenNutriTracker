import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('a typed kJ reads back as typed', (tester) async {
    final misread = <int>[];
    double? zero;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: true),
        child: Builder(
          builder: (context) {
            // Weekday shifts are signed and mostly 0.
            for (var kj = -5000; kj <= 20000; kj++) {
              final kcal = kcalFromInput(context, kj.toDouble());
              if (energyValue(context, kcal) != kj) misread.add(kj);
            }
            zero = kcalFromInput(context, 0);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(misread, isEmpty);
    expect(zero, 0);
  });

  testWidgets('a signed energy has a true minus; unsigned keeps its hyphen', (
    tester,
  ) async {
    late List<String> shown;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          shown = [
            energyText(context, -377, signed: true),
            energyText(context, 120, signed: true),
            energyText(context, 0, signed: true),
            energyText(context, -377),
          ];
          return const SizedBox();
        },
      ),
    );
    expect(shown, ['\u2212377 kcal', '+120 kcal', '0 kcal', '-377 kcal']);
  });
}
