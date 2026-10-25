import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
// [fork] S113 weigh-in-delete
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
// [/fork]

class DeleteWeightLogUsecase {
  final WeightLogRepository _weightLogRepository;

  // [fork] S113 weigh-in-delete: as adding today's reading sets the
  // profile weight, deleting it sets it back to the newest one left
  final UserRepository? _userRepository;

  DeleteWeightLogUsecase(this._weightLogRepository, [this._userRepository]);
  // [/fork]

  /// Deletes the stored row [entry] was read from: the one filed under
  /// [WeightLogEntity.filedDay]. Its [WeightLogEntity.date] can show a
  /// neighbouring day after a time-zone change, and deleting by that would
  /// miss the row or remove the neighbour's (#1418). An entry not read from
  /// the log falls back to its date.
  Future<void> deleteEntry(WeightLogEntity entry) async {
    await _weightLogRepository.deleteEntry(entry.filedDay ?? entry.date);
    // [fork] S113 weigh-in-delete
    final users = _userRepository;
    if (users == null ||
        entry.date.toParsedDay() != DateTime.now().toParsedDay()) {
      return;
    }
    final left = await _weightLogRepository.getAllEntries();
    if (left.isEmpty) return;
    final newest = left.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
    final user = await users.getUserData();
    user.weightKG = newest.weightKg;
    await users.updateUserData(user);
    // [/fork]
  }
}
