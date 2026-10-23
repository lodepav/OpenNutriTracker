# Plan — MacroFactor features on OpenNutriTracker

Started 2026-10-17. Decisions in [DECISIONS.md](DECISIONS.md) win over this file.

## 0. What upstream already gives us

Checked on `develop` at 1bc934b1 (2026-10-17). `fork/main` is based on the `v2.4.0` release since 2026-10-22 (D6); the phase 1c files read on `develop` are identical in 2.4.0.

| MacroFactor feature | ONT today |
|---|---|
| Barcode, search, quick add | ✅ Open Food Facts, plus ONT's food backend (USDA, BLS). The backend needs real `.env` values. |
| Recipes | ✅ recipe builder with ingredient barcode scan; JSON/CSV/QR import |
| AI text describe, AI photo | ✅ experimental, **grounded**: the model names foods and portions, and the numbers come from the food database (`lib/features/add_meal/domain/meal_items_api.dart`) |
| AI photo + text | ❌ the photo request sends the fixed prompt `mealPhotoContentPrompt` |
| Trend weight | ⚠️ a 7-day moving average over the weight chart (#1197) |
| Goal ETA | ⚠️ "weeks left" on Trends; calorie taper near the target |
| Adaptive expenditure, weekly check-in | ❌ calorie target = formula TDEE (IOM 2005) ± a weekly-pace offset |
| Micronutrients, water, fasting | ✅ |
| Backup | ⚠️ manual JSON/CSV zip export and import. Import onto a live install appends duplicates in 2.4.0; fixed on `develop` (#1369, #1398), not yet released. |

## 0b. Built elsewhere already (checked 2026-10-22)

Upstream `develop`, its open PRs, its roadmap (#1279) and the 70 forks pushed since mid-August,
checked for anything in this plan. **Rule (D15, 2026-10-23, replaces "port or wait"):**
nothing waits. Upstream's work is carried now and swapped for its release; another fork's is
reviewed (sound, to standard, as simple as it can be), then ported and configured the fork's way.
Both forks below are GPL-3.0 like ONT, so their code can be ported with credit.

| Plan item | Where it exists | Effect |
|---|---|---|
| Phase 1b food tables | theoleuthardt `personal`: local BLS 4.0 and FDC search, with build scripts | Ours is done |
| Phase 1c dish → recipe, word-based recipe search | Nowhere. Upstream #1231 (resolver tie-break) and #833 (a logged recipe ignores its serving amount) touch it | Unchanged |
| Phase 1.1 photo + note | Nowhere. Upstream PR #587 lets an outside AI app share meal JSON into ONT | Unchanged |
| Phase 1.5 leftovers | Nowhere | Unchanged |
| Phase 2 backup | Upstream 2.5.0 (release PR #1439) carries the import fixes (#1369, #1398, #1381). theoleuthardt: custom meals, settings and every profile in the backup, a backup-age reminder, WebDAV auto-backup, backup into a Files-app folder, restore from onboarding. Upstream issues #1356 (Syncthing), #1355 (import from onboarding), #1395 (restore loses pace and taper) | Crucial, stays. Port the custom-meals export and onboarding restore rather than design them |
| Phase 3 adaptive expenditure, check-in | Nowhere. Upstream #671 (fixed calorie target, top store-review request) is high priority there; theoleuthardt has a fixed kcal goal with gram macros and training-day goals | Unchanged; the target switch must leave room for #671's fixed mode |
| Backlog: label scan | theoleuthardt (on-device OCR, iOS only), cattosmile/OpenNutriTrackerPlus (AI scan), aeobrien | Lowered |
| Backlog: AI recipe builder | aeobrien "Phase 12" | Lowered |
| Backlog: re-log yesterday | theoleuthardt: copy entries, meals or days to any date; upstream #842, #1265 | Lowered |
| Backlog: OFF contributions | theoleuthardt: send scanned values and the label photo to OFF | Lowered |
| Backlog: Health Connect weight | Upstream PR #1296 | Lowered: take it when merged |
| Backlog: top contributors per nutrient | Upstream issue #1266, no code | Unchanged |

Also seen: cattosmile identifies unpackaged food from a photo with a web-search fallback,
worth a look when phase 1c's breakdown is designed.

## 1. Pre-work

- [x] Fork on GitHub (`lodepav/OpenNutriTracker`), clone, `upstream` remote, `develop` and `fork/main` branches (D6).
- [x] Build rig: Flutter 3.44.6 in `~/flutter`, OpenJDK 24, debug APK builds.
- [x] `fork/tools/emulator.sh` (D5). `SEED=1` builds upstream's demo-data entry point, which gives a year of diary and weigh-ins, enough to exercise an expenditure estimate.
- [x] GitHub Actions off on the fork (2026-10-19). Every upstream workflow needs upstream's secrets or acts on upstream's issues and Weblate, and none had ever run here, so Actions is switched off for the whole repo (Settings → Actions) rather than per workflow; that also covers workflows upstream adds later. The files stay: deleted files conflict on every upstream edit. Switch it back on, and disable workflows one by one, if the fork ever wants CI of its own.
- [x] Fork identity (Q2, D8): **OpenBite**, app id `io.github.lodepav.openbite`, set in `android/app/fork.gradle` (S20). Launcher name only.
- [ ] OpenBite in the app's own text (onboarding, About, share texts) and its own icon. Search the trademark registers before publishing under the name.
- [ ] `.env`: placeholders stay; ONT's hosted backend isn't used (D11).

## 1c. Phase 1c — Dishes as recipes (D12, revised D9)

Before phase 1, at the user's request. Upstream code read 2026-10-18; findings first, then the steps.

**What upstream gives us:**
- **The resolver never gives up loudly.** `ResolveParsedMealsUseCase._resolveOne` searches Open
  Food Facts and the food table in parallel, merges with the user's own content in a tier above
  remote results, and re-ranks. An item ends one of three ways:
  - unresolved (no candidates)
  - low confidence (top score under `kResolutionConfidenceFloor`)
  - resolved

  Its own doc comment names the unresolved item as "the seam where [a fallback] would attach".
  A trap: a dish the tables lack can still resolve to a *branded* Open Food Facts product (a frozen
  khachapuri), which looks resolved.
- **The breakdown needs no client changes.** Every client implements
  `MealItemsApi.requestItems(content, system)`, and `mealItemsToolSchema` already carries
  `query`, `quantity` and `unit` (`g` included) with no nutrition fields. A breakdown is the
  same call with `MealTextContent("one serving of <dish>")` and a breakdown system prompt.
  - The reply is validated by the same `validateParsedMealItems`.
  - The provenance rule holds: the model names ingredients and grams, the table supplies every
    nutrient.
  - Only the grams are the model's estimate. Upstream's photo path refuses gram estimates (#250),
    so this is a fork-only, marked deviation (D12).
- **Recipes already rank first, but match on exact text.** `SearchProductsUseCase` puts recipes
  above cached and remote results, and the resolver keeps that tier. But
  `_mealMatchesSearch` is `name.contains(query)`: a recipe "Khachapuri" is found by
  `khachapuri`, not by `adjarian khachapuri` or `Georgian cheese bread`. The model's wording
  varies, so this decides whether a saved dish is found next time.
- **Recipes are self-contained.** `RecipeIngredientEntity` holds a full `MealEntity` snapshot plus
  amount, unit and grams. A saved breakdown keeps its numbers even if the food table changes.
- **The builder can open pre-filled.** `RecipeBuilderScreen` takes `existing: RecipeEntity` in its
  route arguments, so an unsaved recipe built from a breakdown opens for review and saving
  without a builder change. Save upserts by id (`recipe_data_source.dart` `saveRecipe`), and the
  builder keeps the passed recipe's id, so a breakdown given a fresh id saves as a new recipe.
- **Import formats:**
  - `user_recipes.json` in the export zip (full snapshots, `docs/export-format.md`).
  - The QR/JSON share payload (`shared_recipe_payload.dart`, macros only, no micronutrients).
- **Review screen.** `bulk_add_screen.dart` shows one row per item, with unresolved and
  low-confidence rows marked (`_buildRow`). A breakdown replaces one row with a group.

**Steps:**
1. **Breakdown call.** In `lib/fork/`: a use case taking a dish name (and the photo's query, if
   it came from one), calling the configured `MealItemsApi` with a text-only breakdown prompt.
   - The prompt asks for ingredients of one serving in grams, each the nearest generic ingredient
     (grey peas → dried split peas, sulguni → brined mozzarella-type cheese), plus the serving
     weight.
   - Each ingredient is resolved with the same `ResolveParsedMealsUseCase`. No photo is resent.
   - *Done 2026-10-22:* `lib/fork/dish/break_down_dish_usecase.dart`, built from upstream's
     locator registrations (no seam). The serving weight is the sum of the grams; the schema has
     no field for it. Two findings:
     - Every client drops a unit the text does not state (#977), so the text sent says "e.g.
       100 g"; a test pins that it still counts as stating one.
     - Bare ingredient names hit the resolver's tie-break (`carrot` → *Carrot, dehydrated*,
       `bacon` → *Bacon, meatless*). The prompt asks for table-style names ("carrot, raw"),
       which land on the raw rows; `test/fork/staple_foods_test.dart` pins eight of them.
2. **When it runs.**
   - Automatically for an unresolved row.
   - On demand ("Break into ingredients") for any row, which covers low-confidence matches and
     the branded-product trap.
   - One seam in `bulk_add_screen.dart`/its bloc, or a wrapper around the resolver if that is
     smaller.
   - *Done 2026-10-22:* `DishBreakdownController` runs it automatically for an unmatched row of
     a model or photo read (not the parser's rows: the model was not used or failed there), and
     on demand ("Ingredients") for an unmatched, low-confidence or Open Food Facts row. Seams S3
     (bloc) and S4 (screen). Fork UI text is English only (`dish_strings.dart`), kept out of
     upstream's ARB files and Weblate.
3. **Review.** The dish shows as a group of its ingredient rows, marked "AI breakdown, grams
   estimated". Each row is editable as today. A row that still matches nothing keeps the model's
   name for the user to search (D9's estimate stays a last resort, marked).
   *Done 2026-10-22:* each ingredient row carries its dish (`DishIngredientItem`, which survives
   edits) and reads "Ingredient of <dish> · AI estimate, check the grams". No group header yet.
4. **Save as recipe.** One action builds an unsaved `RecipeEntity` (name = the dish, servings 1,
   ingredients from the group) and opens `RecipeBuilderScreen` with it.
   *Done 2026-10-22:* "Save recipe" on the first row of each group (`dish_recipe.dart`). The rows
   as edited, each converted to grams like bulk add's own save; skipped and unmatched rows left
   out. The id is empty, upstream's "copy" sentinel, so the builder gives it a new id and saves it
   as a new recipe; a test runs upstream's builder bloc on it.
5. **Finding it again.** Make the recipe tier match on words, not the whole string: every query
   word in the name, using the same `wordsAgree` rule as the food table. Check that the model's
   usual names for the user's dishes find the saved recipe, typed and photographed. This touches
   upstream's `_mealMatchesSearch`, which is either an upstream PR (it helps every user) or a seam.
   *Done 2026-10-22 as seam S5:* custom meals and recipes match on every word, in any order,
   up to an ending ("khachapuri, adjarian" finds "Adjarian khachapuri", "pelmeni" finds
   "Pelmenis"), beside upstream's substring match so half a word still works. A test runs it
   through the resolver. Still to do: offer it upstream as a PR, and the typed/photographed
   check with a real model (phase 4). Latvian letters fold to plain ones on both sides
   ("sklandu rausi" finds "Sklandu rauši"). A model's one-word "sklandrausis" still misses the
   two-word name: watch for it in phase 4.
   *Emulator run 2026-10-22 (fake AI, `--dart-define=FORK_FAKE_AI=true`, `lib/fork/dev/fake_ai.dart`):*
   the starters were saved on first start; "sklandu rausi" found "Sklandu rauši" (1620 g, 12 × 135 g,
   240 kcal); "khachapuri, 200 ml kefir, grey peas" broke khachapuri into its four rows on its own,
   matched grey peas to the starter at one serving (151 g, 462 kcal); "Save recipe" opened the
   builder filled in and saved; typing "khachapuri" again then found the saved recipe (290 g,
   969 kcal) without a breakdown.
   **Found:** two ingredients resolved to Open Food Facts products, not table rows ("cheese,
   mozzarella, whole milk" → a Kroger product, "butter, salted" → "Butter Salted"). A breakdown's
   ingredients should prefer the generic table row. *Fixed 2026-10-22* (`preferTableRow` in
   `break_down_dish_usecase.dart`): a breakdown row that landed on a product takes the table's
   row when the search found one; not yet re-run on the emulator.
   *Re-run 2026-10-22:* "khachapuri, mozzarella" broke khachapuri into table rows only ("Cheese,
   mozzarella, whole milk", "Butter, salted"); the typed "mozzarella" matched a product and was
   not offered "Ingredients", which is now offered only on an unmatched or weak row. A saved
   recipe survived an app restart (one saved last run was lost to killing the emulator, not
   the app). **Phase 1c done.**
6. **Starter recipes.** The four CC0 Latvian recipes (grey peas with bacon, pelmeni, sklandu rauši,
   layered rye-bread dessert).
   - Built on first run in `lib/fork/` from food-table rows chosen at build time (ids in a small
     bundled list) and saved through the recipe repository.
   - Not shipped as a `user_recipes.json`, whose snapshot shape would freeze today's table values
     and tie us to upstream's export schema.
   - Credit the Latvian Institute in the description.
   *Done 2026-10-22 as seam S6:* `starter_recipes.dart` holds the source's grams and the table
   ids chosen for them (BLS where it has a European equivalent, USDA otherwise); a test checks
   each id still names its food. On first start they are saved through upstream's
   `SaveRecipeUseCase`, which computes the nutrition. A flag in the fork's own Hive box makes it
   once per install, so a deleted starter stays deleted. Servings are ours (the source gives
   none): peas 2, pelmeni 6, rauši 12 tarts, dessert 1.
7. **Check** with the fake AI on the emulator (above). Every check against a real model moved
   to phase 4 on 2026-10-22.

## 2. Phase 1 — AI logging complete

1. **Photo + note.** Send the user's typed text along with the photo, in all three clients
   (`anthropic_meal_items_api.dart`, `openai_meal_items_api.dart`,
   `openai_compatible_meal_items_api.dart`) and the add-meal screen. Upstream PR (rule 1).
   *Done 2026-10-22* on `feat/photo-note` (off `develop`, carried into the fork by cherry-pick;
   PR not opened yet). What is typed in the box goes with the photo; the model may name and count
   from it, and a measured amount survives only when the note states that same amount
   ("200g rice" kept 200 g; an unstated or different amount is dropped as before). Emulator,
   fake AI: photo + "200g rice, 2 eggs" gave khachapuri (broken down), brown rice 200 g and eggs ×2.
   Seen, upstream's, not this change: "2 eggs" matched a branded product as "2 g/ml" (#1231).
   Use `fork/tools/emulator.sh`: booting the shared AVD with `-no-snapshot-save` reloads the old
   snapshot, so app data from the last run is gone.
2. *Dropped 2026-10-18:* Gemini. Google is excluded (D7). If the user ever wants it, the
   custom-server option covers it once upstream merges #1257.
3. **Estimate when nothing matches (D9):** covered by phase 1c.
4. **Photo test (D7):** moved to phase 4, last.
5. **Leftovers (D14).** Subtract what was left uneaten from a meal already logged.
   *Done 2026-10-22* on `fork/leftovers`. The single-entry dialog (amount left, ¼ ⅓ ½ ¾) is
   `feat/leftovers` off `develop` (PR not opened yet). Fork-only, seams S7–S11: a bulk save
   records its entries as a meal; tapping one in the diary or on home offers "Just this item" or
   "Whole meal"; the whole-meal dialog takes one share off every item with per-item overrides,
   and "Photo of what's left" sends the leftovers photo beside the kept meal photo (one image,
   side by side, since upstream's clients carry one photo) with the entries as they are now,
   through upstream's meal-items tool; the answer is the amount left per entry, shown as an AI
   estimate. Meal photos are kept 24 h in app support storage (not documents, so not exported;
   Android backup is off), pruned at start-up, off by "Keep meal photos for 24 hours" in
   Privacy Settings, which deletes them; the photo sheet says a copy is kept while it is on.
   Emulator, fake AI: photo + note logged 6 items with the photo kept; whole meal → photo of
   what's left halved five items, curry adjusted by hand, lunch 3170 → 1914 kcal; "Just this
   item" opens upstream's dialog; switching the setting off deleted the photo. Group records
   and the setting are not in backups yet (phase 2). The real-model check below is phase 4.
   The privacy switch saves as it is switched, so the dialog's Cancel does not undo it.
   - **What upstream gives us:** a logged entry's amount can be edited
     (`update_intake_usecase.dart`), so subtracting is an amount update. Nothing groups the
     items of one AI log: bulk add writes each row as its own intake
     (`bulk_add_screen.dart` `addIntake` loop), with no shared id. The photo is compressed,
     sent and never kept (`meal_photo_encoder.dart`).
   - **Manual.** A "Leftovers" action on a diary entry: enter the amount left, or tap ¼, ⅓, ½
     or ¾ left. The new amount is shown before saving. On a group (below), one fraction
     applies to every item, with per-item overrides. The single-entry action is an upstream
     PR (rule 1).
   - **Groups.** When bulk add saves, record a meal group in a fork Hive box: the intake ids,
     the time, and the cached photo's path if any. Included in backups (phase 2.3), without
     the photo.
   - **AI.** Photo of the plate after eating. The model gets that photo, the cached original
     photo if still there, and the group's entries *as they are now* (names, amounts, units;
     the user may have edited them since). It returns, per entry, how much is left: a count
     for countable items ("2 of 5 dumplings"), else a fraction. No nutrients and no new foods:
     the numbers stay the logged entries' own. The same review screen as the manual action
     shows each subtraction, marked "AI estimate", editable before saving. Without the
     original photo it still works from the entries and the leftover photo alone.
   - **Photo cache.** Keep each AI-logged photo in app-private storage for 24 hours, then
     delete it. Never exported or backed up. Off by a setting for users who want no photo kept.
   - **Check.** Before/after photo pairs of a few of the user's meals with known leftovers,
     scoring the subtracted kcal against what was actually left.

## 2b. Phase 1b — Offline food tables (D11)

Status 2026-10-17: USDA (SR Legacy, Foundation, FNDDS survey) and BLS 4.0 are built and
searched on the emulator: 20,687 foods, 13,006 with portions, a 1.4 MB asset. Fineli is dropped
(D11, D12). Only USDA rows carry portions; BLS has none (upstream's backend has
the same gap). Pelmeni and khachapuri are in no table and go to D9.

1. [x] `fork/tools/build_food_db.py`: BLS 4.0 and USDA (SR Legacy, Foundation, FNDDS survey),
   normalised to per 100 g plus portions, with the source on every row, written to
   `assets/fork/foods.json.gz`.
2. [x] `LocalFoodDataSource` (`lib/fork/food/`) registered as the `SpFoodDataSource` (seam S1),
   so search and AI matching use it in place of the hosted backend.
3. [x] Credits. Settings → Food databases already names BLS and FDC with links (upstream's
   `SPConst`, same source codes as our rows). The rest of CC BY 4.0 (creator, licence, changes)
   is in Settings → About → View licenses, registered by `lib/fork/food/food_table_licenses.dart`
   from seam S1.
4. [x] Check, 2026-10-22: `test/fork/staple_foods_test.dart` runs upstream's resolver over the
   table alone, no Open Food Facts.
   - Pass: rye bread, kefir, buckwheat, quark (biezpiens), cottage cheese.
   - Gap: grey peas, in no table. That goes to recipes (D12): phase 1c's starter "grey peas
     with bacon".
   - Wrong sibling, not a gap: `egg` → *Egg, creamed*, `eggs` (typed "2 eggs") → a Foundation
     yolk row, `pizza` → *Pizza, no cheese*, `pepperoni pizza` → *…with meat other than
     pepperoni*. The right rows are in the table. Upstream's tie-break picks the shorter sibling,
     the same on its backend: it pins egg as a known miss, and #1231 (open) is about it. Fix
     upstream there (rule 1), not in the fork. Until then the review screen offers the siblings.
   - Not run: the pizza photo, which needs an AI key.

## 3. Phase 2 — Backup to Google Drive (D10)

**Status 2026-10-23: done** (`fork/backup`), unblocked by D15.
- Upstream's import fixes (#1369, #1381, #1398) cherry-picked from `develop`, to drop at v2.5.0.
- **Ported after review** from theoleuthardt `personal` (#93, #94, #97): water, fasting sessions
  and custom meals in the backup, as `BackupExtras` (S21), plus the adaptive switches and
  check-ins. Review: sound (everything decoded before the first write, writes by id, every file
  optional); dropped their profile and app-settings files (#95, #96: separate work) and their
  `AutoBackupService`'s WebDAV and iOS targets, keeping its shape (one shared run, rotation by
  name, errors stored). Their folder backup (#156) is iOS only; the Android one is ours (S22).
- Settings → Automatic backup (S23): a folder picked once; on leaving the app, at most hourly,
  `openbite-YYYY-MM-DD.zip` (another profile: `openbite-<tag>-…`), newest 14 kept. Restore is
  upstream's Import.
- Checked on the emulator: the zip carries the fork's files; importing it and backing up again
  gives the same counts (no duplicates).
- **Not done:** every profile in one backup (theoleuthardt #96; today each profile backs up
  when it is the active one), the app settings (#95), restore from onboarding (#155, upstream
  #1355), encrypting the zip.

The app writes backup files; it syncs nothing itself (openGym-Hevier's D20). Upstream ONT has
only a manual export (`export_data_usecase.dart`, a `FilePicker.saveFile` dialog each time), so
unlike openGym the automatic part has to be built.

Build after merging `v2.5.0` (D6), which carries the import fixes this phase relies on. Port from
theoleuthardt `personal` where it fits (§0b): custom meals in the backup, restore from onboarding.

1. **Folder.** Settings → Auto-backup: pick a folder once with the system picker (Storage Access
   Framework, `ACTION_OPEN_DOCUMENT_TREE`, persisted grant). A tree grant can also delete old
   files and survives app updates; after a reinstall the user picks the folder again. Not
   MediaStore: an app loses access to its own files there after a reinstall, so it could not
   prune them. Writing through SAF needs either the `saf` package (MIT, Android only, 2.1.2) or a
   small platform channel like openGym's `BackupFolderPlugin.java`. Decide when building:
   upstream's view on a new dependency decides it.
2. **When.** When the app goes to the background (`AppLifecycleState.paused`) and something
   changed since the last file, write today's file. Today's file is overwritten, and older ones
   beyond the newest 14 are deleted. Writing while the app is still in the foreground avoids
   WorkManager and Android's background limits. A diary change logged and the app killed at once
   waits for the next pause.
3. **What.** Upstream's JSON export zip: intakes, activities, tracked days, recipes, the weight
   log, custom activity templates, and goal settings once #1381 is released (not in 2.4.0). **Gap:** saved custom meals (the
   user's own foods) are not in the bundle (`docs/export-format.md`), so a restore loses them.
   That is an upstream fix worth proposing alongside #1356. Fork-only data (phase 3's trend and
   check-ins) must be added to it, or a restore loses it.
4. **Sync.** A sync app mirrors the folder to Drive (Autosync for Google Drive, FolderSync, or a
   Syncthing fork; the official Syncthing Android app was discontinued in 2024). Not the app's
   concern; the settings screen names the option.
5. **Restore** is upstream's Import, which upserts by id since #1369. That fix is on `develop`, not in 2.4.0: build phase 2 after the release that carries it, or restore appends duplicates.
6. **Upstream.** This is #1356 (Syncthing) and covers #585 (Drive/iCloud). Ask on #1356 before
   building whether a PR is welcome, and whether a dependency or a platform channel is preferred.

## 4. Phase 3 — The MacroFactor core (D13)

Pure Dart in `lib/fork/`, unit-tested in `test/fork/` (rule 3), beside upstream's code, never
replacing it. Design and sources: [research/phase3-macrofactor-algorithms.md](research/phase3-macrofactor-algorithms.md).

1. **Simulator first.** Synthetic users with a known expenditure: weights from energy balance,
   daily water noise, missed weigh-ins, unlogged and under-logged days, step changes in
   expenditure, and for some users a menstrual water swing (about 1–2 kg over a ~28-day
   cycle; upstream ignores the cycle). It scores stability (kcal/day moved per day), responsiveness (days to follow a
   step) and error against the truth, as MacroFactor reports. Everything below is tuned on it.
2. **Smoothed trend.** Interpolate missing days, exponential smoothing (start at 10%/day). Shown
   on the weight chart when the setting picks it; upstream's 7-day average stays the default.
3. **Expenditure.** 20-day change, Forbes/Hall energy density (flat 6,000 fallback), blended
   estimate from the IOM prior, data rules (4 of 7 days logged, a weigh-in a week, else carry).
   Checked against the simulator and upstream's demo-seeded year (`SEED=1`).
   The 20-day window is shorter than a cycle, so a water swing can read as a real change:
   measure how far the estimate and the proposed target wobble on the cycle users. If the
   capped weekly change doesn't absorb it, try a window covering a full cycle for them.
4. **Weekly check-in.** Past week (average intake, trend change, expenditure) and a proposed
   target with a capped change; accept or edit. Adaptive mode stops adding logged activities.
   Fork state in its own Hive box, included in backups (phase 2.4).
5. **Settings switch** for trend and target, behind seams in the settings screen and in
   `calorie_goal_calc.dart`'s caller.
6. **Goal ETA** from the trend and the chosen pace.

**Status 2026-10-22: steps 1–6 done** (branch `fork/adaptive`, seams S12–S15). Simulator
results in [research/phase3-simulation.md](research/phase3-simulation.md). On the emulator with
the demo profile: the switch shows the check-in card at once; the check-in read 3,032 kcal
expenditure and proposed 2,648 (moved the 200 kcal most from the formula's 2,848, 2 of 7 days
logged); Accept hid the card and home went from 933 to 733 kcal left; the smoothed trend draws
dashed on the weight chart. *2026-10-23:* the adaptive state is per profile (an
encrypted box per profile, seam S16), so a new profile and its onboarding start on the formula;
"How your goal is calculated" says when the check-in's target is the goal (S17); the dev entry
loads the switches (S18). Emulator: two profiles kept their own goals (2,648 adaptive, the
other on the formula) across switches both ways. Not yet: energy shown in kJ for kJ users in
the check-in screens.

Upstream: open an issue first, with the simulation results. The maintainer cites a source for
every calculation; everything except the tuned weights has one, and those come with the
simulation. If declined, it stays in the fork behind seams.

## 4b. Phase 4 — Model comparison (last)

Moved last 2026-10-22 (D7): any capable vision model does the job, and every user brings their
own key and model anyway, so the comparison only picks the suggested default. Until it runs,
Haiku 4.5 and luna stay the defaults.

`fork/eval/photos.json` holds 23 photos taken from recipe pages that
publish macros: Latvian and Baltic (5), Georgian (6), Slavic dishes common in Latvia (7),
pizza and everyday (5). Each entry records the words a correct answer contains, the pieces to
count where countable, and, where the photo shows a known amount, the servings shown.
`fork/tools/fetch_eval_photos.py` downloads the photos into `build/` (they are the sites',
not ours). `FORK_EVAL_OPENROUTER_KEY=... flutter test test/fork/eval` runs upstream's photo
path unchanged for each model (`FORK_EVAL_MODELS`, default Haiku 5.5, Haiku 4.5, luna) and
looks every name up in the bundled table. It writes `build/fork-eval/<time>/report.md`, with
the dish named, the count right, and names with no table match (phase 1c's job). Upstream's
photo path returns names and counts, not grams, so photos are scored on those. The recipe
macros score phase 1c's breakdown: its per-serving total against the page's. Then ten of the
user's own meals. This decides Q3 and which default leads.

**Real-model checks moved here from phase 1c (2026-10-22):**
- Photo → breakdown over the test set, scoring the per-serving total against the recipe
  pages' macros (khachapuri adjaruli, khinkali, pelmeni, borscht, cold beet soup, stuffed
  peppers).
- Khachapuri, pelmeni and grey peas, typed and photographed by the user; check the model's
  names find the saved recipes (a one-word "sklandrausis" misses "Sklandu rauši").
- Until then, phase work is checked with the fake AI (`FORK_FAKE_AI`, `lib/fork/dev/fake_ai.dart`).

*Status 2026-10-19:* harness built and the 23 photos downloaded; not run yet (needs an
OpenRouter key).

**Then upstream (user, 2026-10-23):** no upstream PRs, issues or #1356 questions until the
app is tested live, after the real-model checks above. Queued: `feat/photo-note`,
`feat/leftovers`, the word-search change, the phase 3 issue with the simulation results, and the
#1356 question for phase 2.

## 5. Backlog (after phases 1–3)

Not built anywhere yet:

- *Done 2026-10-23:* recents ranked by the meal being added to (seam S19,
  `lib/fork/recents/`). A food's place sums its logs over 90 days, each halving every 30 days,
  and a log in another meal counts a quarter. On the emulator, breakfast and dinner list the
  demo foods in different orders.
- *Done 2026-10-23:* top contributors per nutrient (#1266), on `feat/nutrient-contributions` off
  `develop`, carried by cherry-pick (PR not opened yet).
  - Tapping carbs, fat or protein on Home lists the day's foods, most first, with grams and
    share. A food logged in two meals is one row.
  - Checked on the emulator.
  - Not done: tapping a food to open its details, which the issue also asks for.
- *Done 2026-10-23:* release checks after openGym-Hevier's D26/D38.
  - `fork/tools/release-check.sh [--apk <file>]` runs the gates: secrets in history, working
    tree and APK; Trivy; `pubspec.lock` against a reviewed list; and the APK's signing,
    scheme, debuggable flag, permissions, native libraries and exported components.
  - Allow-lists live in `fork/security/`, each entry with its reason.
  - A release APK signed with a throwaway key passes everything except the certificate pin.
  - **Before daily use:** make the fork's release keystore, then pin its digest in
    `~/.config/opennutritracker-fork/apk-cert.txt`.
  - Seen: ML Kit's barcode scanner brings in Google's datatransport, which sends usage
    metrics to Google. That's upstream's to decide.

Lower: already built elsewhere (§0b), port or wait:

- AI nutrition-label scan (aeobrien "Phase 11", cattosmile, theoleuthardt's on-device OCR).
- AI recipe builder from text or a URL (reference: aeobrien "Phase 12": unmatched
  ingredients fall back to search, label scan or manual entry).
- Re-log yesterday's meal in one tap (theoleuthardt copies entries, meals or days to any date).
- **Contribute missing barcodes to Open Food Facts** (theoleuthardt sends scanned values and
  the label photo). Today the app only reads OFF; upstream just links to the official OFF apps
  (`import_custom_food_data_dialog.dart`). OFF is the only source that takes contributions: USDA
  and BLS are fixed tables (D11).
  - Entry point: a barcode scan that finds nothing, which already offers "create custom meal"
    (#995). Add "also submit to Open Food Facts" there. Pairs with the AI label scan above.
  - The user's own OFF account (free; username, email, password), stored like the AI keys. No
    shared app account: OFF discourages anonymous edits.
  - OFF's app rules: a User-Agent with app name, version and contact; ODbL credit; personal
    volume only.
  - Only real label data goes up: a hand-entered or label-scanned product with a barcode.
    Never D9 estimates, D12 breakdowns or recipes.
  - Upstream first (rule 1): it helps every ONT user. It adds a data-sharing path, so the
    privacy policy and `docs/play-data-safety.md` change with it.
- Health Connect weight import: upstream PR #1296, take it when merged.

## 6. Open questions for the user

| # | Question | Answer |
|---|---|---|
| Q1 | Which AI model or provider? | D7 |
| Q2 | Install beside the official app? | D8: yes, as OpenBite |
| Q3 | Grounded only, or estimate when nothing matches? | D9 |
| Q4 | How to get generic foods (USDA/BLS) without ONT's backend key? | D11 (option b: USDA and BLS bundled; Fineli dropped) |
| Q5 | Drive backup through a sync app? | D10 |

**Q4.** Open Food Facts is mostly packaged, branded products: searching "banana" or
"boiled egg" returns brands, not the generic food. The generic foods and their portion sizes
("1 slice", "1 medium") come from ONT's backend (USDA, BLS), and AI matching resolves against
those portions (`sp_food_data_source.dart` `fetchPortions`). Without the backend key, AI
describe and AI photo mostly fall back to D9's estimates. Options: (a) ask the maintainer
whether a personal fork may use the hosted backend's publishable key; (b) bundle USDA's
public-domain generic foods (Foundation + SR Legacy, a few thousand foods with portions)
into the app as a local, offline database, which needs no server and no key but is a
feature of its own; (c) run the backend ourselves, which is a server (D2 rules it out).

## 7. Risks

- **Upstream speed:** 100+ commits in 90 days, mostly by the maintainer. Merge each release and keep seams few.
- **Storage:** the fork must not change upstream's Hive types. Fork data goes in its own box, and it needs to be included in backups (phase 2.4).
- **Grounded AI** may disappoint on mixed home-cooked dishes; phase 1c's check measures it.
