import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_display_name.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/profile_avatar.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/display/home_tiles.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// Seam S121: the You tab as MacroFactor's (YouA). Who is active, with a
/// Switch button for the profile sheet.
class YouProfileRow extends StatelessWidget {
  final ProfileEntity? profile;

  /// "29 · 178 cm · Male".
  final String details;
  final VoidCallback onSwitch;

  const YouProfileRow({
    super.key,
    required this.profile,
    required this.details,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final profile = this.profile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing4,
        0,
        Dimens.spacing4,
        Dimens.spacing12,
      ),
      child: Row(
        children: [
          if (profile != null) ...[
            ProfileAvatar(profile: profile, radius: 24),
            const SizedBox(width: Dimens.spacing12),
          ],
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (profile != null)
                    Text(
                      profileDisplayName(context, profile),
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    details,
                    style: text.bodySmall?.copyWith(
                      color: paletteOf(context).textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (profile != null)
            Semantics(
              identifier: 'profile-switcher',
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  side: BorderSide(color: paletteOf(context).border),
                ),
                onPressed: onSwitch,
                child: const Text('Switch', semanticsLabel: 'Switch profile'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Four tiles, two to a row, each row as tall as its taller tile.
class YouTiles extends StatelessWidget {
  final List<Widget> tiles;

  const YouTiles({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < tiles.length; i += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: Dimens.spacing8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: Dimens.spacing8),
                Expanded(
                  child: i + 1 < tiles.length
                      ? tiles[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

/// Today's energy goal and macro goals, as Home has them; a dash before
/// Home has loaded.
class BudgetTile extends StatelessWidget {
  final VoidCallback onTap;

  const BudgetTile({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (!locator.isRegistered<HomeBloc>()) return _tile(context, null);
    return BlocBuilder<HomeBloc, HomeState>(
      bloc: locator<HomeBloc>(),
      builder: (context, state) =>
          _tile(context, state is HomeLoadedState ? state : null),
    );
  }

  Widget _tile(BuildContext context, HomeLoadedState? state) {
    final macros = state == null
        ? null
        : inMacroOrder(
            carbs: 'C ${state.totalCarbsGoal.round()}',
            fat: 'F ${state.totalFatsGoal.round()}',
            protein: 'P ${state.totalProteinsGoal.round()}',
          ).join(' · ');
    return HomeTile(
      identifier: 'profile-budget',
      title: 'Daily budget',
      value: state == null
          ? '—'
          : '${energyValue(context, state.totalKcalDaily)}',
      note: energyUnit(context),
      hint: 'How it is worked out',
      onTap: onTap,
      below: macros == null ? null : _Below('$macros g'),
    );
  }
}

/// A tile's line under its value.
class _Below extends StatelessWidget {
  final String text;

  const _Below(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: paletteOf(context).textMuted),
  );
}

/// A tile of the grid with a line of text under its value.
class YouTile extends StatelessWidget {
  final String identifier;
  final String title;
  final String value;
  final String? note;
  final String? below;
  final String? hint;
  final VoidCallback onTap;

  const YouTile({
    super.key,
    required this.identifier,
    required this.title,
    required this.value,
    this.note,
    this.below,
    this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => HomeTile(
    identifier: identifier,
    title: title,
    value: value,
    note: note,
    hint: hint,
    onTap: onTap,
    below: below == null ? null : _Below(below!),
  );
}

/// A titled group of rows.
class YouSection extends StatelessWidget {
  final String title;
  final List<Widget> rows;

  const YouSection({super.key, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing4,
            Dimens.spacing12,
            Dimens.spacing4,
            Dimens.spacing8,
          ),
          child: Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0) Divider(height: 1, color: palette.surfaceMuted),
                row,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A row: what it is on the left, its value and a chevron on the right.
class YouRow extends StatelessWidget {
  final String identifier;
  final String label;
  final String? value;

  /// Under the value, smaller (the distance to the target weight).
  final String? detail;
  final VoidCallback onTap;

  const YouRow({
    super.key,
    required this.identifier,
    required this.label,
    this.value,
    this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = paletteOf(context).textMuted;
    return Semantics(
      identifier: identifier,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Dimens.spacing16,
              vertical: Dimens.spacing8,
            ),
            child: MergeSemantics(
              child: Row(
                children: [
                  Expanded(child: Text(label, style: text.bodyLarge)),
                  const SizedBox(width: Dimens.spacing12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (value != null)
                          Text(
                            value!,
                            textAlign: TextAlign.end,
                            style: text.bodyMedium?.copyWith(color: muted),
                          ),
                        if (detail != null && detail!.isNotEmpty)
                          Text(
                            detail!,
                            textAlign: TextAlign.end,
                            style: text.bodySmall?.copyWith(color: muted),
                          ),
                      ],
                    ),
                  ),
                  ExcludeSemantics(
                    child: Icon(Icons.chevron_right_rounded, color: muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row with a switch.
class YouSwitchRow extends StatelessWidget {
  final String identifier;
  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  const YouSwitchRow({
    super.key,
    required this.identifier,
    required this.label,
    this.detail,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: identifier,
    child: SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
      title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      subtitle: detail == null
          ? null
          : Text(
              detail!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: paletteOf(context).textMuted,
              ),
            ),
      value: value,
      onChanged: onChanged,
    ),
  );
}
