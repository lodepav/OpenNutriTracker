import 'package:flutter/material.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart'
    show CheckInWaitingNote;
import 'package:opennutritracker/fork/bulk/ai_add.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/layout/arrange_screen.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';
import 'package:opennutritracker/fork/layout/width_cap.dart';
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
const homeQuickActionsKey = 'homeQuickActions';

/// Today's diary on Home, off until switched on in Arrange Home. Named apart
/// from the ids they had while on by default ('activity', 'breakfast'…), so a
/// saved layout does not know them and they go off there too.
const homeDiarySections = {
  'diaryActivity',
  'diaryBreakfast',
  'diaryLunch',
  'diaryDinner',
  'diarySnack',
};

/// Home's sections off until switched on: today's diary, and Recent foods,
/// which the + sheet lists too.
const homeOptionalSections = {...homeDiarySections, 'recentFoods'};

/// Home's quick actions, by id in their first order; Photo log only while
/// AI meal assistance is on.
Map<String, String> homeQuickActionNames(
  BuildContext context, {
  required bool ai,
}) => {
  'search': S.of(context).searchLabel,
  'scan': 'Scan',
  if (ai) 'photo': 'Photo log',
  'quick-add': S.of(context).quickAddCardLabel,
  'weigh-in': 'Weigh in',
  'meal-plan': 'Meal plan',
};

/// Quick actions off until switched on: the + sheet opens on search.
const optionalQuickActions = {'search'};

/// Home's sections (S162), by id in their first order. 'notices' (the
/// empty-day hint and the low-energy warning) is not in the editor: it
/// keeps its place after the meal plan wherever that goes.
Map<String, String> homeSectionNames(BuildContext context) => {
  'dashboard': 'Summary',
  'quickActions': 'Quick actions',
  'repeatMeal': 'Repeat a meal',
  'recentFoods': 'Recent foods',
  'tiles': 'Tiles',
  'checkIn': 'Weekly check-in',
  'strength': 'Strength',
  'plan': 'Meal plan',
  'diaryActivity': S.of(context).activityLabel,
  'diaryBreakfast': S.of(context).breakfastLabel,
  'diaryLunch': S.of(context).lunchLabel,
  'diaryDinner': S.of(context).dinnerLabel,
  'diarySnack': S.of(context).snackLabel,
};

/// Opens "Arrange Home": its sections, its quick actions, and its tiles but
/// those hidden in Settings.
Future<void> openArrangeHome(BuildContext context) async {
  // Read first: a list Home has not shown (the quick actions, switched off)
  // has no layout in memory, and the editor would start from the defaults.
  for (final key in [homeSectionsKey, homeQuickActionsKey, homeTilesKey]) {
    try {
      LayoutStore.current(key).value = await LayoutStore(key).layout();
    } catch (_) {
      // No box (widget tests): as in memory.
    }
  }
  // Without the setting, no Photo log, rather than no editor.
  final ai = await aiAddEnabled().catchError((Object _) => false);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => ArrangeScreen(
        title: 'Arrange Home',
        lists: [
          ArrangeList(
            title: 'Sections',
            store: LayoutStore(homeSectionsKey),
            names: homeSectionNames(context),
            optional: homeOptionalSections,
          ),
          ArrangeList(
            title: 'Quick actions',
            store: LayoutStore(homeQuickActionsKey),
            names: homeQuickActionNames(context, ai: ai),
            optional: optionalQuickActions,
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
}

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
        // shown, the card says it itself
        if (layout.hidden.contains('checkIn')) const CheckInWaitingNote(),
        // each capped, so the list's sides still scroll on a wide window
        for (final section in arranged(sections, (
          order: layout.order,
          hidden: {...layout.hidden, ...addable(homeOptionalSections, layout)},
        )).nonNulls)
          WidthCap(child: section),
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
