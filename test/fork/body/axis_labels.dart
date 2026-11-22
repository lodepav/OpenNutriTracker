import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The chart's axis numbers (A6): each on one line, none over another.
void expectAxisReadable(WidgetTester tester) {
  final rects = <(String, Rect)>[];
  for (final element
      in find
          .descendant(
            of: find.byType(LineChart),
            matching: find.byType(RichText),
          )
          .evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text.toPlainText();
    expect(
      paragraph.size.width + 0.5,
      greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
      reason: '"$text" wraps',
    );
    rects.add((text, paragraph.localToGlobal(Offset.zero) & paragraph.size));
  }
  expect(rects, isNotEmpty);
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      expect(
        rects[i].$2.intersect(rects[j].$2).height > 0.5 &&
            rects[i].$2.intersect(rects[j].$2).width > 0.5,
        isFalse,
        reason: '"${rects[i].$1}" overlaps "${rects[j].$1}"',
      );
    }
  }
}
