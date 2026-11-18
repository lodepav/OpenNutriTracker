import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';

/// Home's loads: one each time the HomeBloc has read the day again (a log,
/// an edit on the Diary, a setting). A card reads its own data again on
/// these, not on every rebuild of Home. None where no HomeBloc is (tests).
Stream<Object?> homeLoads() => locator.isRegistered<HomeBloc>()
    ? locator<HomeBloc>().stream.where((s) => s is HomeLoadedState)
    : const Stream.empty();
