# Design decisions

Agreed with the user. These override anything in PLAN.md that says otherwise. Change a
decision here first, with the date, before changing the code. Take the next free number for a
new one.

## Base and scope

Agreed 2026-10-17.

| # | Decision |
|---|---|
| D1 | **Base: OpenNutriTracker.** Compared with SparkyFitness (needs its own Express/Postgres server), Fud AI (no food-database search; whole diary in one preferences entry), NutriTrace, Waistline, FoodYou and FitBook. ONT has search, barcode, recipes and AI text/photo logging. Data stays on the phone in encrypted Hive, and it has an active community. |
| D2 | **Android only, no server of our own.** Third-party services the app already calls (Open Food Facts, ONT's food backend, the user's own AI provider) are fine. |
| D3 | **Must-have logging methods:** barcode, search, recipes, AI text describe, AI photo, AI photo with text. **Not wanted:** voice logging (the keyboard's dictation covers it). |
| D4 | **Bring your own AI**, through ONT's existing providers (Anthropic, OpenAI, OpenRouter, any OpenAI-compatible server). |
| D5 | **Testing on the Android emulator**, the `xperia1vi_api36` AVD shared with openGym-Hevier (`fork/tools/emulator.sh`). |

## Git

Set up 2026-10-17 the way openGym-Hevier does it (its PLAN.md §1.1).

| # | Decision |
|---|---|
| D6 | **Branches.** `develop` mirrors `upstream/develop` (fast-forward only, never a fork commit); upstream merges everything there and only cuts releases to `main`. `fork/main` is the fork's trunk. Feature work goes on `fork/<topic>`, and upstream-bound work on a branch off `develop`. Merge, never rebase; `rerere` and `zdiff3` are on. |

## First answers

Agreed 2026-10-17 (PLAN.md §6, Q1–Q3 and Q5).

| # | Decision |
|---|---|
| D7 | **A cheap vision model; the database supplies the numbers.** Start with `gpt-5.6-luna`, the cheapest model on upstream's screened list (`lib/core/utils/ai_model_catalogue.dart`: about a tenth of Sonnet's per-token price; Haiku 4.5 is about $0.0017 a photo). Phase 1.3 compares it with Haiku 4.5 on the user's own meals before we settle. Keep upstream's grounding: the model names foods and portions, and nutrition values come from the database. |
| D8 | **Own app id and name**, installed beside the official app (openGym-Hevier's S7 approach: a fork-owned Gradle file applied by one seam line). The name is still to be chosen. |
| D9 | **Estimate when nothing matches.** When the model names an item the database can't match, the model's own estimate is offered for it instead of the item being dropped. The entry is clearly marked as an AI estimate and is editable before logging. Fork-only behind a seam, because upstream deliberately forbids model-supplied numbers (`meal_items_api.dart`); the fork does not offer it upstream. |
| D10 | **Google Drive backup through a sync app**, no Drive code in the app (PLAN.md phase 2; openGym-Hevier's D20). |

## Food data

Agreed 2026-10-17 (PLAN.md §6, Q4).

| # | Decision |
|---|---|
| D11 | **Generic foods come from open tables bundled into the app as an offline SQLite asset. No API key and no backend.** Base: **USDA FoodData Central Foundation + SR Legacy** (public domain, English names). It is the only free source with household portions ("1 medium", "1 slice"), which AI matching needs. Local layer: **Livsmedelsverket** (Sweden, CC BY 4.0, keyless JSON API, English names), the nearest open table to the user's mostly Latvian diet (rye bread, quark, kefir, herring, buckwheat, potatoes). Latvia publishes no open table, and Estonia's NutriData has no stated open licence. Packaged and branded products keep coming from Open Food Facts live, as upstream does. Dishes no table covers (Georgian, many Latvian home dishes) fall through to D9's estimate. A script in `fork/tools/` builds the asset. Credits go on upstream's Sources screen. Candidates, after their licences are checked: Fineli (Finland, more composite dishes; open data, but no licence stated and the download sits behind a Cloudflare challenge) and BLS 4.0 (Germany, ~7,100 foods, "licence-free" with no named licence). Not usable: NEVO (unchanged copies only). |
