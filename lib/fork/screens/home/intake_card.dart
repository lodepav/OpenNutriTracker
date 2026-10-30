// Fork-owned copy of lib/core/presentation/widgets/intake_card.dart
// (D23); upstream's later changes to it are ported by hand:
// fork/tools/upstream-copies.sh.
import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/diary_sort_type.dart';
import 'package:opennutritracker/fork/units/amount_text.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/features/add_meal/util/food_emoji_resolver.dart';
import 'package:opennutritracker/fork/timeline/timeline.dart';
import 'package:opennutritracker/fork/history/food_icon.dart';
import 'package:opennutritracker/fork/display/meal_macros_line.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';

/// A logged intake, rendered as a full-width row: a rounded thumbnail, the meal
/// name and amount, and the energy on the trailing edge. Replaces the old
/// 120x120 tile so a day's meals read as a clean scannable list.
class IntakeCard extends StatelessWidget {
  // was 52
  static const double thumbSize = 32;

  final IntakeEntity intake;
  final Function(BuildContext, IntakeEntity)? onItemLongPressed;
  final Function(BuildContext, IntakeEntity, bool)? onItemTapped;
  final bool firstListElement;
  final bool usesImperialUnits;
  final DiarySortType? sortType;

  // the time eaten beside the amount, in an
  // hour's section where foods of one hour are listed together
  final bool showTime;

  /// While the Diary selects (S177): whether this entry is picked; null
  /// when not selecting.
  final bool? selected;

  const IntakeCard({
    required super.key,
    required this.intake,
    this.onItemLongPressed,
    this.onItemTapped,
    required this.firstListElement,
    required this.usesImperialUnits,
    this.sortType,
    this.showTime = false,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(Dimens.radiusM);
    final s = S.of(context);
    final macro = switch (sortType) {
      DiarySortType.protein => (intake.totalProteinsGram, s.proteinLabel),
      DiarySortType.carbs => (intake.totalCarbsGram, s.carbsLabel),
      DiarySortType.fat => (intake.totalFatsGram, s.fatLabel),
      _ => null,
    };
    final macroValue = macro == null
        ? null
        : NumberFormat.decimalPatternDigits(
            locale: Localizations.localeOf(context).toString(),
            decimalDigits: 1,
          ).format(macro.$1);
    // the amount under the energy, the macros
    // under the name
    final amount = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            amountText(intake, usesImperialUnits),
            style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (showTime && !hasNoTime(intake))
          Text(
            ' · ${clockText(context, intake.dateTime)}',
            style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing16,
        vertical: 2, //: was Dimens.spacing4
      ),
      child: Semantics(
        selected: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onItemTapped != null
                ? () => onTappedItem(context, usesImperialUnits)
                : null,
            onLongPress: onItemLongPressed != null
                ? () => onLongPressedItem(context)
                : null,
            child: AppCard(
              color: selected == true
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
              borderRadius: Dimens.radiusM,
              // was EdgeInsets.all(Dimens.spacing12),
              // the row at least 48 tall
              padding: const EdgeInsets.symmetric(
                horizontal: Dimens.spacing12,
                vertical: 6,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Row(
                  children: [
                    if (selected case final picked?)
                      SizedBox.square(
                        dimension: IntakeCard.thumbSize,
                        child: Icon(
                          picked
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: picked
                              ? Theme.of(context).colorScheme.primary
                              : palette.textMuted,
                        ),
                      )
                    else
                      _Thumbnail(intake: intake, palette: palette),
                    const SizedBox(width: Dimens.spacing12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AutoSizeText(
                            intake.meal.name ?? "?",
                            style: textTheme.titleSmall?.copyWith(
                              color: palette.textStrong,
                            ),
                            maxLines:
                                2, // large-text: a long name wraps once before it is cut
                            minFontSize: 11,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // was the amount, and
                          // the time in an hour's section (S80)
                          const SizedBox(height: 2),
                          MacrosLine(
                            carbs: intake.totalCarbsGram,
                            fat: intake.totalFatsGram,
                            protein: intake.totalProteinsGram,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Dimens.spacing8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (macro != null)
                            Text(
                              '$macroValue ${s.gramUnit} ${macro.$2}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelMedium?.copyWith(
                                color: palette.textStrong,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          Text(
                            EnergyDisplay.formatWithUnit(
                              context,
                              intake.totalKcal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: macro == null
                                ? textTheme.labelMedium?.copyWith(
                                    color: palette.textStrong,
                                    fontWeight: FontWeight.w700,
                                  )
                                : textTheme.bodySmall?.copyWith(
                                    color: palette.textMuted,
                                  ),
                          ),
                          amount,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void onLongPressedItem(BuildContext context) {
    onItemLongPressed?.call(context, intake);
  }

  void onTappedItem(BuildContext context, bool usesImperialUnits) {
    onItemTapped?.call(context, intake, usesImperialUnits);
  }
}

/// The leading thumbnail: a user photo, the remote OFF/FDC image, or a soft
/// fallback chip with a food icon — clipped to a rounded square.
class _Thumbnail extends StatelessWidget {
  final IntakeEntity intake;
  final AppPalette palette;

  const _Thumbnail({required this.intake, required this.palette});

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (intake.meal.localImagePath != null) {
      content = _LocalMealImage(relativePath: intake.meal.localImagePath!);
    } else if (intake.meal.mainImageUrl != null &&
        OffKinds.showsPhoto(intake.meal)) {
      content = CachedNetworkImage(
        cacheManager: locator<CacheManager>(),
        imageUrl: intake.meal.mainImageUrl ?? "",
        fit: BoxFit.cover,
        errorWidget: (context, url, error) => _fallback(),
        placeholder: (context, url) => _fallback(),
      );
    } else {
      content = _fallback();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(Dimens.radiusS),
      child: SizedBox(
        width: IntakeCard.thumbSize,
        height: IntakeCard.thumbSize,
        child: content,
      ),
    );
  }

  // the food's kind when its name or categories
  // say one, as on its search row
  Widget _fallback() => Container(
    color: palette.surfaceMuted,
    alignment: Alignment.center,
    // In color, as a food's emoji; a plate when its kind is unknown.
    child: switch (importedFoodIcon(intake)) {
      final icon? => Icon(icon, color: palette.textMuted, size: 18),
      //: was 24
      _ => ExcludeSemantics(
        child: Text(
          importedFoodEmoji(intake) ??
              OffKinds.emojiFor(intake.meal) ??
              resolveFoodEmoji(intake.meal.name) ??
              '🍽️',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    },
  );
}

class _LocalMealImage extends StatelessWidget {
  final String relativePath;

  const _LocalMealImage({required this.relativePath});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: UserImageStorage.absolutePath(relativePath),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final file = File(snapshot.data!);
        if (!file.existsSync()) return const SizedBox.shrink();
        return Image.file(file, fit: BoxFit.cover);
      },
    );
  }
}
