import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';

import '../../helpers/fake_reload_blocs.dart';

/// The profile too, which a weigh-in's delete reloads.
extension RegisterProfile on ReloadRecorder {
  void registerProfile() =>
      locator.registerSingleton<ProfileBloc>(_RecordingProfileBloc(log));
}

class _RecordingProfileBloc extends Fake implements ProfileBloc {
  final List<String> _log;

  _RecordingProfileBloc(this._log);

  @override
  void add(ProfileEvent event) => _log.add(event.runtimeType.toString());
}
