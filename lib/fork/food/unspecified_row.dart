import 'package:opennutritracker/features/add_meal/util/soft_text_score.dart';

/// How many times [name] says it leaves something unspecified: USDA's
/// "NFS" (not further specified) and "NS as to ..." (part, cooking method,
/// skin). Among rows that tie on a family name the most unspecified one is
/// the everyday form: "chicken" logged "Chicken, back", the shortest of 254
/// rows titled "Chicken", over "Chicken, NS as to part and cooking method,
/// NS as to skin eaten"; "bacon" logged "Bacon, for use on a sandwich" over
/// "Bacon, NS as to type of meat, cooked". Upstream declined reading these
/// markers (`_sorted` in `resolver_relevance.dart`); the fork's table is
/// all USDA-named, where most families with such a row ended on an odd one.
///
/// Zero unless [query] is one word, the family alone: a longer name has
/// chosen within it, and "pork bacon" from a recipe's breakdown wants the
/// raw "Pork, cured, bacon, unprepared", not "Pork bacon, NS as to fresh,
/// smoked or cured, cooked".
int unspecifiedMarks(String? name, String query) =>
    tokenize(query).length == 1 && _unspecifiedFirst.hasMatch(name ?? '')
    ? _unspecified.allMatches(name!).length
    : 0;

/// The row is the family's unspecified member when the first thing said
/// after the title is: "Chicken, NS as to part", "Bread, NS as to major
/// flour", "Potato, NFS". Not a marker further on, about a detail of a
/// specific form ("Carrots, fresh, cooked, fat added, NS as to fat type"),
/// nor "NS as to form" (fresh, frozen or canned), which goes on to name a
/// cooked form where "carrots" or "tomato" eaten as they come is raw.
final _unspecifiedFirst = RegExp(r'^[^,]*,\s*(NFS|NS as to(?! form\b))\b');
final _unspecified = RegExp(r'\b(NFS|NS as to)\b');
