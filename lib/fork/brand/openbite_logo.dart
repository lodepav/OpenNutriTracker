import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// OpenBite's logo (seam S35): the launcher icon's diary page on its disc,
/// with the bite out of it. Drawn by `fork/tools/launcher_icon.py`.
class OpenBiteLogo extends StatelessWidget {
  static const pageAsset = 'assets/fork/openbite_page.svg';
  static const biteAsset = 'assets/fork/openbite_bite.svg';

  /// Where the bite's centre sits on the 108-unit canvas (80, 55 scaled by
  /// 0.8 about the centre, then moved right by 1), for scaling it in place.
  static const _biteCentre = Alignment(75.8 / 54 - 1, 54.8 / 54 - 1);

  final double? size;

  /// The splash's progress, 0 to 1: the bite is taken quickly a fifth of
  /// the way in. Null shows it taken.
  final Animation<double>? bite;

  const OpenBiteLogo({super.key, this.size, this.bite});

  @override
  Widget build(BuildContext context) {
    const biteArt = SvgPicture(SvgAssetLoader(biteAsset));
    return SizedBox(
      width: size,
      height: size,
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SvgPicture.asset(pageAsset),
            if (bite case final bite?)
              ScaleTransition(
                scale: CurvedAnimation(
                  parent: bite,
                  curve: const Interval(0.2, 0.55, curve: Curves.easeOutBack),
                ),
                alignment: _biteCentre,
                child: biteArt,
              )
            else
              biteArt,
          ],
        ),
      ),
    );
  }
}
