import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/layout/width_cap.dart';

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

  /// The theme's primary for the first card, as the rows inside use, muted
  /// for the second: not the macro colours, which mean carbs, fat and
  /// protein everywhere else (H4).
  Color colorIn(BuildContext context) => isFirstCard
      ? Theme.of(context).colorScheme.primary
      : paletteOf(context).textMuted;
}

/// A row of a section, for the search, with other words it goes by
/// ([also]: "kJ" for the energy unit).
typedef SettingsEntry = ({String label, SettingsSection section, String also});

/// [entries] whose label, section or other words have a word starting with
/// each word of [query]: "ai" finds "AI meal assistance", not "Daily".
List<SettingsEntry> matchingSettings(
  List<SettingsEntry> entries,
  String query,
) {
  // Unicode-aware, for the translated labels: "énergie" is one word
  final split = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  List<String> wordsOf(String text) =>
      text.toLowerCase().split(split).where((w) => w.isNotEmpty).toList();
  final words = wordsOf(query);
  if (words.isEmpty) return const [];
  return [
    for (final e in entries)
      if (words.every(
        (w) => wordsOf(
          '${e.label} ${e.section.title} ${e.also}',
        ).any((word) => word.startsWith(w)),
      ))
        e,
  ];
}

/// The sections, each with what is set in it now.
class SettingsIndex extends StatelessWidget {
  final Map<SettingsSection, String> summaries;

  /// Sections whose summary reports a failure, drawn in the error colour.
  final Set<SettingsSection> failing;
  final ValueChanged<SettingsSection> onOpen;

  const SettingsIndex({
    super.key,
    required this.summaries,
    this.failing = const {},
    required this.onOpen,
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
              failing: failing.contains(s),
              onTap: () => onOpen(s),
            ),
          ],
        ],
      ),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(
        Dimens.spacing12,
        Dimens.spacing8,
        Dimens.spacing12,
        Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        card(SettingsSection.values.where((s) => s.isFirstCard)),
        const SizedBox(height: Dimens.spacing12),
        card(SettingsSection.values.where((s) => !s.isFirstCard)),
      ].map<Widget>((c) => WidthCap(child: c)).toList(),
    );
  }
}

class _SectionRow extends StatelessWidget {
  final SettingsSection section;
  final String? summary;
  final bool failing;
  final VoidCallback onTap;

  const _SectionRow({
    required this.section,
    required this.summary,
    required this.failing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final summary = this.summary;
    // Merged at the top, so the button says what it is (A2).
    return MergeSemantics(
      child: Semantics(
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
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: section.colorIn(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        section.icon,
                        // A dynamic primary can be pale, as in dark themes;
                        // so is the muted fill in the dark theme
                        color: section.isFirstCard
                            ? Theme.of(context).colorScheme.onPrimary
                            : AppPalette.readableOn(section.colorIn(context)),
                        size: 22,
                      ),
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
                              color: failing
                                  ? Theme.of(context).colorScheme.error
                                  : palette.textMuted,
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

/// Every row by name; a result opens its section at the row.
class SettingsSearchPage extends StatefulWidget {
  final List<SettingsEntry> entries;
  final ValueChanged<SettingsEntry> onOpen;

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
                  WidthCap(
                    child: ListTile(
                      leading: Icon(e.section.icon),
                      title: Text(e.label),
                      subtitle: Text(e.section.title),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => widget.onOpen(e),
                    ),
                  ),
              ],
            ),
    );
  }
}
