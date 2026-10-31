import 'package:flutter/material.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/layout/arrange_screen.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Home's tiles (S119), by id in their first order.
const homeTileNames = {
  'weight': 'Weight trend',
  'expenditure': 'Expenditure',
  'water': 'Water',
  'fasting': 'Fasting',
};

/// Trends' tiles Home can add, off until switched on in Arrange
/// Home; by their Trends ids. Weight, expenditure and water have Home's.
const homeTrendTileNames = {
  'calories': 'Energy',
  'balance': 'Energy balance',
  'carbs': 'Carbs',
  'fat': 'Fat',
  'protein': 'Protein',
  'fibre': 'Fibre',
  'sugars': 'Sugars',
  'sodium': 'Salt',
  'goal': 'Goal',
  'sides': 'Left vs right',
  'waist': 'Waist to height',
};

const homeTilesKey = 'homeTiles';
const homeSectionsKey = 'homeSections';

/// Home's sections (S162), by id in their first order. 'notices' (the
/// empty-day hint and the low-energy warning) is not in the editor: it
/// keeps its place after the meal plan wherever that goes.
Map<String, String> homeSectionNames(BuildContext context) => {
  'dashboard': 'Summary',
  'tiles': 'Tiles',
  'checkIn': 'Weekly check-in',
  'plan': 'Meal plan',
  'activity': S.of(context).activityLabel,
  'breakfast': S.of(context).breakfastLabel,
  'lunch': S.of(context).lunchLabel,
  'dinner': S.of(context).dinnerLabel,
  'snack': S.of(context).snackLabel,
};

/// Opens "Arrange Home": its sections, and its tiles but those hidden in
/// Settings.
void openArrangeHome(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (context) => ArrangeScreen(
      title: 'Arrange Home',
      lists: [
        ArrangeList(
          title: 'Sections',
          store: LayoutStore(homeSectionsKey),
          names: homeSectionNames(context),
        ),
        ArrangeList(
          title: 'Tiles',
          store: LayoutStore(homeTilesKey),
          names: {
            for (final MapEntry(:key, :value) in homeTileNames.entries)
              if ((key != 'water' || DisplayPrefs.showWater.value) &&
                  (key != 'fasting' || DisplayPrefs.showFasting.value))
                key: value,
            ...homeTrendTileNames,
          },
          optional: homeTrendTileNames.keys.toSet(),
        ),
      ],
    ),
  ),
);

/// Seam S162: Home's list, its [sections] (by the ids of
/// [homeSectionNames], plus 'notices'; null for one not shown today) as
/// arranged, then the way to the editor.
class HomeSectionsList extends StatelessWidget {
  final Map<String, Widget?> sections;

  const HomeSectionsList({super.key, required this.sections});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: LayoutStore.current(homeSectionsKey),
    builder: (context, layout, _) => ListView(
      children: [
        ...arranged(sections, layout).nonNulls,
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            key: const ValueKey('home-arrange'),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Arrange Home'),
            onPressed: () => openArrangeHome(context),
          ),
        ),
        const SizedBox(height: 48),
      ],
    ),
  );
}
