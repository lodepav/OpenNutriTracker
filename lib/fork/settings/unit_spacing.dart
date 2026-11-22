/// "1000mg" as "1000 mg" and "20g" as "20 g" (seam S586, G6-12): the
/// nutrient editor's helper text wrote units against the number, where its
/// fields and the rest of the app put a space.
String spaceUnits(String text) => text.replaceAllMapped(
  RegExp(r'(\d)(mg|g)\b'),
  (m) => '${m[1]} ${m[2]}',
);
