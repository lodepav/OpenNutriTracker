# OpenBite's own features

What the fork adds to OpenNutriTracker, as of OpenBite 0.9.1 (based on ONT 2.7.0), 2026-11-09.
Each feature is marked:

- **Fork only**: stays in the fork, for the reason given: it goes against an upstream rule, is
  the fork's own identity or taste, depends on something only the fork has, or is too large and
  opinionated for one PR.
- **Candidate**: any ONT user would want it, so rule 1 of [README.md](README.md) says to offer it
  upstream. It still needs a branch off `develop` and upstream's yes.
- **Sent**: already offered upstream (PR or issue number).

The marks are a judgement, not a decision; a decision goes in [DECISIONS.md](DECISIONS.md).
Details live in the seam rows ([SEAMS.md](SEAMS.md), `Sxx`) and decisions (`Dxx`).

## Sent upstream

| What | Where |
|---|---|
| Bottom sheets and the nutrient goals list clear of the navigation bar | #1493, merged (2.7.0) |
| Labelled icon buttons and sliders, text that wraps at large font sizes | #1494, merged (2.7.0) |
| Claude 5.5 and GPT-6 models, tool calls the way each accepts | #1495, merged (2.7.0) |
| A dish served as pieces counted in a photo; a count past a recipe's batch flagged | #1496, merged (2.7.0) |
| Tests delete their Hive boxes before closing them (no stray `.hive` files, S203) | #1574, open |
| Automatic backup after diary changes, for Syncthing and Drive sync apps (D10) | issue #1356, open |
| Changing the unit keeps the amount of food (S164) | #1603, open |
| Decimal fields take digits and one separator only (S141) | #1604, open |
| A favourite's starred time exported in UTC (S86) | #1605, open |
| Deleting today's weigh-in sets the current weight back (S113) | #1606, open |
| The editor opens the advanced form when the simple one would change the food (S188) | #1607, open |
| Add says when the food was not stored (S189) | #1608, open |
| A full Open Food Facts record lookup gives up after 5 s (S181) | #1609, open |
| Daily average goals over the days that have one, grams rounded (S87, S114) | #1610, open |
| A unit stated inside a phrase is kept (S169) | #1611, open |
| One retry after a brief rate limit (S171) | #1612, open |
| Saved recipe names in the meal photo prompt (S172) | #1613, open |
| Copy a meal into another meal of the same day (#842, from S177) | #1614, open |
| Custom meals and recipes found by their words in any order (S5) | #1615, open |
| Read a nutrition label into a custom food; add an unknown barcode from its label (S29, S36) | #1616, open |
| A typed weight under the ruler in the weigh-in and target-weight dialogs (S111) | #1643, open |
| Delete in the Edit item dialog; OK refuses 0 (S83, S168) | #1644, open |
| No photo for the four demo foods whose photo was another food (S82) | #1645, open |
| Trends' windows end on the Diary's logical today (S190) | #1646, open |
| A unit picked while the amount is blank is kept (S192) | #1647, open |
| Chart touches labelled, charts fitted to the period, dots up to a month (S96, S97, S161, S166) | #1648, open |
| A food that cannot be logged says what it needs per 100 g, energy in the user's unit (S94) | #1649, open |
| Key field names that wrap, a spoken Go to today, three lists clear of the navigation bar (S211, S92, S143) | #1650, open |
| The added-food snackbar names the meal (S110) | #1651, open |
| A recipe's serving reads as one serving and its weight (S91) | #1652, open |
| The scanner's manual-entry button clear of the navigation bar (S217) | #1653, open |

## Targets and coaching (MacroFactor's)

| Feature | Mark | Why / notes |
|---|---|---|
| Adaptive expenditure and the weekly check-in: estimated expenditure from weigh-ins and intake, a capped target the user accepts (D13, D17–D21, D27; S12, S13, S17) | Fork only | The fork's reason to exist; large and opinionated (smoothing, blend and cap tuned by simulation). Upstream keeps the formula and its fixed target. |
| Expenditure and check-in settings: responsiveness, steps and workouts counted, check-in day, auto-accept, a day left out (D17) | Fork only | Part of the adaptive target. |
| Smoothed trend weight beside the 7-day average, chosen by a switch (D13, S15, S93) | Candidate | A pure function and a switch; useful without the adaptive target. |
| Macro program: protein and fat per kg of body weight or lean mass, the rest carbs; fat moves with the goal (D22, D34, S41) | Candidate | Upstream sets macros as a percentage split. A new way to set macros, so upstream's call. |
| Goal planner in onboarding and diet phases: goal, pace, phases that move the goal by date, Home saying when it moved (S88, S89, S193, D32) | Fork only | Built on the adaptive target and phases. |
| Weekday calorie shift, per-day goals kept for copies, imports and activities (S63–S69) | Fork only | Part of the fork's targets. |
| Activities leave a fixed or adaptive target alone (S62, S68) | Candidate (fixed part) | For upstream's fixed target (#671) a logged activity still moves the goal; the adaptive part is the fork's. |
| "Allow for a monthly cycle" on a woman's profile only (S146) | Fork only | A setting of the adaptive estimate. |
| Weigh-in and check-in reminders (S46) | Candidate (weigh-in) | The weigh-in reminder fits upstream's reminders; the check-in one is the fork's. |
| Strength from Go Hevier suggests a calorie change; OpenBite shares its phase with Go Hevier (D28, D29, S182, S183) | Fork only | Depends on the user's own gym app and signing key. |

## Logging with AI

| Feature | Mark | Why / notes |
|---|---|---|
| A dish the database lacks is broken into ingredients with grams; only an unmatched ingredient gets the model's estimate (D9, D12, S3) | Fork only | Upstream forbids model-supplied numbers (#250). |
| A photo note's weight sizes the plate; a named meal without a weight gets estimated grams (D24, D25, S175) | Fork only | Visual portion estimates, which #250 rules out. |
| Leftovers: subtract what was left from an entry or a meal (D14, S9, S10) | Candidate (manual) | D14: the manual amount or fraction goes upstream; the AI photo of the leftovers is fork only (#250). |
| Read a nutrition label into a custom food (S29), and "Add it from its label" when a barcode is not found (S36) | Sent (#1616) | Reads printed numbers; it does not estimate them. |
| Photo prompt: counts of halves and pieces, counts the note states (S60, S170) | Candidate | The first part went upstream as #1496. The note counts need the photo note upstream first (`feat/photo-note`, not opened). |
| Photo prompt lists the user's saved recipe names (S172) | Sent (#1613) | |
| A 429 from the model is retried once, within the read's timeout (S171) | Sent (#1612) | |
| A counted food's full-record lookup waits 5 s, not 60 s (S181) | Sent (#1609) | A slow network holds upstream's review screen. |
| An amount inside a phrase counts as stated ("a 330 ml can of coke", S169) | Sent (#1611) | Extends upstream's #977. |
| Model rows show the fork's eval rating and price tier (S174) | Fork only | From the fork's own eval (`fork/eval/`). |
| Typed meals queried in English whatever their language (S204) | Fork only | Fits the fork's English tables; upstream searches Open Food Facts in the user's language. |
| Matching rules for what a model reads: variants trail, everyday rows, dish parts and sides left out, slices as pieces, brands named or not (S70, S73–S75, S178, S187, S196–S200, S202, S205, S206; D26, D40) | Fork only | Tuned on the fork's bundled tables and evals. A rule that also helps Open Food Facts results could be split out later. |
| Log with AI's review list as Diary rows with the meal's macros, swipe to leave out (D35–D38) | Fork only | Part of the redesign. |
| Back on "Add several items" asks before the foods found are lost (S90) | Candidate | |
| A fake model and replayed answers for emulator runs (`FORK_FAKE_AI`) | Fork only | Development tooling. |

## Food data and search

| Feature | Mark | Why / notes |
|---|---|---|
| Offline generic foods: USDA FoodData Central and BLS 4.0 bundled (D11, S1, S2) | Fork only | Replaces upstream's food backend and adds a large asset; a change of upstream's architecture, not a feature PR. |
| The fork's dishes worked out from recipes (solyanka, cepelinai, kvass…) (S72) | Fork only | Rows of the fork's own table. |
| Four Latvian starter recipes (D12, S6) | Fork only | Local to the user. |
| Saved meals and recipes found by their words in any order (S5) | Sent (#1615) | Flagged in SEAMS.md as an upstream PR candidate. |
| Recents put the foods usually logged in this meal first (S19) | Candidate | |
| Remembered amounts: a food opens at the amount last logged (S45) | Candidate | |
| Amount picker: units as chips, the food's portions with their weights, − and +, the user's own named portion (D33, S195) | Candidate | A large UI change to upstream's meal detail. |
| A unit change converts the amount (180 g → 1 serving, S164) | Sent (#1603) | A bug fix. |
| A food that cannot be logged says what it lacks (S94) | Sent (#1649) | Upstream already listed the missing values (#1474); the PR words the first line and names energy in the user's unit. |
| A recipe's serving reads as one serving and its weight (S91) | Sent (#1652) | |
| Contribute a custom food to Open Food Facts (S33) | Candidate | Ported from another fork (theoleuthardt `personal`). |
| Search opens with the keyboard up (S163) | Candidate | |
| Search rows as short as the Diary's; Open Food Facts products as an emoji, not a photo (S116, S117) | Fork only | Part of the redesign. |

## Diary and logging flow

| Feature | Mark | Why / notes |
|---|---|---|
| Copy and move: select foods or meals on the Diary and copy, move, share or delete them (S177, D30) | Candidate | Copying a meal into another meal of the same day went as #1614 (upstream's #842). Upstream's lock (#1319) already fixed the under-count. The selection bar stays fork only for now. |
| Food basket: gather several foods, review the meal, log them together (S42, D39) | Candidate | |
| Meal plan and recurring meals (S43, D31) | Candidate | Large; could go in parts. |
| Diary by the hour (S80) | Candidate | |
| Macro order: carbs, fat and protein in the order picked (S79) | Candidate | |
| Swipe the Diary a day back or forward, past today (S176) | Candidate | |
| Undo after deleting a food (S52) | Candidate | |
| Show water and Show fasting switches (S144) | Candidate | Next to upstream's Show activity tracking. |
| The added-food snackbar names the meal (S110) | Sent (#1651) | |
| The food page's Add says when the write failed (S189) | Sent (#1608) | A bug fix. |
| Editing a food whose serving the simple form cannot hold opens the advanced form (S188) | Sent (#1607) | A bug fix. |
| Number fields take digits and one separator only (S141) | Sent (#1604) | A bug fix: "120-" saved an empty value. |
| A Diary day can be left out of the expenditure estimate (D17) | Fork only | Part of the adaptive target. |

## The redesign (MacroFactor's look)

| Feature | Mark | Why / notes |
|---|---|---|
| Home: one summary card, quick actions, recent foods, repeat a meal, sections arranged by the user (S119, S162, D30, D31) | Fork only | The fork's taste; whole screens copied under D23. |
| Diary: a week calendar of rings filling with the day's energy, the day card (S118, S149) | Fork only | |
| Trends: tiles over 1W to All, with a page each (S120) | Fork only | |
| You tab, the foods behind a macro, the recipe page, accent colour, Health Connect page (S121, S124, S126, S136, S138) | Fork only | |
| Muted macro colours on every macro line (D38) | Fork only | |

## Health and body

| Feature | Mark | Why / notes |
|---|---|---|
| Health Connect: weight in, body fat in, nutrition out (S27, S48, S49) | Candidate | Next to upstream's workout import. Each needs Play's Health Connect declaration. Weight import is already open upstream as markprovan's #1296, so the fork doesn't send its own. |
| Daily steps on Trends (S44) | Fork only | Upstream dropped READ_STEPS after Play called it excessive. |
| Weight from Health Connect during onboarding (S99) | Candidate | |
| Health Connect grants checked without the plugin ending the process (S180) | Candidate | A workaround for a plugin crash. |
| Deleting today's weigh-in sets the profile weight back (S113) | Sent (#1606) | A bug fix: the goal kept the deleted weight. |
| Body measurements and body fat % on Trends (S40, `lib/fork/body/`) | Candidate | |
| Progress photos (`lib/fork/photos/`) | Candidate (photos) | The AI comparison of two photos is fork only, as a visual estimate. |
| Fasting timer's plans and history (S157) | Fork only | A copy of upstream's screen, redesigned. |

## Backup and data

| Feature | Mark | Why / notes |
|---|---|---|
| Automatic backup into a folder a sync app mirrors (D10, S22) | Sent | Issue #1356. |
| The fork's own data in the backup: water, fasting, check-ins, phases, settings (S21) | Fork only | The fork's boxes. |
| Restore a backup from onboarding (S37); restored settings apply without a restart (S38) | Candidate | |
| Data that will not open: restore the newest backup or start again, files set aside, never deleted (S112) | Candidate | |
| Import another app's history, e.g. MacroFactor's export (`lib/fork/history/`) | Candidate | The user's own export never goes in the repo. |
| CSV export (`lib/fork/export/`) | Candidate | |
| A favourite's time round-trips an export in UTC (S86) | Sent (#1605) | A bug fix: an hour off across a clock change. |
| Deleting a profile's data also empties the fork's boxes and photos (S102, S191) | Fork only | The fork's data. |

## Android

| Feature | Mark | Why / notes |
|---|---|---|
| Launcher shortcuts (Scan, Photo log, Quick add, Weigh in) and shares into the app: a photo, text, a recipe link (S167) | Candidate | |
| Home-screen widgets for macros and trend weight, beside upstream's calorie widget (S50, D41) | Candidate | |
| Its own app id, name, icon and logo: OpenBite (D8, S20, S34, S35) | Fork only | Identity. |
| GitHub releases with an in-app updater (D16, S76) | Fork only | The fork's distribution. |
| No tip jar, no billing permission (S207, D41) | Fork only | Upstream's Support page funds upstream. |

## Charts, accessibility and polish

| Feature | Mark | Why / notes |
|---|---|---|
| Chart touches name each number with its unit and day; an empty range says so (S96, S97) | Sent (#1648) | Upstream's lines and 7-day average stay; the fork's trend line and legend are not in it. |
| Charts fit the period shown; dots up to a month (S161, S166) | Sent (#1648) | |
| Trends' windows end on the Diary's logical today (S190) | Sent (#1646) | A bug fix past midnight. The water average over the days logged is not in it. |
| Daily averages over the days logged, rounded not cut (S87, S114, now in S120) | Sent (#1610) | Bug fixes to upstream's Daily average card. |
| Screen-reader labels and large-text fixes beyond what 2.7.0 took (S81, S83, S92, S111, S211) | Sent (part) | Partly upstream via #1494. Sent: the typed weigh-in field (#1643), the edit dialog's Delete (#1644), key field names and Go to today (#1650). The rest of S81 and S83 is not sent. |
| Lists clear of a 3-button navigation bar (S143) | Sent (#1650) | Partly upstream via #1493. |

## Release checks

| Feature | Mark | Why / notes |
|---|---|---|
| Release gate: supply chain, secrets, signing, permissions, exported components, vulnerability scan (`fork/tools/release-check.sh`) | Fork only | The fork's own release process. |
| `addressable` ahead of upstream; no `cocoapods` gem (S194, S201) | Fork only | For the vulnerability scan. S201 never goes upstream: upstream's iOS job needs the gem. |
