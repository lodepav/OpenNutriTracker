import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tappable nodes on screen that sit inside another, by identifier or
/// label. A row whose tap takes in its card's other rows makes a reader say
/// the card as one, and go to the first row on a tap of any; none is right.
List<String> tapsInTaps(WidgetTester tester) {
  final found = <String>[];
  void visit(SemanticsNode node, bool inTap) {
    // A switch merged into its row is read with it, as one.
    if (node.isMergedIntoParent) return;
    final data = node.getSemanticsData();
    final tap = data.hasAction(SemanticsAction.tap);
    if (tap && inTap) {
      found.add(data.identifier.isEmpty ? data.label : data.identifier);
    }
    node.visitChildren((child) {
      visit(child, inTap || tap);
      return true;
    });
  }

  final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
  visit(owner.rootSemanticsNode!, false);
  return found;
}
