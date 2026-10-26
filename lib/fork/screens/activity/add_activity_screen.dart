// Fork-owned copy of lib/features/add_activity/presentation/add_activity_screen.dart (D23); upstream's later changes to it
// are ported by hand: fork/tools/upstream-copies.sh.
// Upstream's arguments, so upstream's callers open this screen too.
import 'package:opennutritracker/features/add_activity/presentation/add_activity_screen.dart'
    show AddActivityScreenArguments;
export 'package:opennutritracker/features/add_activity/presentation/add_activity_screen.dart'
    show AddActivityScreenArguments;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/error_dialog.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/activity_detail/activity_detail_screen.dart';
import 'package:opennutritracker/features/add_activity/presentation/bloc/activities_bloc.dart';
import 'package:opennutritracker/features/add_activity/presentation/widgets/quick_add_activity_bottom_sheet.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/log_user_activity_usecase.dart';
import 'package:opennutritracker/core/utils/navigation_predicates.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_display_format.dart';
import 'package:opennutritracker/fork/activity/activity_picker.dart';
import 'package:opennutritracker/fork/adaptive/activity_credit.dart';

class AddActivityScreen extends StatefulWidget {
  const AddActivityScreen({super.key});

  @override
  State<AddActivityScreen> createState() => _AddActivityScreenState();
}

class _AddActivityScreenState extends State<AddActivityScreen> {
  late DateTime _day;

  late ActivitiesBloc _activitiesBloc;

  @override
  void initState() {
    _activitiesBloc = locator<ActivitiesBloc>();
    super.initState();
    // the user for the estimates, the recents
    _forkLoad();
  }

  @override
  void didChangeDependencies() {
    final args =
        ModalRoute.of(context)!.settings.arguments
            as AddActivityScreenArguments;
    _day = args.day;
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    // MacroFactor's list (ActivityAB), recent
    // activities as chips that log again, a row's minutes in a sheet
    return BlocBuilder<ActivitiesBloc, ActivitiesState>(
      bloc: _activitiesBloc,
      builder: (context, state) {
        if (state is ActivitiesInitial) {
          _activitiesBloc.add(LoadActivitiesEvent(context: context));
        }
        final s = S.of(context);
        return ActivityPickerView(
          title: 'Add activity',
          activities: state is ActivitiesLoadedState ? state.activities : null,
          error: state is ActivitiesFailedState
              ? ErrorDialog(
                  errorText: s.errorLoadingActivities,
                  onRefreshPressed: _onActivitiesRefreshButtonPressed,
                )
              : null,
          recent: _forkRecent,
          user: _forkUser,
          weightText: _forkUser == null
              ? null
              : formatBodyWeight(
                  _forkUser!.weightKG,
                  _forkUnit,
                  kgLabel: s.kgLabel,
                  lbLabel: s.lbsLabel,
                  stLabel: s.stLabel,
                ),
          day: _day,
          credit: _forkCredit,
          onSearch: (query) => _activitiesBloc.add(
            SearchActivitiesEvent(context: context, searchString: query),
          ),
          onLog: _forkLog,
          onOpenCustom: (_) => _onCustomActivityPressed(),
          onQuickAdd: _onQuickAddPressed,
          onCustom: _onCustomActivityPressed,
        );
      },
    );
  }

  UserEntity? _forkUser;
  BodyWeightUnit _forkUnit = BodyWeightUnit.kg;
  List<UserActivityEntity> _forkRecent = const [];

  /// What a logged activity does to the goal, for the minutes sheet.
  ActivityCredit _forkCredit = ActivityCredit.added;

  /// At most this many recent activities as chips.
  static const _forkRecentCount = 8;

  Future<void> _forkLoad() async {
    final user = await locator<GetUserUsecase>().getUserData();
    final config = await locator<ConfigRepository>().getConfig();
    final recent = await locator<GetUserActivityUsecase>()
        .getRecentUserActivity();
    if (!mounted) return;
    setState(() {
      _forkUser = user;
      _forkUnit = config.bodyWeightUnit;
      _forkRecent = recent
          .where((a) => a.physicalActivityEntity.isCustom || a.duration > 0)
          .take(_forkRecentCount)
          .toList();
    });
    final credit = await activityCredit();
    if (mounted) setState(() => _forkCredit = credit);
  }

  void _forkRefresh() {
    locator<HomeBloc>().add(const LoadItemsEvent());
    locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    locator<CalendarDayBloc>().add(RefreshCalendarDayEvent());
  }

  /// Logs [entry] on its day, then back to the dashboard with an Undo.
  Future<void> _forkLog(UserActivityEntity entry) async {
    await locator<LogUserActivityUsecase>().logActivity(entry, day: _day);
    _forkRefresh();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final name = entry.physicalActivityEntity.getName(context);
    final what = entry.physicalActivityEntity.isCustom
        ? name
        : '${entry.duration.round()} min ${name.toLowerCase()}';
    final day = _day;
    Navigator.of(
      context,
    ).popUntil(namedRouteOrFirst(NavigationOptions.mainRoute));
    messenger.showSnackBar(
      SnackBar(
        content: Text('Added $what'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await locator<CalendarDayBloc>().deleteUserActivityItem(
              messenger.context,
              entry,
              day,
            );
            _forkRefresh();
          },
        ),
      ),
    );
  }

  void _onQuickAddPressed() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickAddActivityBottomSheet(day: _day),
    );
  }

  void _onCustomActivityPressed() {
    Navigator.of(context).pushNamed(
      NavigationOptions.activityDetailRoute,
      arguments: ActivityDetailScreenArguments(
        PhysicalActivityEntity.custom,
        _day,
      ),
    );
  }

  void _onActivitiesRefreshButtonPressed() {
    _activitiesBloc.add(LoadActivitiesEvent(context: context));
  }
}
