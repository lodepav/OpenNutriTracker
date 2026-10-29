import 'package:flutter/material.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';

/// The macro program, or none for upstream's percentages; pops a record
/// so "off" and "cancelled" differ. Settings' Macros row and onboarding's
/// goal page open it. Grams per pound where body weight is in pounds
/// ([perLb]); the program keeps them per kg.
class MacroProgramDialog extends StatefulWidget {
  final MacroProgram? program;
  final bool perLb;

  const MacroProgramDialog(this.program, {super.key, this.perLb = false});

  @override
  State<MacroProgramDialog> createState() => _MacroProgramDialogState();
}

class _MacroProgramDialogState extends State<MacroProgramDialog> {
  late MacroProgram? _program = widget.program;
  bool _valid = true;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Macros'),
    content: SingleChildScrollView(
      child: MacroProgramForm(
        widget.program,
        perLb: widget.perLb,
        onChanged: (program, valid) => setState(() {
          _program = program;
          _valid = valid;
        }),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _valid
            ? () => Navigator.pop(context, (program: _program))
            : null,
        child: const Text('Save'),
      ),
    ],
  );
}

/// The dialog's fields: the program, or null when off, and whether the
/// typed values are numbers in range, to [onChanged] on every change. The
/// goal planner's macros step shows it on its own.
class MacroProgramForm extends StatefulWidget {
  final MacroProgram? program;
  final bool perLb;
  final void Function(MacroProgram? program, bool valid) onChanged;

  const MacroProgramForm(
    this.program, {
    super.key,
    this.perLb = false,
    required this.onChanged,
  });

  @override
  State<MacroProgramForm> createState() => _MacroProgramFormState();
}

class _MacroProgramFormState extends State<MacroProgramForm> {
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onChanged(_on ? _program : null, !_on || !(_proteinBad || _fatBad));
  }

  late bool _on = widget.program != null;
  late MacroProgram _program = widget.program ?? const MacroProgram();

  // A typed value stays manual even when it equals a preset.
  late bool _proteinManual = !_proteinPresets.contains(_program.proteinGPerKg);
  late bool _fatManual =
      _program.style == MacroStyle.perKg &&
      !MacroProgram.fatPresets.contains(_program.fatGPerKg);
  bool _proteinBad = false;
  bool _fatBad = false;

  List<double> get _proteinPresets => _program.leanMass
      ? MacroProgram.proteinPresetsLean
      : MacroProgram.proteinPresets;

  static const _levels = ['Moderate', 'High', 'Very high'];
  static const _fatLevels = ['Low', 'Moderate', 'High'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _program.style;
    final perLb = widget.perLb;
    String shown(double kg) => MacroProgram.perWeight(kg, perLb);
    final per = perLb ? 'lb' : 'kg';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const ValueKey('macro-program-on'),
          contentPadding: EdgeInsets.zero,
          title: Text('Protein and fat per $per'),
          subtitle: const Text(
            'In place of the percentages. Protein holds steady; carbs '
            'and fat take a weekday\'s shift.',
          ),
          value: _on,
          onChanged: (v) => setState(() => _on = v),
        ),
        if (_on) ...[
          Text('Protein', style: theme.textTheme.titleSmall),
          Wrap(
            spacing: 6,
            children: [
              for (final (i, kg) in _proteinPresets.indexed)
                ChoiceChip(
                  key: ValueKey('macro-protein-$i'),
                  label: Text('${_levels[i]} ${shown(kg)}'),
                  selected: !_proteinManual && _program.proteinGPerKg == kg,
                  onSelected: (_) => setState(() {
                    _proteinManual = false;
                    _proteinBad = false;
                    _program = _program.copyWith(proteinGPerKg: kg);
                  }),
                ),
              ChoiceChip(
                key: const ValueKey('macro-protein-manual'),
                label: const Text('Manual'),
                selected: _proteinManual,
                onSelected: (_) => setState(() => _proteinManual = true),
              ),
            ],
          ),
          if (_proteinManual)
            _PerKgField(
              key: const ValueKey('macro-protein-kg'),
              initial: _program.proteinGPerKg,
              min: 0.8,
              max: 3.5,
              perLb: perLb,
              onChanged: (kg) => setState(() {
                _proteinBad = kg == null;
                if (kg != null) {
                  _program = _program.copyWith(proteinGPerKg: kg);
                }
              }),
            ),
          Text(
            '${shown(_program.proteinGPerKg)} g per $per'
            '${_program.leanMass ? ' of lean mass' : ' of body weight'}',
            style: theme.textTheme.bodySmall,
          ),
          SwitchListTile(
            key: const ValueKey('macro-lean'),
            contentPadding: EdgeInsets.zero,
            title: Text('Per $per of lean mass'),
            subtitle: const Text(
              'Weight less body fat: your latest measured body fat %, '
              'or an estimate from your BMI and age.',
            ),
            value: _program.leanMass,
            // A preset moves to the same level of the other basis.
            onChanged: (v) => setState(() {
              final level = _proteinPresets.indexOf(_program.proteinGPerKg);
              _program = _program.copyWith(leanMass: v);
              if (!_proteinManual) {
                _program = _program.copyWith(
                  proteinGPerKg: _proteinPresets[level < 0 ? 0 : level],
                );
              }
            }),
          ),
          const SizedBox(height: 8),
          Text('Fat', style: theme.textTheme.titleSmall),
          Wrap(
            spacing: 6,
            children: [
              for (final (i, kg) in MacroProgram.fatPresets.indexed)
                ChoiceChip(
                  key: ValueKey('macro-fat-$i'),
                  label: Text('${_fatLevels[i]} ${shown(kg)}'),
                  selected:
                      style == MacroStyle.perKg &&
                      !_fatManual &&
                      _program.fatGPerKg == kg,
                  onSelected: (_) => setState(() {
                    _fatManual = false;
                    _fatBad = false;
                    _program = _program.copyWith(
                      style: MacroStyle.perKg,
                      fatGPerKg: kg,
                    );
                  }),
                ),
              ChoiceChip(
                key: const ValueKey('macro-fat-manual'),
                label: const Text('Manual'),
                selected: style == MacroStyle.perKg && _fatManual,
                onSelected: (_) => setState(() {
                  _fatManual = true;
                  _program = _program.copyWith(style: MacroStyle.perKg);
                }),
              ),
              for (final other in MacroStyle.values)
                // A style no longer offered shows only while it is saved.
                if (other == MacroStyle.lowCarb ||
                    other == MacroStyle.keto ||
                    (other != MacroStyle.perKg &&
                        widget.program?.style == other))
                  ChoiceChip(
                    key: ValueKey('macro-style-${other.name}'),
                    label: Text(other.label),
                    selected: style == other,
                    onSelected: (_) => setState(() {
                      _fatBad = false;
                      _program = _program.copyWith(style: other);
                    }),
                  ),
            ],
          ),
          if (style == MacroStyle.perKg && _fatManual)
            _PerKgField(
              key: const ValueKey('macro-fat-kg'),
              initial: _program.fatGPerKg,
              min: 0.3,
              max: 2.0,
              perLb: perLb,
              onChanged: (kg) => setState(() {
                _fatBad = kg == null;
                if (kg != null) {
                  _program = _program.copyWith(fatGPerKg: kg);
                }
              }),
            ),
          Text(
            style == MacroStyle.perKg
                ? '${shown(_program.fatGPerKg)} g per $per of '
                      'body weight, the rest carbs. Under about 20% of '
                      'your energy from fat is not advised.'
                : style.explanation,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// Grams per kg typed in, between [min] and [max]; null to [onChanged]
/// while the text is no such number. Typed per pound with [perLb], and
/// still told per kg.
class _PerKgField extends StatefulWidget {
  final double initial;
  final double min;
  final double max;
  final bool perLb;
  final ValueChanged<double?> onChanged;

  const _PerKgField({
    super.key,
    required this.initial,
    required this.min,
    required this.max,
    required this.perLb,
    required this.onChanged,
  });

  @override
  State<_PerKgField> createState() => _PerKgFieldState();
}

class _PerKgFieldState extends State<_PerKgField> {
  late final _text = TextEditingController(text: _shown(widget.initial));

  String _shown(double kg) =>
      widget.perLb ? MacroProgram.perWeight(kg, true) : '$kg';
  bool _bad = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      suffixText: MacroProgram.unitOf(widget.perLb),
      errorText: _bad
          ? 'From ${_shown(widget.min)} to ${_shown(widget.max)}'
          : null,
    ),
    onChanged: (text) {
      final typed = double.tryParse(text.trim().replaceAll(',', '.'));
      final kg = typed == null || !widget.perLb
          ? typed
          : typed * MacroProgram.lbPerKg;
      // A bound shown rounded is still in range.
      final slack = widget.perLb ? 0.005 * MacroProgram.lbPerKg : 0.0;
      final ok =
          kg != null && kg >= widget.min - slack && kg <= widget.max + slack;
      setState(() => _bad = !ok);
      widget.onChanged(ok ? kg : null);
    },
  );
}
