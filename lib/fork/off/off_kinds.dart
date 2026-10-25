import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/util/food_emoji_resolver.dart';

/// What kind of food an Open Food Facts product is, as an emoji for its
/// row (seam S117): a product's front photo is often a blurry packshot
/// that says less at 32 dp than an icon does. The kind comes from the
/// product's categories ("en:dairies, …, en:fruit-yogurts"), learnt when
/// the product is searched or scanned and kept by barcode, so a food
/// logged from it shows it too. A product never seen with categories
/// (logged before, or with none) gets a guess from its name.
///
/// Kept in one box for every profile: what a barcode is does not depend
/// on whose diary it is in.
class OffKinds {
  static const boxName = 'OffKindsBox';
  static final _log = Logger('OffKinds');

  /// Kinds by barcode; rows listen, so a kind learnt or loaded late shows.
  static final kinds = ValueNotifier<Map<String, String>>(const {});

  @visibleForTesting
  static Future<Box<dynamic>> Function() box = () =>
      locator<HiveDBProvider>().openScopedBox<dynamic>(boxName, '');

  /// Run at start-up (seam S6): reads the kinds learnt before.
  static Future<void> start() async {
    try {
      final stored = (await box()).toMap();
      kinds.value = {
        for (final MapEntry(:key, :value) in stored.entries)
          if (key is String && value is String) key: value,
      };
    } catch (error, stack) {
      _log.warning('Could not read the food kinds', error, stack);
    }
  }

  /// Learns the kind of each product with a barcode and categories that
  /// say one; failures are logged, as the products show either way.
  static Future<void> learn(
    Iterable<({String? code, List<String>? categories})> products,
  ) async {
    final learnt = <String, String>{};
    for (final product in products) {
      final code = product.code;
      final kind = fromCategories(product.categories);
      if (code == null || code.isEmpty || kind == null) continue;
      if (kinds.value[code] != kind) learnt[code] = kind;
    }
    if (learnt.isEmpty) return;
    kinds.value = {...kinds.value, ...learnt};
    try {
      await (await box()).putAll(learnt);
    } catch (error, stack) {
      _log.warning('Could not keep the food kinds', error, stack);
    }
  }

  /// The emoji for [meal]'s row: an Open Food Facts product's kind, a
  /// base food's by its name (as upstream has it), null for anything else
  /// or when nothing says.
  static String? emojiFor(MealEntity meal) => switch (meal.source) {
    MealSourceEntity.off => kinds.value[meal.code] ?? fromName(meal.name),
    MealSourceEntity.fdc => resolveFoodEmoji(meal.name),
    _ => null,
  };

  /// Whether [meal]'s row shows its photo: not an Open Food Facts
  /// product's, which shows its kind.
  static bool showsPhoto(MealEntity meal) =>
      meal.source != MealSourceEntity.off;

  /// The most specific category that names a kind: OFF lists them from the
  /// broadest to the narrowest. A tag is tried whole ("ice creams"), then
  /// without its leading words ("fruit yogurts" → "yogurts"); English tags
  /// only, as the nouns are.
  @visibleForTesting
  static String? fromCategories(List<String>? tags) {
    if (tags == null) return null;
    for (final tag in tags.reversed) {
      if (!tag.startsWith('en:')) continue;
      var words = tag.substring(3).split('-');
      // "desserts with fruits" are desserts.
      final with_ = words.indexOf('with');
      if (with_ > 0) words = words.sublist(0, with_);
      for (var i = 0; i < words.length; i++) {
        final noun = words.sublist(i).join(' ');
        final kind = resolveFoodEmoji(noun) ?? _broad[noun];
        if (kind != null) return kind;
      }
    }
    return null;
  }

  /// A guess from a product's name: its last words that name a food
  /// ("Greek yogurt" → "yogurt"). A brand alone says nothing.
  @visibleForTesting
  static String? fromName(String? name) {
    if (name == null) return null;
    final words = name
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    for (var i = 0; i < words.length; i++) {
      final kind = resolveFoodEmoji(words.sublist(i).join(' '));
      if (kind != null) return kind;
    }
    return null;
  }

  /// OFF's broad categories that no food noun names.
  static const _broad = {
    'dairies': '🥛',
    'fermented milk products': '🥛',
    'beverages': '🥤',
    'sodas': '🥤',
    'carbonated drinks': '🥤',
    'waters': '💧',
    'breakfast cereals': '🥣',
    'cereals and their products': '🌾',
    'biscuits and cakes': '🍪',
    'confectioneries': '🍬',
    'sweets': '🍬',
    'sweet snacks': '🍬',
    'salty snacks': '🥨',
    'crisps': '🍟',
    'meats': '🥩',
    'poultries': '🍗',
    'fishes': '🐟',
    'seafood': '🐟',
    'fruits': '🍎',
    'vegetables': '🥦',
    'legumes': '🫘',
    'nuts': '🥜',
    'sauces': '🥫',
    'condiments': '🧂',
    'canned foods': '🥫',
    'meals': '🍲',
    'soups': '🍲',
    'pizzas': '🍕',
    'sandwiches': '🥪',
    'desserts': '🍮',
    'frozen desserts': '🍦',
    'plant based spreads': '🥜',
  };
}
