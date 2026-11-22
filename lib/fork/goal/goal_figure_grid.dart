import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';

/// [tile], whose value shows a dash, read as "[label], no data" and its
/// [note]. Only for a tile with no tap: this read replaces its own.
Widget noDataTile(String label, Widget tile, {String? note}) => Semantics(
  label: [label, 'no data', ?note].join(', '),
  excludeSemantics: true,
  child: tile,
);

/// [FigureGrid] whose last tile, left alone in its row, spans the row.
// shortcut: only the goal pages get it; FigureGrid itself is the place
// once the trends pages want it too.
class GoalFigureGrid extends StatelessWidget {
  final List<Widget> tiles;

  const GoalFigureGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final paired = tiles.length - tiles.length % 2;
    return Column(
      spacing: Dimens.spacing8,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (paired > 0) FigureGrid(tiles: tiles.sublist(0, paired)),
        if (paired < tiles.length) tiles.last,
      ],
    );
  }
}
