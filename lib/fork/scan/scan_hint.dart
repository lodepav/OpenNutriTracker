import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/scan/scanner_error.dart';

/// The bar over a QR import scanner's camera feed: what to point it at, and
/// the paste dialog as the way around the camera.
class ScanHint extends StatelessWidget {
  final String text;
  final VoidCallback onPaste;

  const ScanHint({super.key, required this.text, required this.onPaste});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Dimens.spacing16),
          // Opaque, so the text reads over any camera picture.
          child: Material(
            color: colors.surface,
            shape: Dimens.shapeL,
            child: Padding(
              padding: const EdgeInsets.all(Dimens.spacing16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: colors.onSurface),
                  ),
                  const SizedBox(height: Dimens.spacing12),
                  PasteCodeButton(onPaste: onPaste),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
