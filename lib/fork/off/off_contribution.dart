import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/app_const.dart';
import 'package:opennutritracker/core/utils/secure_app_storage_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// The user's own Open Food Facts account (backlog: OFF contributions).
/// Kept in the platform keychain only: the password is a secret, and none
/// of it belongs in a backup. Ported after review from theoleuthardt's
/// `off_contribution_settings.dart`.
class OffAccount {
  final bool enabled;

  /// The Open Food Facts user name (not the e-mail address).
  final String userId;
  final String password;

  /// Sends to `world.openfoodfacts.net` instead of the real database, until
  /// the upload has been tried there.
  final bool useTestServer;

  const OffAccount({
    this.enabled = false,
    this.userId = '',
    this.password = '',
    this.useTestServer = true,
  });

  bool get isReady => enabled && userId.isNotEmpty && password.isNotEmpty;

  String get host =>
      useTestServer ? 'world.openfoodfacts.net' : 'world.openfoodfacts.org';

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'userId': userId,
    'password': password,
    'useTestServer': useTestServer,
  };

  factory OffAccount.fromJson(Map<String, dynamic> json) => OffAccount(
    enabled: json['enabled'] as bool? ?? false,
    userId: json['userId'] as String? ?? '',
    password: json['password'] as String? ?? '',
    useTestServer: json['useTestServer'] as bool? ?? true,
  );
}

class OffAccountStore {
  static const _key = 'ForkOffAccount';

  final FlutterSecureStorage _storage;

  OffAccountStore([FlutterSecureStorage? storage])
    : _storage = storage ?? SecureAppStorageProvider.secureAppStorage;

  Future<OffAccount> load() async {
    try {
      final json = jsonDecode(await _storage.read(key: _key) ?? '{}');
      return json is Map<String, dynamic>
          ? OffAccount.fromJson(json)
          : const OffAccount();
    } on Exception {
      // Unreadable, or no keychain (widget tests): no account.
      return const OffAccount();
    }
  }

  Future<void> save(OffAccount account) =>
      _storage.write(key: _key, value: jsonEncode(account.toJson()));
}

/// What a custom food would add to Open Food Facts, per 100 g, with each
/// value's unit and salt instead of the app's sodium (salt = sodium × 2.5).
class OffUpload {
  final String barcode;
  final String? name;
  final String? brand;

  /// OFF nutrient name → (value, unit), the values the food has.
  final Map<String, (double, String)> nutrients;

  const OffUpload({
    required this.barcode,
    this.name,
    this.brand,
    this.nutrients = const {},
  });

  factory OffUpload.fromMeal(MealEntity meal) {
    final n = meal.nutriments;
    final sodium = n.sodium100;
    final values = <String, (double?, String)>{
      'energy-kcal': (n.energyKcal100, 'kcal'),
      'fat': (n.fat100, 'g'),
      'saturated-fat': (n.saturatedFat100, 'g'),
      'carbohydrates': (n.carbohydrates100, 'g'),
      'sugars': (n.sugars100, 'g'),
      'fiber': (n.fiber100, 'g'),
      'proteins': (n.proteins100, 'g'),
      'salt': (sodium == null ? null : sodium * 2.5 / 1000, 'g'),
      'calcium': (n.calcium100, 'mg'),
      'iron': (n.iron100, 'mg'),
      'potassium': (n.potassium100, 'mg'),
      'magnesium': (n.magnesium100, 'mg'),
      'vitamin-d': (n.vitaminD100, 'µg'),
      'vitamin-b12': (n.vitaminB12100, 'µg'),
    };
    String? text(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    return OffUpload(
      barcode: meal.code ?? '',
      name: text(meal.name),
      brand: text(meal.brands),
      nutrients: {
        for (final MapEntry(:key, value: (value, unit)) in values.entries)
          if (value != null) key: (value, unit),
      },
    );
  }

  bool get isEmpty => name == null && brand == null && nutrients.isEmpty;

  /// Only what Open Food Facts lacks: the name and the brand each when it
  /// has none, the nutrients only when it has no nutrient at all, so
  /// nothing someone else entered is overwritten.
  OffUpload without(OffProduct there) => OffUpload(
    barcode: barcode,
    name: there.hasName ? null : name,
    brand: there.hasBrand ? null : brand,
    nutrients: there.hasNutrients ? const {} : nutrients,
  );

  /// The fields of OFF's product write form.
  Map<String, String> get fields => {
    'code': barcode,
    'product_name': ?name,
    'brands': ?brand,
    if (nutrients.isNotEmpty) 'nutrition_data_per': '100g',
    for (final MapEntry(key: nutrient, value: (value, unit))
        in nutrients.entries) ...{
      'nutriment_$nutrient': formatOffValue(value),
      'nutriment_${nutrient}_unit': unit,
    },
  };
}

String formatOffValue(double value) {
  final rounded = double.parse(value.toStringAsFixed(2));
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}

/// What Open Food Facts already holds for a barcode.
class OffProduct {
  final bool hasName;
  final bool hasBrand;
  final bool hasNutrients;

  const OffProduct({
    this.hasName = false,
    this.hasBrand = false,
    this.hasNutrients = false,
  });
}

enum OffFailure { offline, rejected, busy }

class OffContributionException implements Exception {
  final OffFailure failure;

  const OffContributionException(this.failure);

  @override
  String toString() => 'OffContributionException($failure)';
}

/// Writes to Open Food Facts through its product write form
/// (`/cgi/product_jqm2.pl`) as the user's own account. The test server sits
/// behind the basic auth `off:off` that Open Food Facts publishes for it.
class OffContributionClient {
  static const _timeout = Duration(seconds: 20);
  static const userAgentName = 'OpenBite';
  static const sourceUrl = 'https://github.com/lodepav/OpenNutriTracker';

  final http.Client _client;
  final Future<String> Function() _version;

  OffContributionClient(
    this._client, {
    Future<String> Function() version = AppConst.getVersionNumber,
  }) : _version = version;

  Future<OffProduct> product(OffAccount account, String barcode) async {
    final response = await _send(
      http.Request(
        'GET',
        Uri.https(account.host, '/api/v2/product/$barcode', {
          'fields': 'product_name,brands,nutriments',
        }),
      ),
      account,
    );
    if (response.statusCode == 404) return const OffProduct();
    _throwOnServerError(response);
    final body = _decode(response);
    final product = body is Map<String, dynamic> ? body['product'] : null;
    if (product is! Map<String, dynamic>) return const OffProduct();
    bool present(Object? value) => value is String && value.trim().isNotEmpty;
    final nutriments = product['nutriments'];
    return OffProduct(
      hasName: present(product['product_name']),
      hasBrand: present(product['brands']),
      hasNutrients:
          nutriments is Map &&
          nutriments.keys.any((key) => '$key'.endsWith('_100g')),
    );
  }

  Future<void> upload(OffAccount account, OffUpload upload) async {
    final request =
        http.Request('POST', Uri.https(account.host, '/cgi/product_jqm2.pl'))
          ..bodyFields = {
            'user_id': account.userId,
            'password': account.password,
            ...upload.fields,
          };
    final response = await _send(request, account);
    _throwOnServerError(response);
    final body = _decode(response);
    if (body is! Map<String, dynamic> || body['status'] != 1) {
      throw const OffContributionException(OffFailure.rejected);
    }
  }

  Future<http.Response> _send(
    http.BaseRequest request,
    OffAccount account,
  ) async {
    // OFF asks every app for its name, version and a way to reach its author.
    request.headers['User-Agent'] =
        '$userAgentName - ${AppConst.getPlatformName()} - Version '
        '${await _version()} - $sourceUrl';
    if (account.useTestServer) {
      request.headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('off:off'))}';
    }
    try {
      return await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_timeout);
    } on Exception {
      throw const OffContributionException(OffFailure.offline);
    }
  }

  Object? _decode(http.Response response) {
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return null;
    }
  }

  void _throwOnServerError(http.Response response) {
    final status = response.statusCode;
    if (status == 429 || status >= 500) {
      throw const OffContributionException(OffFailure.busy);
    }
    if (status != 200) {
      throw const OffContributionException(OffFailure.rejected);
    }
  }
}
