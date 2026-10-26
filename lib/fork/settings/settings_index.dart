import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// Seam S129: Settings as MacroFactor's (SettingsB), a page for each of
/// these, in this order.
enum SettingsSection {
  goals('Goals & nutrition', Icons.track_changes_rounded),
  units('Units', Icons.straighten_rounded),
  reminders('Reminders', Icons.notifications_rounded),
  food('Food databases', Icons.travel_explore_rounded),
  data('Data', Icons.save_rounded),
  appearance('Appearance', Icons.palette_rounded),
  about('About', Icons.info_outline_rounded);

  final String title;
  final IconData icon;

  const SettingsSection(this.title, this.icon);

  /// The first four are what people come to change; the rest, a second card.
  bool get isFirstCard => index < 4;

  Color colorIn(AppPalette palette, ColorScheme scheme) => switch (this) {
    goals => palette.accent,
    units => palette.proteinColor,
    reminders => palette.carbsColor,
    food => scheme.secondary,
    _ => palette.textMuted,
  };
}

/// A row of a section, for the search, with other words it goes by
/// ([also]: "kJ" for the energy unit).
typedef SettingsEntry = ({String label, SettingsSection section, String also});

/// [entries] whose label, section or other words have every word of
/// [query] in them.
List<SettingsEntry> matchingSettings(
  List<SettingsEntry> entries,
  String query,
) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  return [
    for (final e in entries)
      if (words.every(
        (w) =>
            e.label.toLowerCase().contains(w) ||
            e.section.title.toLowerCase().contains(w) ||
            e.also.toLowerCase().contains(w),
      ))
        e,
  ];
}

/// The sections, each with what is set in it now.
class SettingsIndex extends StatelessWidget {
  final Map<SettingsSection, String> summaries;
  final ValueChanged<SettingsSection> onOpen;

  /// Under the cards: the app's version banner.
  final Widget? footer;

  const SettingsIndex({
    super.key,
    required this.summaries,
    required this.onOpen,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    Widget card(Iterable<SettingsSection> sections) => AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, s) in sections.indexed) ...[
            if (i > 0) Divider(height: 1, color: palette.surfaceMuted),
            _SectionRow(
              section: s,
              summary: summaries[s],
              onTap: () => onOpen(s),
            ),
          ],
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing12,
        Dimens.spacing8,
        Dimens.spacing12,
        Dimens.spacing32,
      ),
      children: [
        card(SettingsSection.values.where((s) => s.isFirstCard)),
        const SizedBox(height: Dimens.spacing12),
        card(SettingsSection.values.where((s) => !s.isFirstCard)),
        if (footer != null) ...[
          const SizedBox(height: Dimens.spacing24),
          footer!,
        ],
      ],
    );
  }
}

class _SectionRow extends StatelessWidget {
  final SettingsSection section;
  final String? summary;
  final VoidCallback onTap;

  const _SectionRow({
    required this.section,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final summary = this.summary;
    return Semantics(
      identifier: 'settings-section-${section.name}',
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Dimens.spacing12,
              vertical: Dimens.spacing8,
            ),
            child: MergeSemantics(
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: section.colorIn(
                          palette,
                          Theme.of(context).colorScheme,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(section.icon, color: Colors.white, size: 22),
                    ),
                  ),
                  const SizedBox(width: Dimens.spacing12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.title,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (summary != null && summary.isNotEmpty)
                          Text(
                            summary,
                            style: text.bodySmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ExcludeSemantics(
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: palette.textMuted,
                    ),
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

/// Every row by name; a result opens its section.
class SettingsSearchPage extends StatefulWidget {
  final List<SettingsEntry> entries;
  final ValueChanged<SettingsSection> onOpen;

  const SettingsSearchPage({
    super.key,
    required this.entries,
    required this.onOpen,
  });

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final found = matchingSettings(widget.entries, _query);
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        title: Semantics(
          identifier: 'settings-search-field',
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search settings',
              border: InputBorder.none,
            ),
            onChanged: (q) => setState(() => _query = q),
          ),
        ),
      ),
      body: _query.trim().isEmpty
          ? const SizedBox.shrink()
          : found.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(Dimens.spacing24),
              child: Text(
                'No setting by that name',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted),
              ),
            )
          : ListView(
              children: [
                for (final e in found)
                  ListTile(
                    leading: Icon(e.section.icon),
                    title: Text(e.label),
                    subtitle: Text(e.section.title),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => widget.onOpen(e.section),
                  ),
              ],
            ),
    );
  }
}
