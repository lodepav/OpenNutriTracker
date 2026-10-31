# Plan — MacroFactor features on OpenNutriTracker

Started 2026-10-17. Decisions in [DECISIONS.md](DECISIONS.md) win over this file.

Sections 0 to 4b, the finished phases, are in [archive/PLAN-phases.md](archive/PLAN-phases.md).

## 5. Backlog (after phases 1–3)

Not built anywhere yet:

- *Done 2026-10-24 (D19):* "Count every kg as 7,700 kcal" in Expenditure and check-ins, off
  by default. Off, a kg follows body composition (Forbes via Hall, about 6,200 kcal at a typical
  build, as part of a change is lean tissue); on, the same pace takes a larger deficit or
  surplus. The journey's drift against MacroFactor's targets fell from 7.0 to 4.3 kg.

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
  - The release key and its pin are Go Hevier's (D16): `~/.config/hevier/apk-cert.txt`.
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
