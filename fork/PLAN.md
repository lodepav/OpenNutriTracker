# Plan — MacroFactor features on OpenNutriTracker

Started 2026-10-17. Decisions in [DECISIONS.md](DECISIONS.md) win over this file.

## 0. What upstream already gives us

Checked on `develop` at 1bc934b1 (2026-10-17). `fork/main` is based on upstream's releases since 2026-10-22 (D6): `v2.4.0`, then `v2.5.0` merged 2026-10-23; the phase 1c files read on `develop` are identical in 2.4.0.

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
| Backup | ⚠️ manual JSON/CSV zip export and import. Import onto a live install appended duplicates in 2.4.0; fixed in 2.5.0 (#1369, #1398). |

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
| Backlog: label scan | theoleuthardt (on-device OCR, iOS only), cattosmile/OpenNutriTrackerPlus (AI scan), aeobrien | Done: cattosmile's label rules, without its research and estimating merge (S29) |
| Backlog: AI recipe builder | aeobrien "Phase 12" | Done our way (S30): bulk add's rows saved as a recipe; a link read from its schema.org data, not sent to a model |
| Backlog: re-log yesterday | theoleuthardt: copy entries, meals or days to any date; upstream #842, #1265 | Lowered |
| Backlog: OFF contributions | theoleuthardt: send scanned values and the label photo to OFF | Done without the photo (S32, S33) |
| Health Connect weight | Upstream PR #1296 | Done as our own take on it (S27); swap when upstream releases it |
| Backlog: top contributors per nutrient | Upstream issue #1266, no code | Unchanged |

Also seen: cattosmile identifies unpackaged food from a photo with a web-search fallback,
worth a look when phase 1c's breakdown is designed.

## 1. Pre-work

- [x] Fork on GitHub (`lodepav/OpenNutriTracker`), clone, `upstream` remote, `develop` and `fork/main` branches (D6).
- [x] Build rig: Flutter 3.44.6 in `~/flutter`, OpenJDK 24, debug APK builds.
- [x] `fork/tools/emulator.sh` (D5). `SEED=1` builds upstream's demo-data entry point, which gives a year of diary and weigh-ins, enough to exercise an expenditure estimate.
- [x] GitHub Actions off on the fork (2026-10-19). Every upstream workflow needs upstream's secrets or acts on upstream's issues and Weblate, and none had ever run here, so Actions is switched off for the whole repo (Settings → Actions) rather than per workflow; that also covers workflows upstream adds later. The files stay: deleted files conflict on every upstream edit. Switch it back on, and disable workflows one by one, if the fork ever wants CI of its own.
- [x] Fork identity (Q2, D8): **OpenBite**, app id `io.github.lodepav.openbite`, set in `android/app/fork.gradle` (S20). Launcher name only.
- [ ] Release keystore and its pinned digest: the user makes it later (2026-10-23).
- [x] Health Connect weight import (item 3, 2026-10-23): our own take on PR #1296 (`lib/fork/health/`, S27, S28). Each day gets its latest reading; a typed or edited weight is never replaced; a deleted day stays empty until a newer reading; the newest imported row becomes the current weight. Fake scale under `FORK_FAKE_AI`. Not done: the Play Health Connect declaration for READ_WEIGHT; real-device check in phase 4.
- [x] OpenBite in the app's own text (2026-10-23, `fork/tools/rebrand.sh`, S31) and its own icon, a diary page with a bite, themed-icon layer included (`fork/tools/launcher_icon.py`, S34). The splash and the in-app logo too (2026-10-23, S35): Android 12's launch screen shows the page whole and the Flutter splash takes the bite. Not done: searching the trademark registers before publishing under the name.
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
- Upstream's import fixes (#1369, #1381, #1398) cherry-picked from `develop`; released in v2.5.0, whose merge (2026-10-23) replaced them.
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
- *Done 2026-10-23:* the profile and the app settings in the backup (`user_profile.json`,
  `app_settings.json` in `BackupExtras`), ported after review from theoleuthardt #95. Review:
  sound (a whitelist of device-wide settings laid over the current config; consent, demo flag,
  goals, health-import state and day boundary left out; enums by name; everything checked
  before the first write). Changed here: the reminder switch stays out too (restored "on", the
  reminder would not be scheduled on a new phone); no "also restore profile and settings"
  switch, a restore restores them.
- *Done 2026-10-23:* "Restore a backup" on onboarding's first page (S37, upstream #1355), after
  theoleuthardt #155, which restores from their WebDAV server; here it is upstream's Import of a
  backup file (an auto-backup zip from the folder works). Behind the policy checkbox, like "Try
  demo"; a backup with a profile records the policy and the crash-report choice and goes into
  the app (and out of demo mode); one without keeps its data and the setup goes on. Tried on the
  emulator from a fresh install. The restored theme, accent, kilojoules and language show at
  once, from onboarding and from Settings' import (S38).
- *Done 2026-10-23:* every profile in one backup (`ProfilesBackup`, S21), ported after review
  from theoleuthardt #96. The zip keeps upstream's layout for the active profile and adds
  `profiles.json` and a `profiles/<id>/` folder per other profile, written and read by upstream's
  own export and import run on that profile's boxes. Review: sound (folders checked before the
  first write, profiles matched by id, the suffix kept unless taken); changed here: no "replace
  everything" mode and the active profile is not renamed; a backup made in another profile is
  refused rather than restored over this one, since its main data would land in the wrong place.
- **Not done:** encrypting the zip.

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
other on the formula) across switches both ways. *2026-10-23:* the check-in screens show
and take kJ for kJ users (`lib/fork/units/energy_text.dart`).

**More from MacroFactor** (asked 2026-10-23, branch `fork/mf2`):
- *Done:* an Expenditure card on Trends (S40): the estimate each day over the picked range,
  logged intake dashed beside it, and the mean balance of the logged days. It reads the
  check-in's history and shows whether or not the adaptive target is on; nothing before the
  first weigh-in.
- *Done:* a fixed target (upstream #671), in kcal or as protein, carbs and fat in grams, and
  targets by weekday (calorie shifting), in Settings → Trend and calorie target (S12, S14,
  S41). The target is formula, adaptive or fixed; the weekday shift adds to any of them and the
  dialog shows the week's net. Fixed grams scale with a shifted day. In the backup with the
  rest of `fork_adaptive.json`. Not ported: theoleuthardt's training-day goals (a shift by
  weekday covers a set schedule). Limit: a goal is the logical today's, so an entry copied to
  another weekday's empty day takes today's shift, as it already takes today's activities.
- *Done:* a goal planner on Trends (S40): the trend of the past 60 days, the weight curve
  projected at a pace picked on a slider (−1 to +1 kg a week), the date the target weight is
  reached at that pace and at the trend's own, and the daily target the pace needs at the
  measured expenditure (before the check-in's cap and upstream's taper). "Use this pace" saves
  it to the profile through upstream's profile update, the goal following its sign.
- *Done:* a food basket (MacroFactor's multi-add, S42): "Add to basket" on a food's page takes
  it at the chosen amount and returns to search; a bar under the results counts the basket and
  its energy, and its review removes foods or logs them all, each through upstream's add.
  One meal of one day at a time: picking for another empties it. Upstream's own multi-food
  path stays the typed bulk add.
- *Done:* meals planned ahead (S43): the basket's "Plan, don't log" puts its foods on that
  day's meal (a future day is opened from the Diary's calendar); Home and the Diary show the
  day's plan, counted nowhere until a tick logs a food on its planned day and meal ("Log all"
  for the lot). Kept in the fork's per-profile box beside the adaptive state, and in the
  backup as `fork_plan.json`, every profile's included.
- *Done:* body measurements on Trends (S40): body fat %, waist, hips, chest, neck, arm and
  thigh, any of them on a day (a second entry that day replaces it), one charted over the
  range with its latest value and change, entries deletable; inches for lb and st users. The
  latest body fat % of the past 90 days replaces Deurenberg's estimate in the expenditure
  model and the goal planner (MacroFactor uses a measured one too). Per profile, in the
  backup as `fork_measurements.json`.
- *Done:* progress photos on Trends (S40): taken or picked (scaled to 1440 px, JPEG 85), a
  strip newest first, each opening to view or delete, and a compare of any two side by side,
  the oldest and newest to start. The images stay in the app's documents folder
  (`progress_photos/<id>.jpg`, private to the app), the index per profile in the fork's box;
  the backup carries `fork_photos.json` and the images, another profile's inside its folder.
- *Done:* daily steps from Health Connect on Trends (S40, S44: `READ_STEPS`, which upstream
  dropped for Play; OpenBite is not on Play): off until "Read steps" gets the permission;
  then today's, the average and the days at a step goal (8,000, editable) over the range, and
  a bar a day against the goal. Read only, changing no target, since the adaptive
  expenditure already measures what walking burns (MacroFactor too). The last 30 days are
  read (Health Connect's reach for a new app) and kept in the fork's per-profile box, so the
  history grows past it; the last two days are read again each time. Not in the backup: a
  cache, and the permission does not travel. The fake health (`FORK_FAKE_HEALTH`) walks
  4,000 to 12,000 a day.

**More from MacroFactor, round 2** (asked 2026-10-23, branch `fork/mf3`):
- *Done:* remembered amounts (S45): a food's page opens at the number and unit it was last
  logged (or put in the basket) at, ahead of upstream's 1 serving / 100 g, the raw-units
  preference included. Kept per profile for the last 1,000 foods, by barcode or else name; not
  in the backup.
- *Done:* reminders (S46), in Settings → Goals: a daily weigh-in (7:30 to start), moved to
  tomorrow once today's weight is in, and the weekly check-in, once on the day it falls due
  (9:00) or at the next time when it already is, with the adaptive target on. Planned again
  when the app opens or leaves, the profile switches, or the target's settings change (a
  check-in saves them). Per profile; the times are not in the backup.
- *Done:* macro programs (S41), in the target's settings → Macros: protein per kg of body
  weight (1.8 to start) or of lean mass (2.2; weight less the measured body fat of the past 90
  days, else Deurenberg's estimate, which another profile always uses), and a style for the
  rest: balanced (fat 30% of energy), low fat (20%), low carb (carbs 25%) or keto (carbs 30 g).
  Protein is capped at 60% of the energy. Grams follow each day's target, so a weekday's
  shift moves carbs and fat and leaves protein (MacroFactor's macros by weekday). The fixed
  target's own grams win over it. In the backup with `fork_adaptive.json`.
- *Done:* diet phases (S40), a card on Trends: a plan of cuts, maintenance (a diet break) and
  bulks, each a pace and a number of weeks, from a start day. As each phase begins its pace is
  set into the goal once (`PhaseRunner`, at start-up, on resume, a profile switch or a saved
  plan), so a pace changed by hand stands until the next phase; after the last, maintenance.
  Per profile; in the backup with `fork_adaptive.json`.
- *Done:* weekly report (S40), a card on Trends: each Monday-to-Sunday week of the range,
  newest first, with the days logged (of the week's days in the range, so this week counts
  only the days so far) and the mean energy, protein, carbs and fat of the logged days against
  those days' goals. An empty day is not counted, so it does not read as a fast. Built from
  the days Trends already loads; nothing stored.

**More from MacroFactor, round 3** (asked 2026-10-23, branch `fork/mf4`; a bundled generic-food
database, Q4 (b), was offered and declined):
- *Done:* suggestions by time of day (S19): a recent food's logs count in full within about
  two hours of now's time of day, fading to 40% at the far side of the clock, on top of the
  meal and the fading by age. A log at midnight (a day picked, no time) counts 70%.
- *Done:* check-in history, in the target's settings with the adaptive target on: each
  check-in newest first, with the target it set, the change from the one before, the
  expenditure, and the proposal when it was edited. Read from the check-ins already kept.
- *Done:* weight change in the goal planner (S40): how far the trend moved over the last 7, 14
  and 30 days, and that as a pace a week; a span longer than the history is left out.
- *Done:* nutrient explorer, "Nutrients" on the weekly report: over the Trends range, energy,
  the macros and the diary panel's ten nutrients, each as a mean over the days logged against
  those days' goals (else the panel's DRI for the profile), sugar, saturated fat and sodium as
  limits. Each opens the foods it came from, the most first, and says how many foods had no
  figure for it (Open Food Facts often has none), since the mean is then a floor.
- *Done:* Trends arranged (S47): "Arrange cards" at the end of Trends reorders (drag) and hides
  (switch) the cards below the range picker, upstream's and the fork's; Reset puts them back.
  Per profile, not in the backup. A card added later keeps its place after its neighbour.
- *Done:* timeline (S26), the clock icon by the diary's date: the day's foods by the hour they
  were eaten, each with its energy and the running total, those with no time (logged to a
  day, not a moment) first. Tapping one moves it to another time of the same logical day (a
  time before the day's start is the next date); "Add at a time" opens the food search for the
  meal that time suggests, logged at that time. Upstream's meals stay as they are; the
  timeline is a second view of the same entries, not MacroFactor's mealless diary. A move
  swaps the stored entry for one with the same id, since upstream's update changes only the
  amount; the day's totals stand.

**More from MacroFactor, round 4** (asked 2026-10-23, branch `fork/mf5`):
- *Done:* body fat from Health Connect (S48): "Import body fat" beside "Import weight" on the
  health sync screen reads a smart scale's body fat % (READ_BODY_FAT, which upstream dropped
  for Play; OpenBite is not on Play, D8) into the body measurements, each day's latest
  reading, under the weight import's rules: a value typed by the user is never replaced, and a
  deleted day stays empty until a newer reading. The measured value then feeds the
  expenditure estimate and lean mass, as a typed one does.
- *Done:* check-in result in the reminder: the check-in notification tells what the week's
  data gives, "Expenditure 2,640 kcal, new target 2,140 kcal, −60", in the user's energy unit,
  the change against the target the last check-in set. Worked out whenever the reminders are
  planned again (the app opening or leaving), so it reads the data as of the last use; with
  too little data (under 4 logged days or no weigh-in) or a failed estimate it keeps its own
  text. Confirming still happens in the app.
- *Done:* nutrition to Health Connect (S49): "Write nutrition" on the health sync screen
  (WRITE_NUTRITION, asked for when switched on) writes each diary entry of the past 14 days as
  a nutrition record: its meal, time, name, calories, carbs, protein, fat, and fibre, sugar,
  saturated fat and sodium where the food has them. The record's client id is the entry's, so
  an edit (amount, a timeline move) is written over it at a higher version, and a deleted entry
  has its record removed. It runs when the app opens and when it is left, writing only what
  changed (kept per profile); a failed write keeps what went out and tries the rest next time.
  Switched off, what was written stays. Android only in practice: HealthKit has no
  delete-by-client-id in the plugin.
- *Done:* home-screen widget with the macros (S50): upstream's widget is iOS only (Android
  only saves its calorie snapshot), so OpenBite has its own Android widget, "OpenBite macros":
  today's energy (in the user's unit), protein, carbs and fat against their goals, each with a
  bar, tapping opens the app. Home writes the figures beside upstream's snapshot each time it
  loads and redraws the widget; with upstream's snapshot cleared (a profile wiped or switched
  away) the widget asks to open the app, and after the logical day ends it shows nothing eaten
  until the app is opened. Native: `MacroWidgetProvider` (Kotlin, `RemoteViews`) and its
  resources in `android/app/src/fork`.

**More from MacroFactor, round 5** (asked 2026-10-23, branch `fork/mf6`; quick tiles were
offered and declined):
- *Fixed:* the goal planner reloads when a pace is saved anywhere, a diet phase beginning
  included (`paceChanges`), not only from its own button.
- *Done:* diary as CSV (S51): "Export diary as CSV" in Settings' data section shares two files
  for a spreadsheet: every food (logical date, time, meal, name, amount, energy, macros, fibre,
  sugar, saturated fat, sodium) and every day (eaten against the goals, the weight logged, the
  estimated expenditure). The full backup stays the way to move data; this is for reading it.
- *Done:* trend weight widget (S50): a second Android widget, "OpenBite trend weight", with
  the smoothed weight and its change over 7 days in the user's unit, written by Home beside the
  macros. Before the first weigh-in it asks for one.
- *Done, mostly upstream's:* custom nutrient targets. Upstream's Settings → Nutrient goals
  already sets the ten nutrients the explorer follows, but keeps each goal on the day it was set,
  so the explorer measured earlier days of a range against the reference. Now a day keeping no
  goal takes the latest set in the range, and the explorer's "Edit goals" opens upstream's
  screen and measures again when it closes. Energy and the macros keep their own day's goal.
- *Already there:* planned meals were built in round 1 (S43, the meal plan). This round adds the
  plan's protein, carbs and fat to its card's header, beside its energy.
- *Already there:* recipe import from a link (S30, round 3): a link typed into bulk add is read
  from the page's schema.org Recipe data and saved with "Save all as a recipe". Nothing added.
- *Found live and fixed:* a planned food was unreadable once the app restarted (Hive's nested
  maps), so the plan card never showed after a restart; a fork box failing its checksum (an
  emulator killed mid-write) hung the splash, and now opens upstream's recovery screen; the CSV
  wrote 2472.98 as "2473.0". Confirmed on the emulator: both CSV files shared, "Edit goals" saved
  and measured again, the plan card's macros, the trend weight widget placed and showing the
  trend, and a cut beginning today moving the goal planner from -0.40 to -0.50 kg a week.

**More from MacroFactor, round 6** (asked 2026-10-23, branch `fork/mf7`; sharing into the app,
voice logging, scanning in a row and AI reading of recipe pages without recipe data were offered
and declined):
- *Done:* undo after a delete (S52): an entry deleted on Home or the Diary, or a meal's "Delete
  all", goes at once with "Entry deleted · Undo" in place of the confirmation dialog; deletes of
  one day in a row gather into one bar ("3 entries deleted"), and Undo writes them back with their
  ids, so meal groups and the Health Connect export see them unchanged.
- *Done:* history import (S51, S53): "Import history" in Settings' data section reads another
  app's export (CSV, XLSX, or a ZIP of them) by its headers rather than one app's layout: a date,
  calories or energy (kcal or kJ), protein, carbs, fat, a meal where there is one, and a weight
  (lb or kg from the header, or Cronometer's metric rows; asked when no header says). Targets,
  expenditure and trend weights are never taken for what was eaten or weighed. The preview says
  what was found where; days already logged here and weigh-ins already here are kept. Each day
  comes in as quick-add style totals (one entry a meal, or one for the day) at noon, under ids
  from the day, so importing twice adds nothing; they are left out of the recents and of the
  custom meals. The headers are checked against what MacroFactor, MyFitnessPal and Cronometer
  are known to write, which none documents: a real export of each is still to be tried.
- *Checked live* (2026-10-23, emulator, fake AI): a drag to the bin, a meal's "Delete all" ("3
  entries deleted") and a Diary delete each undo back to the same totals; a MacroFactor-style CSV
  over June (already logged in the demo) keeps all 30 days and adds only the missing weigh-ins,
  a copy dated a year earlier imports 30 days and 30 weigh-ins, and importing it again keeps all.

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

**Order of the real-model checks (user, 2026-10-23):**
1. **Haiku subagent replay** (`fork/eval/REPLAY.md`). A Claude Code subagent on Haiku plays
   the model: the app (`FAKE_AI=replay fork/tools/emulator.sh`) or the harness
   (`FORK_EVAL_REPLAY=<dir>`) saves each request, the subagent writes the tool call's input,
   and the same request is answered with it (`ReplayAiClient`, `lib/fork/dev/replay_ai.dart`).
   Covers the photo set, the typed and photographed dishes against the saved recipes, the
   breakdowns and the leftovers, on our plan rather than a key. Close to the raw API, not
   the same: the subagent runs under Claude Code's own instructions.
2. **One live call per client** (Anthropic, OpenAI, OpenAI-compatible) with a real key:
   the request the client builds and the reply it parses, which replay skips.
3. **OpenRouter comparison** (optional): Haiku 4.5, luna and others, which a subagent cannot
   be. Only this picks the default model (Q3).

*First replay run 2026-10-23 (photo set, harness):* dish named 21/23, count right 3/7, 12
dishes with no table match (phase 1c's breakdown takes those), no errors. Missed: the fish
dish (named "fish in tomato sauce") and the stuffed pie. Not yet run in the app.

*Dish checks 2026-10-23 (Haiku replay, `test/fork/eval/dish_eval_test.dart`):* the photo's
dish name broken down by the fork's prompt, each ingredient's first table row, and the total
against the page's per serving; and typed or photographed names against the saved recipes.
- **Breakdown, the six one-serving photos:** khachapuri adjaruli 1054 kcal (page 1123),
  stuffed peppers 357 (329), bolognese 630 (510), borscht 260 (181), cold beet soups 160
  (100, 132), buckwheat with mushrooms 122 (168). Within about a third, except borscht and
  the beet soups, which run high. Protein and carbs follow; fat runs low on the khachapuri.
- **Found:** a qualifier missing from every table row drops the whole ingredient:
  "buckwheat groats, raw" finds nothing, though "buckwheat groats" finds the row. (The
  harness takes the table's first row; the app's resolver does better on some, e.g. a bare
  "wheat flour" is all-purpose in the app and cake flour in the harness.)
- **Typed:** khachapuri, pelmeni, grey peas and "sklandu rausi" find their recipes, inside a
  longer line too. Misses: "sklandrausis" and "2 sklandrauši" (the one-word name, as feared)
  and "adjaruli khachapuri" against a recipe saved as "Adjarian khachapuri".
- **Photographed:** only the adjaruli photo found its recipe. The model names regional dishes
  generically from a photo (pelmeni as "dumplings", sklandrausis as "pumpkin tartlet",
  another khachapuri as "stuffed pie"), as the photo prompt tells it to when unsure; a note
  ("pelmeni") is the user's way to name them.
- **In the app 2026-10-23** (`SEED=1 FAKE_AI=replay`): "khachapuri, 200 ml kefir, grey peas"
  read by the replayed model ("Read by AI"); "Ingredients" on khachapuri gave the harness's
  recorded breakdown unchanged (same request, same key), all four rows on table foods.
  "grey peas" matched a Grey Poupon Dijon mustard: the demo-data entry point
  (`lib/dev/main_dev.dart`) does not save the starter recipes, so there was no recipe to
  find. Also seen: the emulator snapshot's old app data opened on
  `hive_wrong_key_or_corrupted` after a reinstall (cleared with `pm clear`); the onboarding
  walker (`tools/adb/walk-onboarding.sh`) no longer fits the fork's onboarding (imperial
  default, height left empty).

*Fixed 2026-10-23:* (1) resolution drops comma qualifiers from the end when no table row has
every word (`LocalFoodDataSource.fetchSearchWordResults`; a person's search stays exact):
buckwheat with mushrooms now 217 kcal (page 168), nothing unmatched. (2) The starter is named
"Sklandu rauši (sklandrausis)": "sklandrausis" and "2 sklandrauši" find it. An install that
already saved the starters keeps the old name. Not fixed: "adjaruli" vs "Adjarian", which only
a looser word rule would join, and that rule would also join "chickpea" and "chicken".

*Tuning, Opus → Sonnet → Haiku replay, 2026-10-23:* the same photos and dishes answered by
each model's subagent (`FORK_EVAL_REPLAY` takes several folders). The harness now matches
ingredients through the resolver's own ranking, not the table's first row.
- **Counts:** under upstream's photo prompt Opus counted 5/7, Sonnet 1/7, Haiku 3/7; they left
  dumplings, pancakes and tarts uncounted. Two labels were wrong (sklandrausis and syrniki
  show 5, not 6). The S60 count rule takes this to 7/7, 7/7 and 6/7. Dishes are named the
  same as before: 22, 22 and 21 of 23.
- **Count as servings:** bulk add reads a bare count as servings (#622). A recipe's serving
  is a share of the batch, so "14 pelmeni" against the 6-serving starter would log about
  3 kg. The typed path already does this, and S60 would add photos. S61 flags a count larger
  than the batch's servings and holds that row back until the user picks a unit.
- **Breakdowns:** no ingredient unmatched for any model. Opus estimates big, complete servings,
  so its kcal runs well above the pages'. The pages' own serving sizes are arbitrary, so this
  figure does not rank the models.
- **Photo → saved recipe:** this stays the weak spot for all three (Opus 2/4, Sonnet 0/4,
  Haiku 1/4, which moves between runs). Photos come back with generic names: "dumplings",
  "sweet potato tart", "cheese bread", "khachapuri with egg". Candidate: list the user's saved
  recipe names in the photo prompt (untested).
- **Left alone:** "tomato sauce" ranks a steak sauce first (upstream's no-portion penalty,
  about 40 kcal). "kefir, plain" goes to a branded kefir and canola to a branded oil.
  "pomegranate seeds" has no row. The tool schema says quantity is "only if the user stated
  an amount", against the photo prompt's counting. The models counted anyway, and rewording it
  would change every request.

*LIDO and Russian home dishes, 2026-10-23:* 23 more photos (46 in all).
- **Sources:** 13 are LIDO's own dishes, photographed from its Wolt menus. These include
  boiled buckwheat and a karbonāde. LIDO publishes no restaurant macros: Wolt's product info
  lists ingredients and allergens only, and its catalogue has none either. The exception is the
  karbonāde, whose packaged twin has a label on barbora.lv (105 g piece). The other 10 are the
  same dishes from eda.ru recipes, which give macros per serving.
- **Results:**
  - Dishes named: Opus 43, Sonnet 39, Haiku 39 of 46.
  - Counts right: 14, 12 and 11 of 16.
  - Opus named all the regional dishes. Sonnet and Haiku did not:
    - the karbonāde was "fried chicken fillet" and "fried stuffed flatbread";
    - grey peas were "chickpeas" and "black beans";
    - LIDO's French-style pork was chicken or a cottage-cheese casserole;
    - eda's chops in batter were "stuffed pancakes" and "fried pastries".
  - LIDO's bread soup is a layered dessert, and it finds the starter of that name.
  - The Opus name for grey peas ("stewed peas with onion and bacon") does not find the saved
    recipe, because it lacks "grey".
- **Dry staples:** every model called the buckwheat "buckwheat", and the resolver gave it the
  raw grain: 343 kcal per 100 g against 115 boiled. Bare "spaghetti", "macaroni", "lentils",
  "pearl barley", "bulgur" and "couscous" did the same. The fix is in
  `local_food_data_source.dart` and applies to resolution only. When the name has no
  state ("raw", "dry", "boiled"…) and the table has the food cooked under its own name, rows
  with more than twice the leanest cooked row's energy and over 50 g carbs are left out. A
  37-name probe changed only those seven. Eggs, meat, raw bacon and oats kept their rows.

*Photo alone against photo with a note, 2026-10-24:* 15 LIDO set meals were added (61 photos
in all). Each plate has two to four parts, which LIDO's menu text lists. The 28 LIDO photos
carry a `user_note` written the way a person would type it, for example "karbonāde, potatoes,
mushroom sauce" or "soļanka, 2 pankūkas with meat, sour cream, beet salad". Some notes leave
out a part the photo shows. Each of those photos runs once alone and once with its note.
- **Dishes named:**
  - alone: Opus 26/28, Sonnet 23/28, Haiku 21/28;
  - with the note: 28/28 for all three. The note also fixes every count (7/7).
- **Set-meal parts named (of 55):**
  - alone: Opus 54, Sonnet 53, Haiku 46;
  - with the note: Opus 55, Sonnet 52, Haiku 54.

  Sonnet with a note sometimes logs only what the note names and drops a dill sauce it can
  see; Opus and Haiku add it.
- **Matching against the table still goes wrong after a right name:**
  - a note's bare "salad" is logged as "salad", which ranks "Salmon salad" first (213 kcal);
  - "pancakes with meat" goes to an egg sandwich on a griddle pancake;
  - "bread soup" goes to a savoury soup at 43 kcal, against LIDO's dessert.
- **Replay slip:** one Haiku subagent wrote four answers under the wrong keys, so two plates
  swapped answers. A fresh subagent answering one request at a time fixed it. The answers
  are worth a spot check against their photos.

*Photo to logged kcal, 2026-10-24* (`calorie_eval_test.dart`): every one-serving photo with
known macros goes through the bulk-add screen's own logic (BulkAddBloc, the resolver, D9
breakdowns). Each row is taken at the amount the screen starts it at, as a user who just
accepts would log it. There are 17 photos: the recipe pages and four LIDO packs whose macros
come from their Barbora labels (pork and chicken cutlets, dill and garlic sauce).
- **Before the fix,** butter logged at 224 g (1,664 kcal) and raisins at 0.5 g. The table's
  default serving was FNDDS's first portion, "1 cup" or "1 raisin". Survey foods now take
  FNDDS's own "Quantity not specified" amount (butter 14 g, raisins 40 g, coffee 360 ml), in
  `build_food_db.py`. That changes 3,807 rows. Portions are unchanged, and a count still
  matches a named portion first.
- **After it, alone / with the note:**
  | Model | Within 25% | Median off | Logged / label, total |
  |---|---|---|---|
  | Opus | 5/17 / 2/5 | 45% / 27% | 97% / 64% |
  | Sonnet | 5/17 / 3/5 | 45% / 12% | 105% / 103% |
  | Haiku | 9/17 / 4/5 | 23% / 12% | 91% / 102% |
- **Totals land near 100%, but single photos still miss widely.** The causes:
  - a dish found in the table starts at 100 g, flagged, since the photo path gives no weight
    (plov: 152 kcal against 753);
  - "meat patty" picks a 97%-lean beef patty, 107 kcal a piece against 330;
  - a note's "2 pork patties" lands on a raw patty row with no serving, so it logs 2 g,
    flagged;
  - "porridge" picks a roasted porridge with vegetable stock.
- **A breakdown is one serving, whatever count the model gave the dish.** That is closer
  than multiplying by the count, since the model's serving of "2 cutlets" is about the
  tray. The breakdown's grams decide the rest: Haiku's chicken cutlet is a 150 g breaded
  fillet, while LIDO's kotlete is a 90 g minced patty.

*Model names pinned to table rows, 2026-10-24* (`test/fork/model_names_test.dart`): the
replays gave 233 dish names and 162 breakdown ingredient names. Each ran through the app's
own resolver; the eval's `tableMatch` now runs it too, portions and all, where it used to
rank rows without their portions. 51 names are pinned to the right row and 20 known misses
are skipped, each with what it logs now.
- **Fixed (S70):** a variant the query did not name scores 0.2 lower: meatless, vegan,
  imitation, baby food. "bacon" logged "Bacon, meatless" and "schnitzel" "Vegan schnitzel".
  USDA's "unprepared" is left alone: it means as sold, the raw row a recipe wants.
- **Tried and backed out (S71, the patch is kept outside the repo):** a tie key ahead of
  upstream's shortest name, counting the words a row adds past the query. It skips FNDDS's
  "NFS" and "NS as to …" segments and plain words (whole, cooked, raw, regular). It fixed 12
  names: rice → "Rice, cooked, NFS" (was fried rice), egg noodles → cooked (was dry, 384
  kcal), bread → "Bread, NS as to major flour", white rice, pork chop, sour cream →
  regular, mayonnaise → regular. But upstream declined exactly this rule (its comment in
  `resolver_relevance.dart`), and it breaks 13 upstream resolver tests whose fixtures pin
  the old order. That is for the user to decide.
- **Known misses left:** a bare word ranks a dish that holds it ("salad" → Salmon salad,
  "fries" → Yuca fries, "tomato sauce" → steak sauce, "tomato paste" → a pasta dish);
  "potatoes" → the skin alone; "porridge" and "bread soup" → savoury BLS rows; "meat
  dumplings" → "Dumpling, no meat", the only row with every word; "butter, unsalted" →
  a pretzel ("unsalted, no butter"), since every word must match and butter says "without
  salt". The typed meals added: "cola" → a 0 kcal ZEVIA diet cola, "coke" → nothing,
  "eggs" → egg yolk, "greek yogurt" → with oats, "granola" → a cookie, "coffee" → a latte.
  S71 would fix the yogurt and the coffee.

*Hard notes and the Latvian locale, 2026-10-24* (`test/fork/eval/hard_note_eval_test.dart`,
all three models):
- **Notes are followed.** A note that contradicts the photo wins ("vistas fileja" on a
  karbonāde gives chicken, "rīsi" on buckwheat gives rice). So do a lower count ("2 ļuļa
  kebabi" over three in the photo), grams (150 g karbonāde, 200 g potatoes, the sauce left
  unweighed), and a food the photo does not show ("kafija ar pienu"). Six of eight cases
  pass for every model.
- **Fractions are dropped.** "puse karbonādes" and "1.5 kāpostu tītenīši" come back with no
  quantity: the models give 0.5 and 1.5, and S60's `_countsOnly` drops a count that is not
  whole unless the note states the same amount with a unit. A bare "1.5" is not exempt, and
  "puse" is a word. The row then starts at one serving.
- **The Latvian locale finds no table row.** Upstream's photo prompt (#650) asks for names
  "in the user's app language". That suits OFF but not the fork's English table. With
  `localeCode: 'lv'` every model named the food in Latvian ("karbonāde", "soļanka",
  "kartupeļu biezenis"), and 0 of about 30 rows per model matched. In English, 13 to 21 of
  28 to 37 did. The dishes are still recognised (15 to 20 of 20). The eval searches the table
  alone. The app's OFF search may catch a few, but every miss is broken down (D9).

Still needs the user: the leftovers photo check, typing and photographing their own
khachapuri, pelmeni and grey peas, and ten of their own meals (photos we do not have).

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
  - Tapping a food opens its details (2026-10-23, `feat/nutrient-contributions` 551a9e9e).
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

- AI nutrition-label scan: done (2026-10-23, `lib/fork/label/`, S29). Ported cattosmile's label-reading
  rules only; its OFF/web research and estimate merge were left out, so only printed values fill the form.
- AI recipe builder from text or a URL: done (2026-10-23, `lib/fork/recipe/`, S30). Ingredient
  lines (typed, or read from a recipe link's schema.org data) go through bulk add's normal read;
  "Save all as a recipe" opens upstream's builder with the ready rows and the page's servings.
  aeobrien's "Phase 12" was reviewed and not ported: a separate recipes rewrite, Claude-only,
  and it sends a page's whole stripped text to the model. Not done: pages without Recipe data.
- *Done 2026-10-23:* copy an entry, a meal or a whole day to any date (`fork/copy`, S24–S26).
  Ported after review from theoleuthardt `personal` #127 (`CopyEntriesUsecase`). Review: sound
  (new ids, the logged food kept, the same time of the target logical day, totals added); it
  writes one entry after another, which fixes upstream's meal-section copy that fires them all at
  once and under-counts the day (worth an upstream PR). Simpler here: no water copy; upstream's
  goal lookups; upstream's `CopyDialog` swapped at its two call sites instead of their rewrite of
  four upstream files. On the emulator, a copied day's totals match the source's.
  Since 2026-10-23 today's entries and meals copy too, and "Select entries" beside "Copy day"
  picks entries one by one, by meal or by the hour, as MacroFactor does, and copies them to now,
  to today at the same times, or to a picked day (same times, or all at a picked time), into
  their own meals or one meal (`lib/fork/copy/select_entries_screen.dart`). A long-pressed
  activity, today's included, copies to a picked day (2026-10-23, `copyActivitiesWithDialog`);
  the activity section's menu still copies other days' to today, as upstream does.
- *Done 2026-10-23:* contribute to Open Food Facts (`lib/fork/off/`, S32, S33), ported after
  review from theoleuthardt `personal` (#81): the user's own account in the keychain, the test
  server until switched off, a preview of exactly what goes out, and only what OFF lacks (name,
  brand, or nutrients when it has none). Offered after saving a custom food with a barcode.
  *2026-10-23:* the offer asks OFF first, then shows only what it lacks as editable fields
  (clear one to leave it out) with the label photo as an optional nutrition picture (kept in
  memory from the label scan, `/cgi/product_image_upload.pl`), and a barcode the scanner can't
  find offers "Add it from its label" (S36), which leads through the label scan to the offer.
  Not done: a live run against OFF (phase 4).
- *Done 2026-10-23 (above, S33, S36):* **Contribute missing barcodes to Open Food Facts** (theoleuthardt sends scanned values and
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
- Health Connect weight import: done as our own take on PR #1296 (S27, S28); swap when upstream releases it.

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
