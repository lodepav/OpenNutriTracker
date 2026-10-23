import 'package:flutter/material.dart';
// [fork] S35 brand: OpenBite's logo instead of upstream's
// import 'package:opennutritracker/core/presentation/widgets/dynamic_ont_logo.dart';
import 'package:opennutritracker/fork/brand/openbite_logo.dart';
// [/fork]
import 'package:opennutritracker/generated/l10n.dart';

class AppBannerVersion extends StatelessWidget {
  final String versionNumber;

  const AppBannerVersion({super.key, required this.versionNumber});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 70, child: OpenBiteLogo() /* [fork] S35 */),
        Text(
          S.of(context).appTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
        ),
        Text(
          S.of(context).appVersionName(versionNumber),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
        ),
      ],
    );
  }
}
