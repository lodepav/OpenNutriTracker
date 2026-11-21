/// A macro goal's grams on onboarding's overview (seam S333), rounded as
/// Home rounds them: upstream truncated, so 322.8 g read 322 there and 323
/// on Home right after.
String overviewGrams(double? grams) => grams?.round().toString() ?? '?';
