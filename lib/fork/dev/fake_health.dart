import 'package:opennutritracker/fork/dev/fake_ai.dart';
import 'package:opennutritracker/fork/health/steps.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';

/// `--dart-define=FORK_FAKE_HEALTH=true`, on with the fake AI: the weight
/// import and the steps read made-up data instead of Health Connect.
const forkFakeHealth = bool.fromEnvironment(
  'FORK_FAKE_HEALTH',
  defaultValue: forkFakeAi,
);

/// A smart scale stepped on at 7:00 every day, drifting down 0.1 kg a day
/// from 82 kg a month ago.
class FakeWeights implements WeightSource {
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<List<HealthWeight>> read(DateTime from, DateTime to) async {
    final today = DateTime(to.year, to.month, to.day);
    return [
      for (var ago = 30; ago >= 0; ago--)
        if (today.subtract(Duration(days: ago)).add(const Duration(hours: 7))
            case final at when !at.isBefore(from) && !at.isAfter(to))
          HealthWeight(
            'fake-${at.toIso8601String()}',
            at,
            ((820 - (30 - ago)) / 10),
          ),
    ];
  }
}

/// A walker who does 4,000 to 12,000 steps a day, the same each run, and
/// walks evenly from 7:00 to 22:00.
class FakeSteps implements StepSource {
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<int> stepsBetween(DateTime from, DateTime to) async {
    final day = DateTime(from.year, from.month, from.day);
    final full =
        4000 + (day.year * 372 + day.month * 31 + day.day) * 2731 % 8000;
    final walked = (to.difference(day).inMinutes - 7 * 60).clamp(0, 15 * 60);
    return full * walked ~/ (15 * 60);
  }
}
