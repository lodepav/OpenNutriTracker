import 'package:opennutritracker/fork/dev/fake_ai.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';

/// `--dart-define=FORK_FAKE_HEALTH=true`, on with the fake AI: the weight
/// import reads made-up weigh-ins instead of Health Connect.
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
