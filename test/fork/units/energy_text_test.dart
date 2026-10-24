import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('a typed kJ reads back as typed', (tester) async {
    final misread = <int>[];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: true),
        child: Builder(
          builder: (context) {
            for (var kj = 1000; kj <= 20000; kj++) {
              final kcal = kcalFromInput(context, kj.toDouble());
              if (energyValue(context, kcal) != kj) misread.add(kj);
            }
            return const SizedBox();
          },
        ),
      ),
    );
    expect(misread, isEmpty);
  });
}
