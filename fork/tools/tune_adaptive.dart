// ignore_for_file: avoid_print
// Sweeps the estimator's weights on the simulated users, then reports the
// chosen settings per user (D13, phase 3). Results go in
// fork/research/phase3-simulation.md.
//   dart run fork/tools/tune_adaptive.dart [sweep]
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/simulator.dart';

String _row(SimSummary s) =>
    '${s.error.toStringAsFixed(0)} | ${s.stability.toStringAsFixed(1)} | '
    '${s.responseDays?.toStringAsFixed(0) ?? '-'}';

void main(List<String> args) {
  if (args.contains('sweep')) {
    print(
      'alpha | window | calibration | blend | error | stability | response',
    );
    for (final alpha in [0.05, 0.1, 0.15, 0.2, 0.25]) {
      for (final window in [14, 20, 28]) {
        for (final calibration in [0.1, 0.2]) {
          for (final blend in [0.02, 0.035, 0.05, 0.1]) {
            final settings = ExpenditureSettings(
              alpha: alpha,
              window: window,
              calibrationBlend: calibration,
              blend: blend,
            );
            print(
              '$alpha | $window | $calibration | $blend | '
              '${_row(scoreAll(settings))}',
            );
          }
        }
      }
    }
    return;
  }
  const chosen = ExpenditureSettings();
  print('user | error | stability | response');
  for (final user in simUsers) {
    print('${user.name} | ${_row(scoreAll(chosen, users: [user]))}');
  }
  print('all | ${_row(scoreAll(chosen))}');
  for (final preset in Responsiveness.values) {
    print(
      'all, ${preset.label.toLowerCase()} | '
      '${_row(scoreAll(ExpenditureSettings.of(preset)))}',
    );
  }
  print('all, flat 6,000 kcal/kg | ${_row(scoreAll(chosen, forbes: false))}');
  for (final priorError in [-0.2, 0.0, 0.2]) {
    print(
      'all, prior off by ${(priorError * 100).round()}% | '
      '${_row(scoreAll(chosen, priorError: priorError))}',
    );
  }
}
