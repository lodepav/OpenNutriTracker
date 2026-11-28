import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/screens/trends/trends_page.dart'
    show openTrendFromHome;
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/goal_saving.dart'
    show paceChanges;
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/body/side_compare.dart';
import 'package:opennutritracker/fork/body/waist_ratio.dart';
import 'package:opennutritracker/fork/phases/phases.dart' show PhaseStore;
import 'package:opennutritracker/fork/report/nutrient_explorer.dart'
    show intakesBetween;
import 'package:opennutritracker/fork/trends/nutrient_trends.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_overview.dart';
import 'package:opennutritracker/fork/weight/weigh_in_log.dart'
    show weighInChanges;
import 'package:opennutritracker/fork/trends/trends_widgets.dart'
    show Sparkline, TrendTile;

/// Trends' tiles whose number is a daily average, by id.
const _averaged = {
  'trends-tile-calories',
  'trends-tile-carbs',
  'trends-tile-fat',
  'trends-tile-protein',
  'trends-tile-fibre',
  'trends-tile-sugars',
  'trends-tile-sodium',
  'trends-tile-water',
};

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

  /// Read again for a new state, or once the measurements, the pace, the
  /// goals or the weigh-ins change.
  Future<_Extras>? _extras;
  TrendsLoaded? _extrasFor;

  // Completing a goal saves the pace before the history: the history's own
  // change reloads too.
  final _changes = Listenable.merge([
    MeasurementStore.changes,
    paceChanges,
    PhaseStore.changes,
    weighInChanges,
  ]);

  Future<_Extras> _extrasOf(TrendsLoaded state, List<DateTime> dates) {
    if (_extrasFor != state || _extras == null) {
      _extrasFor = state;
      _extras = _load(state, dates);
    }
    return _extras!;
  }

  Future<_Extras> _load(TrendsLoaded state, List<DateTime> dates) async {
    final needMicros = widget.ids.any(
      (id) => microLabels.keys.any((m) => m.name == id),
    );
    return (
      history: await widget.loadExpenditure().catchError(
        (Object _) => <ExpenditureDay>[],
      ),
      micros: needMicros
          ? await loadMicros(intakesBetween, dates, days: state.days)
          : null,
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
    _changes.addListener(_remeasure);
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
    _changes.removeListener(_remeasure);
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
        final dates = windowDates(state.logicalToday, state.windowDays);
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
            // Home has no range pills: a tile with a sparkline says its span.
            final span = rangeText(
              state.rangeDays,
              state.windowDays,
            ).toLowerCase();
            return widget.builder(
              _last = {
                for (final t in tiles)
                  if (widget.ids.contains(
                    t.id.substring('trends-tile-'.length),
                  ))
                    t.id.substring('trends-tile-'.length): TrendTile(
                      id: 'home-${t.id}',
                      // Home has no line saying these are averages.
                      label: _averaged.contains(t.id)
                          ? '${t.label} · avg'
                          : t.label,
                      value: t.value,
                      valueColor: t.valueColor,
                      suffix: switch ([
                        ?t.suffix,
                        ?t.note,
                        if (t.chart is Sparkline) span,
                      ]) {
                        [] => null,
                        final parts => parts.join(' · '),
                      },
                      // No room kept for a tile with no chart.
                      chart: t.chart is SizedBox ? null : t.chart,
                      onTap: t.onTap,
                      // Read as on Trends, in words, not the tile's text.
                      spokenLabel: t.spokenLabel,
                      hint: 'Open ${t.label}',
                    ),
              },
            );
          },
        );
      },
    ),
  );
}
