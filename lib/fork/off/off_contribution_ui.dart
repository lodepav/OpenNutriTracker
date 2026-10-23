import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/barcode_validator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/off/off_contribution.dart';

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
/// to Open Food Facts as the user, once they saw what goes out. Only what
/// OFF lacks is sent. Returns once the user decided; the upload carries on
/// and reports through the app's snackbar, with a retry.
Future<void> offerOffUpload(
  BuildContext context,
  MealEntity meal, {
  OffAccountStore? store,
  OffContributionClient? client,
}) async {
  final upload = OffUpload.fromMeal(meal);
  if (!isBarcodeFormatValid(upload.barcode) || upload.isEmpty) return;
  final account = await (store ?? OffAccountStore()).load();
  if (!account.isReady || !context.mounted) return;
  final send = await showDialog<bool>(
    context: context,
    builder: (_) => _PreviewDialog(upload: upload, account: account),
  );
  if (send != true || !context.mounted) return;
  unawaited(
    _send(
      ScaffoldMessenger.of(context),
      account,
      upload,
      client ?? OffContributionClient(locator<http.Client>()),
    ),
  );
}

Future<void> _send(
  ScaffoldMessengerState messenger,
  OffAccount account,
  OffUpload upload,
  OffContributionClient client,
) async {
  String message;
  SnackBarAction? retry;
  try {
    final missing = upload.without(
      await client.product(account, upload.barcode),
    );
    if (missing.isEmpty) {
      message = 'Open Food Facts already has this product';
    } else {
      await client.upload(account, missing);
      message = 'Added to Open Food Facts. Thank you!';
    }
  } on OffContributionException catch (error) {
    message = switch (error.failure) {
      OffFailure.offline => 'Open Food Facts could not be reached',
      OffFailure.rejected =>
        'Open Food Facts refused it. Check your account in Settings',
      OffFailure.busy => 'Open Food Facts is busy. Try again later',
    };
    retry = SnackBarAction(
      label: 'Retry',
      onPressed: () => unawaited(_send(messenger, account, upload, client)),
    );
  }
  messenger.showSnackBar(SnackBar(content: Text(message), action: retry));
}

class _PreviewDialog extends StatelessWidget {
  final OffUpload upload;
  final OffAccount account;

  const _PreviewDialog({required this.upload, required this.account});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
              'As ${account.userId}, to ${account.host}, for barcode '
              '${upload.barcode}. Only what Open Food Facts does not have yet '
              'is sent; nothing there is overwritten.',
            ),
            const SizedBox(height: 8),
            if (upload.name case final name?) row('Name', name),
            if (upload.brand case final brand?) row('Brand', brand),
            for (final MapEntry(key: nutrient, value: (value, unit))
                in upload.nutrients.entries)
              row(
                '${_nutrientLabels[nutrient] ?? nutrient} per 100 g',
                '${formatOffValue(value)} $unit',
              ),
            const SizedBox(height: 12),
            Text(
              'Send only values printed on the package. Open Food Facts '
              'publishes them under the Open Database License.',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const Key('fork-off-send'),
          onPressed: () => Navigator.of(context).pop(true),
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
  Widget build(BuildContext context) => ListTile(
    key: const Key('fork-off-account'),
    leading: const Icon(Icons.volunteer_activism_outlined),
    title: const Text('Open Food Facts account'),
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
