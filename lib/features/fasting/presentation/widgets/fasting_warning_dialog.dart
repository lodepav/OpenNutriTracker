// [fork] S596: the links are buttons now
// import 'package:flutter/gestures.dart';
// [/fork]
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/core/utils/safe_url_launcher.dart';

/// One-time content warning shown before the fasting timer becomes usable.
///
/// Returns `true` when the user accepts and `false` (or null on barrier
/// dismissal — though the dialog is non-dismissible by default) when they
/// decline. The caller is responsible for routing back when declined and for
/// persisting the acknowledgement when accepted.
class FastingWarningDialog extends StatelessWidget {
  static const _beatUrl = 'https://www.beateatingdisorders.org.uk/';
  static const _nedaUrl = 'https://www.nationaleatingdisorders.org/';

  const FastingWarningDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: Dimens.shapeL,
      title: Text(l10n.fastingWarningTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.fastingWarningBody, style: textTheme.bodyMedium),
            const SizedBox(height: 16),
            // [fork] S596 fasting-warning-links: 48 dp link targets, and a
            // decline that says the page asks again
            // Text.rich(
            //   TextSpan(
            //     children: [
            //       TextSpan(
            //         text: l10n.fastingLinkBeat,
            //         style: textTheme.bodyMedium?.copyWith(
            //           color: colors.primary,
            //           decoration: TextDecoration.underline,
            //         ),
            //         recognizer: TapGestureRecognizer()
            //           ..onTap = () => _open(_beatUrl),
            //       ),
            //     ],
            //   ),
            // ),
            // const SizedBox(height: 4),
            // Text.rich(
            //   TextSpan(
            //     children: [
            //       TextSpan(
            //         text: l10n.fastingLinkNeda,
            //         style: textTheme.bodyMedium?.copyWith(
            //           color: colors.primary,
            //           decoration: TextDecoration.underline,
            //         ),
            //         recognizer: TapGestureRecognizer()
            //           ..onTap = () => _open(_nedaUrl),
            //       ),
            //     ],
            //   ),
            // ),
            for (final (label, url) in [
              (l10n.fastingLinkBeat, _beatUrl),
              (l10n.fastingLinkNeda, _nedaUrl),
            ])
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () => _open(url),
                child: Semantics(
                  link: true,
                  child: Text(
                    label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            // [/fork]
          ],
        ),
      ),
      actions: [
        Semantics(
          identifier: 'fasting-warning-decline',
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            // [fork] S596: it only closes the page, which asks again
            // child: Text(l10n.fastingWarningDecline),
            child: const Text('Not now'),
            // [/fork]
          ),
        ),
        Semantics(
          identifier: 'fasting-warning-accept',
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.fastingWarningAccept),
          ),
        ),
      ],
    );
  }

  Future<void> _open(String url) => tryLaunchExternalUrl(url);
}
