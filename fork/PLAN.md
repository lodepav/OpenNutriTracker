# Plan — MacroFactor features on OpenNutriTracker

Started 2026-10-17. Decisions in [DECISIONS.md](DECISIONS.md) win over this file.

## 0. What upstream already gives us

Checked on `develop` at 1bc934b1 (2026-10-17).

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
| Backup | ⚠️ manual JSON/CSV zip export and import. Import onto a live install was fixed on `develop` (#1369, #1398). |

## 1. Pre-work

- [x] Fork on GitHub (`lodepav/OpenNutriTracker`), clone, `upstream` remote, `develop` and `fork/main` branches (D6).
- [x] Build rig: Flutter 3.44.6 in `~/flutter`, OpenJDK 24, debug APK builds.
- [x] `fork/tools/emulator.sh` (D5). `SEED=1` builds upstream's demo-data entry point, which gives a year of diary and weigh-ins, enough to exercise an expenditure estimate.
- [ ] GitHub → Actions on the fork: disable the workflows that need upstream's secrets (store deploys, Weblate, project boards). Disable, don't delete: deleted files conflict on every upstream edit.
- [ ] Fork identity, if wanted (Q2): a `fork` flavour with its own app id and name, set in a fork-owned `android/app/fork.gradle` applied by one seam line, as openGym-Hevier's S7 does.
- [ ] `.env`: placeholders stay; ONT's hosted backend isn't used (D11).

## 1c. Phase 1c — Dishes as recipes (D12, revised D9)

Before phase 1, at the user's request.

1. **Breakdown.** Find where the resolver gives up on an item (`resolve_parsed_meals_usecase.dart`).
   For that item, ask the model for its ingredients with grams in a second, text-only call
   (cheap; the photo isn't resent), then resolve each ingredient the usual way. Fork-only,
   behind a seam. The first step is reading how upstream's three clients build their JSON schema,
   so the breakdown reuses it.
2. **Review screen.** The dish shows as a group of its ingredients, each editable, and is
   marked as an AI breakdown. Ingredients that still match nothing carry the model's estimate,
   marked as such (D9).
3. **Save as recipe.** One action stores the breakdown through upstream's recipe builder. Check
   that a saved recipe is found first next time, by search and by the AI resolver.
4. **Starter recipes.** The four CC0 Latvian recipes, entered as recipes on first run (or via a
   bundled recipe import file, if upstream's JSON recipe import fits).
5. **Check:** khachapuri, pelmeni and grey peas with bacon, typed and photographed, give
   plausible totals with every number traced to a table row or a marked estimate.

## 2. Phase 1 — AI logging complete

1. **Photo + note.** Send the user's typed text along with the photo, in all three clients
   (`anthropic_meal_items_api.dart`, `openai_meal_items_api.dart`,
   `openai_compatible_meal_items_api.dart`) and the add-meal screen. Upstream PR (rule 1).
2. **Gemini.** Upstream PR #1257 fixes Gemini through the OpenAI-compatible client. Review it,
   then merge it into `fork/main` until upstream takes it, if Gemini is the model (Q1).
3. **Estimate when nothing matches (D9):** covered by phase 1c.
4. **Photo test (D7).** `fork/eval/photos.json` holds 23 photos taken from recipe pages that
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

## 2b. Phase 1b — Offline food tables (D11)

Status 2026-10-17: USDA (SR Legacy, Foundation, FNDDS survey) and BLS 4.0 are built and
searched on the emulator: 20,687 foods, 13,006 with portions, a 1.4 MB asset. Fineli is dropped
(D11, D12). Only USDA rows carry portions; BLS has none (upstream's backend has
the same gap). Pelmeni and khachapuri are in no table and go to D9.

1. `fork/tools/build_food_db`: Fineli, BLS 4.0, USDA Foundation + SR Legacy, normalised to
   per 100 g plus portions, with the source on every row, written to a SQLite asset. First
   check: which tables have English names and portion sizes (USDA does; Fineli and BLS to
   be checked). AI matching needs both.
2. A local food data source beside OFF in search and in AI matching, behind a seam where
   upstream's `sp_food_data_source.dart` is called. Local results rank first for generic foods.
3. Credits on the Sources screen (CC BY: THL/Fineli, Max Rubner-Institut/BLS; USDA).
4. Check: rye bread, biezpiens (quark), kefir, buckwheat, grey peas, "2 eggs" and a pizza
   photo resolve without D9's estimate. Gaps found here decide whether Livsmedelsverket is
   added.

## 3. Phase 2 — Backup to Google Drive

Proposed, following openGym-Hevier's D20 (Q5): **no Drive client in the app.**

1. **Automatic export.** After a diary change (debounced), write the export zip into a folder
   the user picks with the system picker, one dated file a day, newest N kept. This is
   upstream issue #1356 (Syncthing) and covers #585 (Drive/iCloud), so it is an upstream PR.
2. **A sync app** on the phone (Autosync for Google Drive, FolderSync, Syncthing) mirrors the
   folder to Drive. No Google sign-in, no OAuth client, no Play Services, nothing to carry
   across merges.
3. **Restore** is upstream's Import.
4. Fork-only data (phase 3's check-ins) must be in the export, or a restore loses it: a seam
   in the exporter, or upstream adopting the feature.

Reference: Albert071/OpenNutriTracker's WorkManager auto-export (it uses a Drive service
account, which is not the approach here).

## 4. Phase 3 — The MacroFactor core

Pure Dart in `lib/fork/`, unit-tested in `test/fork/` (rule 3), checked on seeded data.

1. **Trend weight.** Compare ONT's 7-day moving average with an exponentially smoothed trend
   (MacroFactor's style: less lag, no jumps when a weigh-in is missing). Upstream PR if the
   case is good.
2. **Expenditure estimate.** Port SparkyFitness's `AdaptiveTdeeService.ts` (MIT): intake minus
   the trend's weight change × energy density, over a 28-day window, with confidence levels,
   a plausibility clamp against the formula TDEE, and handling of days not logged.
3. **Weekly check-in.** Once a week, a screen that shows the past week (average intake, trend
   change, expenditure) and proposes new calorie and macro targets for the goal and pace. The
   user accepts or edits them. The proposal is adherence-neutral: it uses what was eaten, not
   the old target.
4. **Goal ETA** from the trend and the chosen pace.

Upstream: open an issue first. The maintainer cites a source for every calculation (the
in-app Sources screen) and lists a fixed calorie target (#671) and gram macro goals (#642) as
priorities. An adaptive target with citations may fit; if not, it stays in the fork behind
seams.

## 5. Backlog (after phases 1–3)

- AI nutrition-label scan (reference: aeobrien/OpenNutriTracker "Phase 11").
- AI recipe builder from text or a URL (reference: aeobrien "Phase 12": unmatched
  ingredients fall back to search, label scan or manual entry).
- Faster logging: recents ranked by time of day, re-log yesterday's meal in one tap.
- Top contributors per nutrient.
- Release checks like openGym-Hevier's D26/D38 (gitleaks, Trivy over `pubspec.lock`, APK
  permissions and signing), before the first build for daily use.
- Health Connect weight import: upstream PR #1296, take it when merged.

## 6. Open questions for the user

| # | Question | Answer |
|---|---|---|
| Q1 | Which AI model or provider? | D7 |
| Q2 | Install beside the official app? | D8 (name still open) |
| Q3 | Grounded only, or estimate when nothing matches? | D9 |
| Q4 | How to get generic foods (USDA/BLS) without ONT's backend key? | D11 (option b: USDA, Fineli, BLS) |
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

- **Upstream speed:** 100+ commits in 90 days, mostly by the maintainer. Merge `develop` often and keep seams few.
- **Storage:** the fork must not change upstream's Hive types. Fork data goes in its own box, and it needs to be included in backups (phase 2.4).
- **Grounded AI** may disappoint on mixed home-cooked dishes; phase 1.3 measures it before we build on it.
