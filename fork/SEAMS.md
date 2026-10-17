# Seams — every place the fork edits an upstream file

The fork's code lives in `fork/`, `lib/fork/` and `test/fork/`. Upstream files are edited
**only** at the seams below. Each seam is wrapped in markers so `git grep -n "\[fork\]"`
finds it:

```dart
// [fork] <seam id>: <one line on why>
...fork lines...
// [/fork]
```

(Gradle and XML use their own comment syntax.)

Add the row in the same commit that adds the seam. A seam that is no longer needed (for example
because upstream merged the feature) gets removed, and so does its row.

| Id | File | What the seam does | Status |
|---|---|---|---|
| S1 | `lib/core/utils/locator.dart` | Registers `LocalFoodDataSource` (`lib/fork/food/`) as the `SpFoodDataSource`, so search and AI matching use the bundled tables (D11). Two blocks: the import and the registration. | active |
| S2 | `pubspec.yaml` | Bundles `assets/fork/` (the food table from `fork/tools/build_food_db.py`). | active |
