import 'package:flutter/material.dart';

/// Above this text scale the choices stack as a list: segments break
/// mid-word at 200%.
const stackedTextScale = 1.3;

/// One of [values], as segments, or a list of checked rows at large text.
class StackingChoice<T> extends StatelessWidget {
  final String identifier;
  final List<T> values;
  final String Function(T) label;
  final T selected;
  final ValueChanged<T>? onChanged;

  /// Around the segments; the stacked rows keep their own.
  final EdgeInsetsGeometry padding;

  /// Names the group for TalkBack.
  final String? groupLabel;

  const StackingChoice({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.groupLabel,
    required this.identifier,
    required this.values,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final stacked =
        MediaQuery.textScalerOf(context).scale(10) / 10 > stackedTextScale;
    if (stacked) {
      return Semantics(
        identifier: identifier,
        container: true,
        label: groupLabel,
        child: Column(
          children: [
            for (final v in values)
              ListTile(
                enabled: onChanged != null,
                selected: v == selected,
                title: Text(label(v)),
                trailing: v == selected
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: onChanged == null ? null : () => onChanged!(v),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Semantics(
        identifier: identifier,
        container: true,
        label: groupLabel,
        child: SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [
            for (final v in values)
              ButtonSegment(value: v, label: Text(label(v))),
          ],
          selected: {selected},
          onSelectionChanged: onChanged == null
              ? null
              : (picked) => onChanged!(picked.single),
        ),
      ),
    );
  }
}
