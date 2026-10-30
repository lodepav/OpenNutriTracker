import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/trends_page.dart'
    show openTrendFromHome;
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan_card.dart'
    show paceChanges;
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/body/side_compare.dart';
import 'package:opennutritracker/fork/body/waist_ratio.dart';
import 'package:opennutritracker/fork/display/home_tiles.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart'
    show intakesBetween;
import 'package:opennutritracker/fork/trends/nutrient_trends.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_overview.dart';

/// What the Trends tiles on Home read besides Trends' state.
typedef _Extras = ({
  List<ExpenditureDay> history,
  MicroData? micros,
  List<Measurement> measurements,
  TrendsGoal? goal,
  BodyFrame? frame,
});

/// Trends' tiles added to Home, [ids] of them, as Home's tiles:
/// over Trends' window, each opening the page its Trends tile opens.
/// [builder] lays them out with Home's own, by id; none until Trends'
/// state is loaded.
class HomeTrendTiles extends StatefulWidget {
  final Set<String> ids;
  final Future<List<ExpenditureDay>> Function() loadExpenditure;
  final Widget Function(Map<String, Widget> tiles) builder;

  /// For tests; the app's from the locator.
  final TrendsBloc? bloc;

  /// Home's reloads, after something was logged; the tiles read Trends
  /// again on each. For tests; the app's from the locator.
  final Stream<Object?>? homeLoads;

  const HomeTrendTiles({
    super.key,
    required this.ids,
    required this.loadExpenditure,
    required this.builder,
    this.bloc,
    this.homeLoads,
  });

  @override
  State<HomeTrendTiles> createState() => _HomeTrendTilesState();
}

class _HomeTrendTilesState extends State<HomeTrendTiles> {
  late final TrendsBloc _bloc = widget.bloc ?? locator<TrendsBloc>();
  StreamSubscription<Object?>? _homeLoads;

  /// The tiles last built, shown while Trends reloads, so Home's grid
  /// keeps its arrangement.
  Map<String, Widget> _last = const {};

  /// Read again for a new state, or once the measurements or the pace
  /// change.
  Future<_Extras>? _extras;
  TrendsLoaded? _extrasFor;

  Future<_Extras> _extrasOf(TrendsLoaded state, List<DateTime> dates) {
    if (_extrasFor != state || _extras == null) {
      _extrasFor = state;
      _extras = _load(dates);
    }
    return _extras!;
  }

  Future<_Extras> _load(List<DateTime> dates) async {
    final needMicros = widget.ids.any(
      (id) => microLabels.keys.any((m) => m.name == id),
    );
    return (
      history: await widget.loadExpenditure().catchError(
        (Object _) => <ExpenditureDay>[],
      ),
      micros: needMicros ? await loadMicros(intakesBetween, dates) : null,
      measurements: widget.ids.contains('sides') || widget.ids.contains('waist')
          ? await TrendsOverview.loadMeasurements().catchError(
              (Object _) => <Measurement>[],
            )
          : const <Measurement>[],
      goal: widget.ids.contains('goal') ? await TrendsOverview.goal() : null,
      frame: widget.ids.contains('waist') ? await loadBodyFrame() : null,
    );
  }

  void _remeasure() => setState(() => _extras = null);

  @override
  void initState() {
    super.initState();
    if (_bloc.state is! TrendsLoaded) _bloc.add(const LoadTrendsEvent());
    SidePartPref.ensureLoaded();
    MeasurementStore.changes.addListener(_remeasure);
    paceChanges.addListener(_remeasure);
    final homeLoads =
        widget.homeLoads ??
        (locator.isRegistered<HomeBloc>()
            ? locator<HomeBloc>().stream.where((s) => s is HomeLoadedState)
            : null);
    _homeLoads = homeLoads?.listen(
      (_) => _bloc.add(const RefreshTrendsEvent()),
    );
  }

  @override
  void didUpdateWidget(HomeTrendTiles old) {
    super.didUpdateWidget(old);
    // One added may want what was not read.
    if (!old.ids.containsAll(widget.ids)) _extras = null;
  }

  @override
  void dispose() {
    MeasurementStore.changes.removeListener(_remeasure);
    paceChanges.removeListener(_remeasure);
    _homeLoads?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: SidePartPref.current,
    builder: (context, _, _) => BlocBuilder<TrendsBloc, TrendsState>(
      bloc: _bloc,
      builder: (context, state) {
        if (state is! TrendsLoaded) return widget.builder(_last);
        final now = DateTime.now();
        final dates = windowDates(
          DateTime(now.year, now.month, now.day),
          state.windowDays,
        );
        return FutureBuilder(
          future: _extrasOf(state, dates),
          builder: (context, snapshot) {
            final extras = snapshot.data;
            if (extras == null) return widget.builder(_last);
            final tiles = trendTiles(
              context,
              state,
              dates: dates,
              history: extras.history,
              micros: extras.micros,
              measurements: extras.measurements,
              goal: extras.goal,
              frame: extras.frame,
              open: (m) => openTrendFromHome(context, m),
            );
            return widget.builder(
              _last = {
                for (final t in tiles)
                  if (widget.ids.contains(
                    t.id.substring('trends-tile-'.length),
                  ))
                    t.id.substring('trends-tile-'.length): HomeTile(
                      identifier: 'home-${t.id}',
                      title: t.label,
                      value: t.value,
                      valueColor: t.valueColor,
                      note: t.suffix,
                      // No room kept for a tile with no chart.
                      below: t.chart is SizedBox ? null : t.chart,
                      onTap: t.onTap,
                      hint: 'Open ${t.label.replaceAll(' · avg', '')}',
                    ),
              },
            );
          },
        );
      },
    ),
  );
}
