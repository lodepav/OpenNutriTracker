import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_dbo.dart';
import 'package:opennutritracker/core/data/dbo/weight_log_dbo.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_display_format.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_display_name.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/profile_avatar.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/generated/l10n.dart';

AppPalette _palette(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppPalette.dark
    : AppPalette.light;

/// What a profile's card says of it; null where it has nothing yet.
typedef ProfileStats = ({
  UserWeightGoalEntity? goal,
  double? kcalGoal,
  double? trendKg,
  int daysLogged,
});

/// [ProfileStats] from a profile's boxes: the goal of its latest tracked
/// day up to [today], its weight trend on [today], and the days it logged
/// food on.
ProfileStats profileStats(
  UserDBO? user,
  Iterable<TrackedDayDBO> days,
  Iterable<WeightLogDBO> weights,
  DateTime today,
) {
  final end = DateTime(today.year, today.month, today.day + 1);
  final past = [
    for (final d in days)
      if (d.day.isBefore(end)) d,
  ]..sort((a, b) => a.day.compareTo(b.day));
  final trend = trendPoints([
    for (final w in weights) WeightLogEntity.fromWeightLogDBO(w),
  ], until: today);
  return (
    goal: user == null
        ? null
        : UserWeightGoalEntity.fromUserWeightGoalDBO(user.goal),
    kcalGoal: past.lastOrNull?.calorieGoal,
    trendKg: trend.lastOrNull?.weightKg,
    daysLogged: past.where((d) => d.caloriesTracked > 0).length,
  );
}

/// [profileStats] for [profile]: the open boxes when it is the active one,
/// else its own, opened for the read and closed after.
Future<ProfileStats> readProfileStats(
  HiveDBProvider db,
  ProfileEntity profile, {
  required bool active,
  DateTime Function() clock = DateTime.now,
}) async {
  if (active) {
    return profileStats(
      db.userBox.get(_userKey),
      db.trackedDayBox.values,
      db.weightLogBox.values,
      clock(),
    );
  }
  final suffix = profile.boxSuffix;
  try {
    final user = await db.openScopedBox<UserDBO>(
      HiveDBProvider.userBoxName,
      suffix,
    );
    final days = await db.openScopedBox<TrackedDayDBO>(
      HiveDBProvider.trackedDayBoxName,
      suffix,
    );
    final weights = await db.openScopedBox<WeightLogDBO>(
      HiveDBProvider.weightLogBoxName,
      suffix,
    );
    return profileStats(
      user.get(_userKey),
      days.values,
      weights.values,
      clock(),
    );
  } finally {
    await db.closeScopedBox<UserDBO>(HiveDBProvider.userBoxName, suffix);
    await db.closeScopedBox<TrackedDayDBO>(
      HiveDBProvider.trackedDayBoxName,
      suffix,
    );
    await db.closeScopedBox<WeightLogDBO>(
      HiveDBProvider.weightLogBoxName,
      suffix,
    );
  }
}

/// UserDataSource's key for the one user of a box.
const _userKey = 'UserKey';

/// Seam S139: Profiles as MacroFactor's (PickProf B). A card for each
/// profile with what it is working toward and three figures, Switch on the
/// others, and Add profile under them.
class ProfilesView extends StatelessWidget {
  final List<ProfileEntity> profiles;
  final String activeId;

  /// Each profile's figures by its id, once read.
  final Map<String, ProfileStats> stats;
  final BodyWeightUnit weightUnit;
  final ValueChanged<ProfileEntity> onEdit;
  final ValueChanged<ProfileEntity> onSwitch;
  final ValueChanged<ProfileEntity> onDelete;

  const ProfilesView({
    super.key,
    required this.profiles,
    required this.activeId,
    required this.stats,
    required this.weightUnit,
    required this.onEdit,
    required this.onSwitch,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      Dimens.spacing12,
      Dimens.spacing8,
      Dimens.spacing12,
      Dimens.spacing32,
    ),
    children: [
      for (final p in profiles)
        _ProfileCard(
          profile: p,
          active: p.id == activeId,
          stats: stats[p.id],
          weightUnit: weightUnit,
          canDelete: profiles.length > 1,
          onEdit: () => onEdit(p),
          onSwitch: () => onSwitch(p),
          onDelete: () => onDelete(p),
        ),
    ],
  );
}

class _ProfileCard extends StatelessWidget {
  final ProfileEntity profile;
  final bool active;
  final ProfileStats? stats;
  final BodyWeightUnit weightUnit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onSwitch;
  final VoidCallback onDelete;

  const _ProfileCard({
    required this.profile,
    required this.active,
    required this.stats,
    required this.weightUnit,
    required this.canDelete,
    required this.onEdit,
    required this.onSwitch,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final text = Theme.of(context).textTheme;
    final s = S.of(context);
    final stats = this.stats;
    final name = profileDisplayName(context, profile);
    final since =
        'since ${DateFormat.yMMM(Localizations.localeOf(context).toLanguageTag()).format(profile.createdAt)}';
    final about = [?stats?.goal?.getName(context), since].join(' · ');
    Widget figure(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: text.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
    final kcal = stats?.kcalGoal;
    final trend = stats?.trendKg;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing8),
      child: AppCard(
        padding: const EdgeInsets.all(Dimens.spacing12),
        child: Semantics(
          identifier: 'profile-card-${profile.id}',
          container: true,
          child: Column(
            children: [
              Row(
                children: [
                  ProfileAvatar(profile: profile, radius: 24),
                  const SizedBox(width: Dimens.spacing12),
                  Expanded(
                    child: MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: Dimens.spacing8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                name,
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (active)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: palette.accent.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    s.profileActiveLabel,
                                    style: text.labelSmall?.copyWith(
                                      color: palette.accent,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            about,
                            style: text.bodySmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Semantics(
                    identifier: 'manage-profiles-edit',
                    child: IconButton(
                      tooltip: 'Edit $name',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: onEdit,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Dimens.spacing8),
              Row(
                children: [
                  figure(
                    kcal == null ? '—' : '${energyValue(context, kcal)}',
                    '${energyUnit(context)} goal',
                  ),
                  figure(
                    trend == null
                        ? '—'
                        : formatBodyWeight(
                            trend,
                            weightUnit,
                            kgLabel: s.kgLabel,
                            lbLabel: s.lbsLabel,
                            stLabel: s.stLabel,
                          ),
                    'trend',
                  ),
                  figure('${stats?.daysLogged ?? '—'}', 'days logged'),
                ],
              ),
              if (!active || canDelete) ...[
                const SizedBox(height: Dimens.spacing8),
                Row(
                  children: [
                    if (!active)
                      Expanded(
                        child: Semantics(
                          identifier: 'profile-switch-${profile.id}',
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              side: BorderSide(color: palette.border),
                            ),
                            onPressed: onSwitch,
                            child: Text('Switch to $name'),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    if (canDelete) ...[
                      const SizedBox(width: Dimens.spacing8),
                      Semantics(
                        identifier: 'manage-profiles-delete',
                        child: IconButton(
                          tooltip: 'Delete $name',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: onDelete,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
