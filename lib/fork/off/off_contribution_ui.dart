import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/barcode_validator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/off/off_contribution.dart';
import 'package:opennutritracker/fork/display/settings_tile.dart';

const _nutrientLabels = {
  'energy-kcal': 'Energy',
  'fat': 'Fat',
  'saturated-fat': 'Saturated fat',
  'carbohydrates': 'Carbohydrates',
  'sugars': 'Sugars',
  'fiber': 'Fiber',
  'proteins': 'Protein',
  'salt': 'Salt',
  'calcium': 'Calcium',
  'iron': 'Iron',
  'potassium': 'Potassium',
  'magnesium': 'Magnesium',
  'vitamin-d': 'Vitamin D',
  'vitamin-b12': 'Vitamin B12',
};

/// After a custom food with a barcode is saved (seam S33): offers to add it
/// to Open Food Facts as the user. Asks Open Food Facts what it has first,
/// then shows only what it lacks, editable, with the label photo when the
/// form was filled from one (S29), and sends nothing until the user does.
/// Returns once the user decided; the upload carries on and reports through
/// the app's snackbar, with a retry.
Future<void> offerOffUpload(
  BuildContext context,
  MealEntity meal, {
  Uint8List? labelPhoto,
  OffAccountStore? store,
  OffContributionClient? client,
}) async {
  // No client to send with: the app's is missing in widget tests.
  if (client == null && !locator.isRegistered<http.Client>()) return;
  final full = OffUpload.fromMeal(meal);
  if (!isBarcodeFormatValid(full.barcode) || full.isEmpty) return;
  final account = await (store ?? OffAccountStore()).load();
  if (!account.isReady || !context.mounted) return;
  final offClient = client ?? OffContributionClient(locator<http.Client>());
  final messenger = ScaffoldMessenger.of(context);

  final OffProduct there;
  try {
    there = await _whileChecking(
      context,
      offClient.product(account, full.barcode),
    );
  } on OffContributionException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(_failureText(error))));
    return;
  }
  final missing = full.without(there);
  final photo = there.hasNutritionPhoto ? null : labelPhoto;
  if (missing.isEmpty && photo == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Open Food Facts already has this product')),
    );
    return;
  }
  if (!context.mounted) return;
  final review = await showDialog<_Review>(
    context: context,
    builder: (_) =>
        _ReviewDialog(upload: missing, account: account, labelPhoto: photo),
  );
  if (review == null || !context.mounted) return;
  final language = Localizations.localeOf(context).languageCode;
  unawaited(_send(messenger, account, review, offClient, language));
}

/// Runs [check] behind a small "Checking" dialog.
Future<T> _whileChecking<T>(BuildContext context, Future<T> check) async {
  final navigator = Navigator.of(context);
  var open = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Checking Open Food Facts…')),
          ],
        ),
      ),
    ).whenComplete(() => open = false),
  );
  try {
    return await check;
  } finally {
    if (open) navigator.pop();
  }
}

String _failureText(OffContributionException error) => switch (error.failure) {
  OffFailure.offline => 'Open Food Facts could not be reached',
  OffFailure.rejected =>
    'Open Food Facts refused it. Check your account in Settings',
  OffFailure.busy => 'Open Food Facts is busy. Try again later',
};

/// What the user confirmed: the values, as edited, and the photo if kept.
class _Review {
  final OffUpload upload;
  final Uint8List? photo;

  const _Review(this.upload, this.photo);
}

Future<void> _send(
  ScaffoldMessengerState messenger,
  OffAccount account,
  _Review review,
  OffContributionClient client,
  String language,
) async {
  String message;
  SnackBarAction? retry;
  try {
    if (!review.upload.isEmpty) {
      await client.upload(account, review.upload);
    }
    if (review.photo case final photo?) {
      await client.uploadNutritionPhoto(
        account,
        review.upload.barcode,
        photo,
        language: language,
      );
    }
    message = 'Added to Open Food Facts. Thank you!';
  } on OffContributionException catch (error) {
    message = _failureText(error);
    retry = SnackBarAction(
      label: 'Retry',
      onPressed: () =>
          unawaited(_send(messenger, account, review, client, language)),
    );
  }
  messenger.showSnackBar(SnackBar(content: Text(message), action: retry));
}

class _ReviewDialog extends StatefulWidget {
  final OffUpload upload;
  final OffAccount account;
  final Uint8List? labelPhoto;

  const _ReviewDialog({
    required this.upload,
    required this.account,
    this.labelPhoto,
  });

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late final _name = TextEditingController(text: widget.upload.name);
  late final _brand = TextEditingController(text: widget.upload.brand);
  late final _values = {
    for (final MapEntry(key: nutrient, value: (value, _))
        in widget.upload.nutrients.entries)
      nutrient: TextEditingController(text: formatOffValue(value)),
  };
  late bool _withPhoto = widget.labelPhoto != null;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    for (final controller in _values.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The values as the fields hold them; a cleared field is left out.
  _Review get _review {
    String? text(TextEditingController controller) =>
        controller.text.trim().isEmpty ? null : controller.text.trim();
    final nutrients = <String, (double, String)>{};
    for (final MapEntry(key: nutrient, value: controller) in _values.entries) {
      final value = double.tryParse(controller.text.replaceAll(',', '.'));
      if (value != null && value.isFinite && value >= 0) {
        nutrients[nutrient] = (value, widget.upload.nutrients[nutrient]!.$2);
      }
    }
    return _Review(
      widget.upload.copyWith(
        name: () => widget.upload.name == null ? null : text(_name),
        brand: () => widget.upload.brand == null ? null : text(_brand),
        nutrients: nutrients,
      ),
      _withPhoto ? widget.labelPhoto : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final upload = widget.upload;
    Widget field(
      TextEditingController controller,
      String label, {
      String? unit,
      Key? key,
    }) => TextField(
      key: key,
      controller: controller,
      keyboardType: unit == null
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        isDense: true,
      ),
    );
    return AlertDialog(
      title: const Text('Add to Open Food Facts?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'As ${widget.account.userId}, to ${widget.account.host}, for '
              'barcode ${upload.barcode}. This is what Open Food Facts does '
              'not have yet; check it against the package and correct it. '
              'Clear a value to leave it out.',
            ),
            if (upload.name != null)
              field(_name, 'Name', key: const Key('fork-off-name')),
            if (upload.brand != null) field(_brand, 'Brand'),
            if (_values.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Per 100 g', style: textTheme.titleSmall),
            ],
            for (final MapEntry(key: nutrient, value: controller)
                in _values.entries)
              field(
                controller,
                _nutrientLabels[nutrient] ?? nutrient,
                unit: upload.nutrients[nutrient]!.$2,
                key: Key('fork-off-$nutrient'),
              ),
            if (widget.labelPhoto case final photo?) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const Key('fork-off-photo'),
                contentPadding: EdgeInsets.zero,
                value: _withPhoto,
                onChanged: (on) => setState(() => _withPhoto = on ?? false),
                title: const Text('Add the label photo'),
                subtitle: const Text('As the nutrition table picture'),
                secondary: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    photo,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Send only what is printed on the package. Open Food Facts '
              'publishes it under the Open Database License.',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const Key('fork-off-send'),
          onPressed: () {
            final review = _review;
            if (review.upload.isEmpty && review.photo == null) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pop(review);
            }
          },
          child: const Text('Send'),
        ),
      ],
    );
  }
}

/// Settings → "Open Food Facts account" (seam S32).
class OffAccountTile extends StatefulWidget {
  final OffAccountStore? store;

  const OffAccountTile({super.key, this.store});

  @override
  State<OffAccountTile> createState() => _OffAccountTileState();
}

class _OffAccountTileState extends State<OffAccountTile> {
  late final _store = widget.store ?? OffAccountStore();
  OffAccount? _account;

  @override
  void initState() {
    super.initState();
    _store.load().then((account) {
      if (mounted) setState(() => _account = account);
    });
  }

  String get _summary {
    final account = _account;
    if (account == null || !account.isReady) {
      return 'Off. Add foods you create with a barcode to Open Food Facts';
    }
    return 'On, as ${account.userId}'
        '${account.useTestServer ? ', test server' : ''}';
  }

  Future<void> _edit() async {
    final edited = await showDialog<OffAccount>(
      context: context,
      builder: (_) => _AccountDialog(account: _account ?? const OffAccount()),
    );
    if (edited == null) return;
    await _store.save(edited);
    if (mounted) setState(() => _account = edited);
  }

  @override
  Widget build(BuildContext context) => ForkSettingsTile(
    key: const Key('fork-off-account'),
    icon: Icons.volunteer_activism_rounded,
    title: 'Open Food Facts account',
    subtitle: Text(_summary),
    onTap: _account == null ? null : _edit,
  );
}

class _AccountDialog extends StatefulWidget {
  final OffAccount account;

  const _AccountDialog({required this.account});

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final _user = TextEditingController(text: widget.account.userId);
  late final _password = TextEditingController(text: widget.account.password);
  late bool _enabled = widget.account.enabled;
  late bool _testServer = widget.account.useTestServer;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Open Food Facts account'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Offer to add my foods'),
            subtitle: const Text(
              'After you save a food with a barcode, you see what would be '
              'sent and decide.',
            ),
            value: _enabled,
            onChanged: (on) => setState(() => _enabled = on),
          ),
          TextField(
            key: const Key('fork-off-user'),
            controller: _user,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'User name (not the e-mail)',
            ),
          ),
          TextField(
            key: const Key('fork-off-password'),
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use the test server'),
            subtitle: const Text(
              'world.openfoodfacts.net: try it out without changing the '
              'real database.',
            ),
            value: _testServer,
            onChanged: (on) => setState(() => _testServer = on),
          ),
          Text(
            'Kept on this phone only, in its secure storage, and never in a '
            'backup.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('fork-off-save'),
        onPressed: () => Navigator.of(context).pop(
          OffAccount(
            enabled: _enabled,
            userId: _user.text.trim(),
            password: _password.text,
            useTestServer: _testServer,
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}
