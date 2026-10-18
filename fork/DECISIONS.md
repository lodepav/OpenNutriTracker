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
| D7 | **A cheap vision model; the database supplies the numbers.** *Revised 2026-10-18.* Starting defaults: **Claude Haiku and `gpt-5.6-luna`**, both from vendors upstream already screened. Haiku 4.5 (upstream's direct Anthropic model) today; Haiku 5.5 ($0.10/$0.50 per M tokens, about $0.0003 a photo, cheaper than luna) is added as a fork catalogue entry, pinned to Anthropic, once it passes the photo test. Cost no longer decides: every cheap model is a few cents a month at personal volume. The photo test (phase 1.4, `fork/eval/`) decides which leads. Chinese open-weight models run as challengers in the same test, served from non-Chinese hosts: GLM-5.3-flash on a US fp8 host, DeepSeek V4.1 flash on Nebius (EU), plus Qwen 3.8 flash (Alibaba, US region). Keep upstream's grounding: the model names foods and counts, nutrition comes from the database, and the photo path never estimates grams (upstream #250). |
| D8 | **Own app id and name**, installed beside the official app (openGym-Hevier's S7 approach: a fork-owned Gradle file applied by one seam line). The name is still to be chosen. |
| D9 | **Break a dish down before estimating.** When the model names a dish the database can't match, it breaks the dish into ingredients with gram amounts (D12), and each ingredient is matched as usual. Only an ingredient that still matches nothing gets the model's own estimate. It is clearly marked as an AI estimate and is editable before logging. Fork-only behind a seam, because upstream deliberately forbids model-supplied numbers (`meal_items_api.dart`). Revised 2026-10-18: ingredients first, estimates last. |
| D10 | **Google Drive backup through a sync app**, no Drive code in the app (PLAN.md phase 2; openGym-Hevier's D20). |

## Food data

Agreed 2026-10-17 (PLAN.md §6, Q4).

| # | Decision |
|---|---|
| D11 | **Generic foods come from open tables bundled into the app as an offline asset. No API key and no backend.** **USDA FoodData Central** (SR Legacy, Foundation, FNDDS survey; public domain; household portions such as "1 medium" or "1 slice") and **BLS 4.0** (Germany, Max Rubner-Institut, CC BY 4.0, ~7,100 foods, close to Latvian staples: rye bread, quark, kefir, herring, sauerkraut). Every row keeps its source. Packaged products keep coming from Open Food Facts live, as upstream does. `fork/tools/build_food_db.py` builds the asset. No more tables: dishes come from recipes (D12), and their ingredients are covered by these two. Fineli and Livsmedelsverket are dropped (2026-10-18). Not usable: NEVO (unchanged copies only) and NutriData (no stated licence). |
| D12 | **Dishes come from recipes, and the AI writes the recipe.** No open recipe database covers Latvian or Georgian food with gram amounts (researched 2026-10-18; the large scraped datasets are research-only or of doubtful licence). So: (1) for a dish the tables lack, the model returns its ingredients with grams, naming the nearest generic ingredient where a local one is missing (grey peas → dried split peas, sulguni → brined mozzarella-type cheese); (2) the ingredients are matched in the tables (D11), so the numbers stay grounded; (3) the breakdown can be saved as a recipe with upstream's recipe builder, which makes the dish instant and offline next time and lets the user adjust it to how they cook it; (4) four CC0 Latvian recipes with gram amounts (grey peas with bacon, pelmeni, sklandu rauši, layered rye-bread dessert; *The Cuisine of Latvia*, Latvian Institute, data.gov.lv) ship as starter recipes. Agreed 2026-10-18. |
