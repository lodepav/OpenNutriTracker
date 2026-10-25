# OpenBite releases

Written by fork/tools/release_notes.dart at each release (D16).

## 0.2.1 · 2026-10-25

Based on OpenNutriTracker 2.5.0.

### Fixes and changes

- the release stops when fork/main moved on
- an added weigh-in refreshes Home, the delete's Undo goes after its time
- Trends' calorie summary and tooltip cut energy as energyValue does
- Trends' daily average rounds, as the weekly report does
- Home shows the weight a deleted weigh-in leaves, the check-in's rows add up, the recovery text names a button
- UX round 5's weigh-in, first check-in, weigh-in delete, recovery text and dev Updates wording
- the Weight card's rate agrees with the Goal planner's; the dashed line passes 3:1
- the recovery screen restores the automatic backup or starts again
- the Weight chart's legend, and its rate from the smoothed trend, never -0.0
- test-fast regenerates the strings
- an Updates row with the version, a typed weigh-in, a readable doubtful match
- the add snackbar names the meal; Log 1 item
- UX round 3's kJ wording, import headline and plurals
- the Health Connect note sits under the weight it filled
- the import says what it finds already here, and a profile's deleted data takes the fork's boxes with it
- an unstated amount is 3.5 oz for imperial, onboarding offers the weight from Health Connect
- UX fixes, the onboarding Overview's macros, typed birth dates, 2.2 g/kg protein per lb in pounds, icons for imported foods
- chart tooltips name and round each number, no line to the axis, empty ranges say so
- recipe servings, labels, the check-in's change, Trends' outlook and legend, the missing-info text

## 0.2.0 · 2026-10-25

Based on OpenNutriTracker 2.5.0.

### New

- goal changes at once, logging-gap guard (D18), round-2 review fixes
- expenditure and check-in settings, activity, days left out

### Fixes and changes

- diet phases to a weight, deferred review items
- review round 4 simplification
- review round 3 tests
- review round 2 fixes
- review round 1 fixes
- "Fits what's left" over the add-meal recents
- weight milestones in the goal planner; diet phases until a weight
- kJ in meal headers, meal detail, Trends summary; onboarding badge wraps
- review fixes for repeating planned foods
- repeat a planned food on chosen weekdays
- chosen segment contrast
- usual portion from the diary, calorie chart summary
- edit dialog, plurals, dates, search macros
- UX standards, review loop and two rounds of fixes
- second UX review fixes
- macro order, diary by the hour, MacroFactor import in one go

## 0.1.0 · 2026-10-24

Based on OpenNutriTracker 2.5.0.

### New

- GitHub releases and an in-app updater (D16)

### Fixes and changes

- bare potato logs plain boiled potatoes
- bare names log their everyday row
- bare egg and pizza log the everyday row
- bare lasagna logs a homemade beef lasagna
- less frequent dishes from the user's log
- search and AI checks on the user's own log
- iLunch recognition, fork dishes and shorter names
- phase switch test, single target restore
- second whole-fork review fixes
- whole-fork review fixes
- photo notes, kcal, names, hard notes, typed meals and variance checks
- real-model replay checks and tuning
- round 6 review fixes
- MacroFactor round 6
- MacroFactor round 5
- MacroFactor round 4
- MacroFactor round 3
- MacroFactor round 2
- more from MacroFactor
- copy label, export name, restored settings applied live
- copy entries, OFF review, backup profile and onboarding restore
- Offer a saved custom food to Open Food Facts as the user's own account
- Save bulk add's rows as a recipe, and read a recipe link's ingredients
- The label button hides where the app's services are not set up
- The dev entry turns the fake AI on, as main does
- Read a nutrition label into the custom-food form with the chosen model
- The contributions list opens a food's details
- The weight tile shows only where the import was started
- The section menu test looks for Copy…
- Never prune the backup just written
- Phase 2 backup done (S21-S23, carried import fixes)
- Name the fork OpenBite (D8, S20)
- A shorter title, totals as the tile shows them, and <1 g for a trace
- Carry feat/nutrient-contributions
- Rank the recents by the meal being added to
- Release checks for secrets, dependencies and the APK
- Record the per-profile adaptive state
- Record phase 3 done and phase 2 waiting on v2.5.0
- Say in the photo sheet that the meal photo is kept
- The fake AI reads a photo's note; record the photo + note check (phase 1.1)
- Offer a breakdown only on an unmatched or weak row, never on a confident product (phase 1c)
- Match Latvian letters to plain ones in dish search (phase 1c.5)
- Credit BLS and USDA on the licence page; check staple foods resolve from the table (phase 1b)

### From OpenNutriTracker

- upstream release v2.5.0
