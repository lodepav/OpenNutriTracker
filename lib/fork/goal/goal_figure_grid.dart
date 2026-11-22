import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';

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
