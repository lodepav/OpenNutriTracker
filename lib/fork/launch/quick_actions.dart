import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/add/add_sheet.dart';
import 'package:opennutritracker/fork/bulk/ai_add.dart';
import 'package:opennutritracker/fork/launch/launch_actions.dart';
import 'package:opennutritracker/fork/layout/home_layout.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';

/// Home's way straight to the frequent actions (seam S162): search, then the
/// launcher shortcuts by the same names, each for today and the time's meal,
/// and the meal plan, as arranged in Arrange Home; search is off until
/// switched on there. Weigh in opens the dialog over Home, where the
/// shortcut opens the weight history.
/// Photo log shows while AI meal assistance is on, as on the + sheet. Home
/// stays alive under other tabs and screens, so the setting is read again
/// each time Home shows: Settings may have changed it meanwhile.
class QuickActions extends StatefulWidget {
  const QuickActions({super.key});

  @override
  State<QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends State<QuickActions> {
  bool _ai = false;
  ValueListenable<TickerModeData>? _shown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Off while another tab or a screen on top hides Home.
    final shown = TickerMode.getValuesNotifier(context);
    if (shown == _shown) return;
    _shown?.removeListener(_onShown);
    _shown = shown..addListener(_onShown);
    _readAi();
  }

  @override
  void dispose() {
    _shown?.removeListener(_onShown);
    super.dispose();
  }

  void _onShown() {
    if (_shown!.value.enabled) _readAi();
  }

  Future<void> _readAi() async {
    final ai = await aiAddEnabled();
    if (mounted && ai != _ai) setState(() => _ai = ai);
  }

  static const Map<String, (IconData, LaunchAction)> _actions = {
    'search': (Icons.search_rounded, SearchAction()),
    'scan': (Icons.qr_code_scanner_rounded, ScanAction()),
    'photo': (Icons.photo_camera_outlined, PhotoAction()),
    'quick-add': (Icons.bolt_rounded, QuickAddAction()),
    'weigh-in': (Icons.monitor_weight_outlined, WeighInDialogAction()),
    'meal-plan': (Icons.event_note_rounded, PlanAction()),
  };

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: LayoutStore.current(homeQuickActionsKey),
    builder: (context, layout, _) {
      final tiles = arranged(
        {
          for (final MapEntry(key: id, value: label) in homeQuickActionNames(
            context,
            ai: _ai,
          ).entries)
            id: actionTile(
              context,
              id: 'home-quick-$id',
              icon: _actions[id]!.$1,
              label: label,
              onTap: () => openLaunchAction(context, _actions[id]!.$2),
            ),
        },
        (
          order: layout.order,
          hidden: {...layout.hidden, ...addable(optionalQuickActions, layout)},
        ),
      );
      if (tiles.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Dimens.spacing16,
          vertical: Dimens.spacing8,
        ),
        child: actionTiles(context, tiles, perRow: 3),
      );
    },
  );
}
