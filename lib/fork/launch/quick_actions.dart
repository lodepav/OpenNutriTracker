import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/add/add_sheet.dart';
import 'package:opennutritracker/fork/bulk/ai_add.dart';
import 'package:opennutritracker/fork/launch/launch_actions.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Home's way straight to the frequent actions (seam S162): search, then the
/// launcher shortcuts by the same names, each for today and the time's meal.
/// Photo log shows while AI meal assistance is on, as on the + sheet.
class QuickActions extends StatefulWidget {
  const QuickActions({super.key});

  @override
  State<QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends State<QuickActions> {
  final _ai = aiAddEnabled();

  Widget _tile(String id, IconData icon, String label, LaunchAction action) =>
      actionTile(
        context,
        id: 'home-quick-$id',
        icon: icon,
        label: label,
        onTap: () => openLaunchAction(context, action),
      );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Dimens.spacing16,
      vertical: Dimens.spacing8,
    ),
    child: FutureBuilder<bool>(
      future: _ai,
      builder: (context, ai) => actionTiles(context, [
        _tile(
          'search',
          Icons.search_rounded,
          S.of(context).searchLabel,
          const SearchAction(),
        ),
        _tile(
          'scan',
          Icons.qr_code_scanner_rounded,
          'Scan',
          const ScanAction(),
        ),
        if (ai.data == true)
          _tile(
            'photo',
            Icons.photo_camera_outlined,
            'Photo log',
            const PhotoAction(),
          ),
        _tile(
          'quick-add',
          Icons.bolt_rounded,
          S.of(context).quickAddCardLabel,
          const QuickAddAction(),
        ),
        _tile(
          'weigh-in',
          Icons.monitor_weight_outlined,
          'Weigh in',
          const WeighInAction(),
        ),
      ]),
    ),
  );
}
