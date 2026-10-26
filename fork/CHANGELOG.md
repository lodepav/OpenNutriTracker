# OpenBite releases

Written by fork/tools/release_notes.dart at each release (D16).

## 0.3.5 · 2026-10-26

Based on OpenNutriTracker 2.5.0.

### Fixes and changes

- journey rounds 8-12 fixes
- implement-review fixes since the redesign review
- compare progress photos' body composition with AI, with certainty
- left vs right measurements; Trends tiles addable to Home

## 0.3.4 · 2026-10-26

Based on OpenNutriTracker 2.5.0.

### Fixes and changes

- one password for both apps' releases
- arrange, hide and add back Home's and Trends' tiles and sections

## 0.3.3 · 2026-10-26

Based on OpenNutriTracker 2.5.0.

### Fixes and changes

- the Goal tile's bar shows before Goal progress is opened
- the Expenditure chart fits the estimate, logged in the touch

## 0.3.2 · 2026-10-26

Based on OpenNutriTracker 2.5.0.

### Fixes and changes

- how each diet phase went against its plan
- logging completeness, scale swings, fibre/sugars/sodium trends
- top foods on Calories, weekends, macro goal days, protein per kg
- a macro's page lists its top foods
- more on the Energy balance page
- food thumbnails stay in color
- trend charts fit the period's lowest and highest
- bottom sheets clear the navigation bar

## 0.3.1 · 2026-10-26

Based on OpenNutriTracker 2.5.0.

### Fixes and changes

- behind the plan counts from the last pace change
- the Expenditure axis fits its numbers at a large font
- round-3 UX fixes for the Weight and Goal pages
- the round-3 UX review's Expenditure and Calories fixes
- the Weight trend page's insights and a Goal progress page
- the Expenditure and Calories trend pages

## 0.3.0 · 2026-10-26

Based on OpenNutriTracker 2.5.0.

### New

- D23 and the upstream-copies check

### Fixes and changes

- the release script catches up with origin by itself
- Settings in parts
- paletteOf in lib/fork
- fork tests out of upstream test files
- the bulk-add copy in three files
- translation overlay and one-call fork start-up
- food search, recipe row, meal card, add activity and activity list as fork-owned copies (D23)
- fasting, weight history and onboarding's About you as fork-owned copies (D23)
- the diary's day card as a fork-owned copy (D23)
- Home's dashboard, meal lists and intake card as fork-owned copies (D23)
- the add and bulk-add screens as fork-owned copies (D23)
- Settings as a fork-owned copy (D23)
- Show water and Show fasting switches
- Home tiles open Trends pages, cycle switch for women, Settings apart from Tools
- page lists clear the navigation bar; macros on their own line in recipe and custom food rows

## 0.2.2 · 2026-10-26

Based on OpenNutriTracker 2.5.0.

### Fixes and changes

- implement-review fixes over the redesign
- the planner's goal as Home's, typed and clearable targets, energy units on tiles and totals, phase limits explained
- UX journey fixes for logging, custom foods, Settings and Fits
- weigh-ins edited and undone, one weight encoding, settings-made check-ins say what changed, Trends at 200%
- UX review fixes on the Settings pages, goals, activity, Health Connect and Profiles
- UX review fixes on the redesigned pages
- the goal page leads with today's goal and three steps
- the custom food form reads like a nutrition label
- quick add is one big energy figure or the macros' sum
- the builder takes amounts in place and saves from a totals bar
- Profiles as cards, goal, trend and days logged
- Health Connect as a card to tick for each thing that syncs
- Food databases as one card, a tag for each
- Nutrient goals as bars against the goals, Edit opens the list
- Accent colour as MacroFactor's, a preview and round swatches
- Data as its own page, backup, in, out, start over
- Settings as MacroFactor's, a page for each section, with search
- Add activity as MacroFactor's, the list with a duration pop-up
- the + sheet starts with search and the meal as chips
- the recipe page logs a chosen portion; the recipes list shows kinds and logs a serving
- the food page shows its kind, the energy by macro, the day after adding and the meal beside Add
- the You tab as MacroFactor's, profile row, four tiles and grouped lists
- Fasting as MacroFactor's, a ring, plan chips and the last seven fasts
- weight history shows the trend over the weigh-ins and swipes a weigh-in away
- the foods behind a macro switch between the energy and the macros
- yogurt shows 🥛
- the recipe tab shows a food's kind, not its photo
- Home in one card with the week, and 2×2 tiles
- Trends after MacroFactor, a grid of tiles, a page each, the energy stacked by macro
- the Diary after MacroFactor, a week of day rings, the day's totals, the meals as a timeline
- an Open Food Facts product's row shows its kind, not its packshot
- compact search rows, history at its last amounts, then favourites
- shorter food rows with their macros
- review fixes for recovery, backups, leftovers and check-in
- left and right arm and thigh measurements

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
