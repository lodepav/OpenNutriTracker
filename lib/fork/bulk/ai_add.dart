import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';

/// AI add (canvas "AI add", B for both): "Add several items" named for
/// what it does while AI meal assistance is on — a wide "Log with AI" on
/// the + sheet, a "Log with AI" floating button on food search. With the
/// feature off neither shows; search keeps its list icon. The screen they
/// open still decides whether a photo can be read.
Future<bool> aiAddEnabled() => locator.isRegistered<AiCredentialStorage>()
    ? locator<AiCredentialStorage>().isEnabled()
    // not registered in the many upstream tests that pump these screens
    : Future.value(false);

/// One name for AI add's buttons and the screen they open.
const aiAddLabel = 'Log with AI';

/// The sparkle that marks AI in the add flow.
const aiAddIcon = Icons.auto_awesome_rounded;

/// Food search's "AI add".
class AiAddFab extends StatelessWidget {
  final VoidCallback onPressed;

  const AiAddFab({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: 'add-meal-ai-add',
    child: FloatingActionButton.extended(
      onPressed: onPressed,
      icon: const Icon(aiAddIcon),
      label: const Text(aiAddLabel),
    ),
  );
}

/// The + sheet's "Log with AI", above the tiles.
class LogWithAiButton extends StatelessWidget {
  final VoidCallback onPressed;

  const LogWithAiButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      identifier: 'add-item-ai',
      button: true,
      child: Material(
        color: scheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: Dimens.borderRadiusM,
          side: BorderSide(color: scheme.primary, width: 1.5),
        ),
        child: InkWell(
          borderRadius: Dimens.borderRadiusM,
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Dimens.spacing12,
                vertical: Dimens.spacing8,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    child: const Icon(aiAddIcon),
                  ),
                  const SizedBox(width: Dimens.spacing12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          aiAddLabel,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Type what you ate, or take a photo',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
