import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/url_const.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/core/utils/safe_url_launcher.dart';

/// Surfaces the peer-reviewed sources behind every health/medical
/// calculation OpenNutriTracker shows. Reachable from the Home dashboard,
/// the BMI overview on the Profile tab, both gender-selection screens,
/// and the disclaimer dialog — so anyone scanning the app for citations
/// (Apple's reviewers included) can find them within one tap.
class SourcesScreen extends StatelessWidget {
  // [fork] S304 sources-anchor: a caller's info button opens at its entry
  // const SourcesScreen({super.key});
  /// The title of the entry to open scrolled to; null opens at the top.
  final String? initialEntry;

  const SourcesScreen({super.key, this.initialEntry});
  // [/fork]

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final entries = <_SourceEntry>[
      _SourceEntry(
        title: l10n.sourcesEnergyTitle,
        description: l10n.sourcesEnergyDescription,
        sources: const [
          _SourceLink(
            citation:
                // [fork] S416 sources-cited-once: the chapter the inline
                // "Source:" gave, which the card no longer prints
                // 'Institute of Medicine (2005). Dietary Reference Intakes for '
                // 'Energy, Carbohydrate, Fiber, Fat, Fatty Acids, Cholesterol, '
                // 'Protein, and Amino Acids. National Academies Press.',
                'Institute of Medicine (2005). Dietary Reference Intakes for '
                'Energy, Carbohydrate, Fiber, Fat, Fatty Acids, Cholesterol, '
                'Protein, and Amino Acids, Chapter 5 and Table 5-5. National '
                'Academies Press.',
                // [/fork]
            url: URLConst.sourceEnergyIomDriURL,
          ),
        ],
      ),
      _SourceEntry(
        title: l10n.sourcesBmiTitle,
        description: l10n.sourcesBmiDescription,
        sources: const [
          _SourceLink(
            citation:
                'World Health Organization. Body mass index (BMI), adult '
                'classification. WHO Global Health Observatory.',
            url: URLConst.sourceBmiWhoURL,
          ),
        ],
      ),
      _SourceEntry(
        title: l10n.sourcesMacrosTitle,
        description: l10n.sourcesMacrosDescription,
        sources: const [
          _SourceLink(
            citation:
                'World Health Organization (2003). Diet, Nutrition and the '
                'Prevention of Chronic Diseases. WHO Technical Report '
                'Series 916.',
            url: URLConst.sourceMacrosWhoTrs916URL,
          ),
        ],
      ),
      _SourceEntry(
        title: l10n.sourcesActivityTitle,
        description: l10n.sourcesActivityDescription,
        sources: const [
          _SourceLink(
            citation:
                'Herrmann SD, et al. (2024). 2024 Adult Compendium of '
                'Physical Activities. Journal of Sport and Health Science.',
            url: URLConst.sourceActivityCompendium2024URL,
          ),
        ],
      ),
      _SourceEntry(
        title: l10n.sourcesEnergyCompensationTitle,
        description: l10n.sourcesEnergyCompensationDescription,
        sources: const [
          _SourceLink(
            citation:
                'Careau V, et al. (2021). Energy compensation and adiposity '
                'in humans. Current Biology, 31(20):4659–4666.e2.',
            url: URLConst.sourceEnergyCompensationCareau2021URL,
          ),
          _SourceLink(
            citation:
                'Borrud LG, et al. (2010). Body composition data for '
                'individuals 8 years of age and older: U.S. population, '
                '1999–2004. National Center for Health Statistics, Vital and '
                'Health Statistics Series 11, No. 250.',
            url: URLConst.sourceBodyCompositionBorrud2010URL,
          ),
        ],
      ),
      _SourceEntry(
        title: l10n.sourcesNonBinaryTitle,
        description: l10n.sourcesNonBinaryDescription,
        sources: const [
          _SourceLink(
            citation:
                'Linsenmeyer W, Waters J (2021). Sex and gender differences '
                'in nutrition research: considerations with the transgender '
                'and gender nonconforming population. Nutrition Journal, '
                '20:6.',
            url: URLConst.sourceInclusiveDesignLinsenmeyer2021URL,
          ),
          _SourceLink(
            citation:
                'Wiik A, et al. (2018). Metabolic and functional changes in '
                'transgender individuals following cross-sex hormone '
                'treatment: Design and methods of the GETS study. '
                'Contemporary Clinical Trials Communications, 10:148–153.',
            url: URLConst.sourceTransMetabolismWiik2018URL,
          ),
          _SourceLink(
            citation:
                'Linsenmeyer W, Drallmeier T, Thomure M (2020). Towards '
                'gender-affirming nutrition assessment: a case series of '
                'adult transgender men with distinct nutrition '
                'considerations. Nutrition Journal, 19:74.',
            url: URLConst.sourceTransNutritionLinsenmeyer2020URL,
          ),
        ],
      ),
      _SourceEntry(
        title: l10n.sourcesNutrientReferenceTitle,
        description: l10n.sourcesNutrientReferenceDescription,
        sources: const [
          _SourceLink(
            citation:
                'Institute of Medicine. Dietary Reference Intakes: The '
                'Essential Guide to Nutrient Requirements. Summary Report. '
                'National Academies Press.',
            url: URLConst.sourceNutrientReferenceIomURL,
          ),
        ],
      ),
      // [fork] S415 sources-own-method: the numbers Home shows first, which
      // no single paper gives; what each step rests on is cited
      const _SourceEntry(
        title: 'Expenditure and weight trend',
        description:
            "The expenditure and weight trend are the app's own method, "
            'built on the structure MacroFactor describes. Weigh-ins are '
            'filled in day by day and smoothed into a trend, as in The '
            "Hacker's Diet. Expenditure starts from the Institute of Medicine "
            'estimate above, then follows what you logged less the energy '
            "stored in the trend's change over 20 days: about 9,400 kcal a kg "
            "of fat and 1,800 of lean, the fat share by Forbes's rule as Hall "
            '(2008) applies it, with body fat from your latest measurement or '
            'else estimated from BMI (Deurenberg 1991). How fast it follows a '
            "change is the app's own choice, tested in simulation; no paper "
            'covers it. '
            'Settings → Goals & nutrition → How your goal is calculated shows '
            'each step with your numbers.',
        sources: [
          _SourceLink(
            citation: 'MacroFactor. Expenditure. MacroFactor help centre.',
            url: 'https://help.macrofactorapp.com/en/articles/20-expenditure',
          ),
          _SourceLink(
            citation: "Walker J. The Hacker's Diet. Fourmilab.",
            url:
                'https://fourmilab.ch/hackdiet/www/subsubsection1_2_4_0_4_4.html',
          ),
          _SourceLink(
            citation:
                'Hall KD (2008). What is the required energy deficit per unit '
                'weight loss? International Journal of Obesity.',
            url: 'https://pubmed.ncbi.nlm.nih.gov/17848938/',
          ),
          _SourceLink(
            citation:
                'Deurenberg P, Weststrate JA, Seidell JC (1991). Body mass '
                'index as a measure of body fatness: age- and sex-specific '
                'prediction formulas. British Journal of Nutrition.',
            url: 'https://pubmed.ncbi.nlm.nih.gov/2043597',
          ),
        ],
      ),
      // [/fork]
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSourcesLabel)),
      // [fork] S304 sources-anchor: every card is built, so the anchored one
      // exists to scroll to (a lazy ListView had not built the fifth)
      // body: ListView(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16, vertical: Dimens.spacing16),
        // children: [
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // The intro claims only what is listed (round-3 critique)
          // Text(
          //   l10n.sourcesScreenIntro,
          //   style: Theme.of(context).textTheme.bodyMedium,
          // ),
          Text(
            'The calculations below follow the sources cited under each '
            'one, so you can check a number yourself.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Dimens.spacing16),
          // ...entries.map((entry) => _SourceCard(entry: entry)),
          ...entries.map(
            (entry) => entry.title == initialEntry
                ? _ScrollIntoView(child: _SourceCard(entry: entry))
                : _SourceCard(entry: entry),
          ),
          ],
        ),
      ),
      // [/fork]
    );
  }
}

// [fork] S304 sources-anchor: scrolls its child to the top once laid out
class _ScrollIntoView extends StatefulWidget {
  final Widget child;

  const _ScrollIntoView({required this.child});

  @override
  State<_ScrollIntoView> createState() => _ScrollIntoViewState();
}

class _ScrollIntoViewState extends State<_ScrollIntoView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Scrollable.ensureVisible(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
// [/fork]

class _SourceEntry {
  final String title;
  final String description;
  final List<_SourceLink> sources;

  const _SourceEntry({
    required this.title,
    required this.description,
    required this.sources,
  });
}

class _SourceLink {
  // Paper citations stay in English by academic convention — the journal,
  // authors, and title are the canonical record regardless of the user's
  // app language.
  final String citation;
  final String url;

  const _SourceLink({required this.citation, required this.url});
}

class _SourceCard extends StatelessWidget {
  final _SourceEntry entry;

  const _SourceCard({required this.entry});

  Future<void> _launch(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorText = S.of(context).errorOpeningBrowser;
    if (await tryLaunchExternalUrl(url)) return;
    messenger.showSnackBar(SnackBar(content: Text(errorText)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing12),
      child: AppCard(
        padding: const EdgeInsets.all(Dimens.spacing16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // [fork] S305 sources-a11y: titles are headings, so TalkBack can
            // jump card to card
            Semantics(
              header: true,
              child: Text(
                entry.title,
                style: theme.textTheme.titleMedium,
              ),
            ),
            // Text(
            //   entry.title,
            //   style: theme.textTheme.titleMedium,
            // ),
            // [/fork]
            const SizedBox(height: Dimens.spacing8),
            // [fork] S416 sources-cited-once: the italic citation below
            // already names it
            // Text(
            //   entry.description,
            //   style: theme.textTheme.bodyMedium,
            // ),
            Text(
              entry.description.replaceFirst(
                RegExp(r'\s*Source: .*$', dotAll: true),
                '',
              ),
              style: theme.textTheme.bodyMedium,
            ),
            // [/fork]
            const SizedBox(height: Dimens.spacing12),
            ...entry.sources.map(
              (source) => Padding(
                padding: const EdgeInsets.only(bottom: Dimens.spacing4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.citation,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => _launch(context, source.url),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        // [fork] S305 sources-a11y: 48 dp, and each says which
                        // source it opens rather than all "View source"
                        // label: Text(S.of(context).sourcesOpenSourceLabel),
                        label: Text(
                          S.of(context).sourcesOpenSourceLabel,
                          semanticsLabel:
                              '${S.of(context).sourcesOpenSourceLabel}: '
                              '${_shortCitation(source.citation)}',
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing8),
                          // minimumSize: const Size(0, 32),
                          // tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: const Size(48, 48),
                        ),
                        // [/fork]
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// [fork] S305 sources-a11y: the author and year ("Careau V, et al. (2021)"),
// or the author alone where the citation has no year
String _shortCitation(String citation) =>
    RegExp(r'^[^()]*?\(\d{4}\)').stringMatch(citation) ??
    citation.split('.').first;
// [/fork]
