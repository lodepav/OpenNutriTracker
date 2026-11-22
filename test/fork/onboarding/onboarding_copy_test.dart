import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/utils/theme_mode_provider.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_activity_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_other_options_page_body.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_pal_category_dialog.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

// G1 sweep: upstream strings that read wrong in OpenBite, shown in fork
// English (lib/fork/onboarding/onboarding_copy.dart).
void main() {
  testWidgets('activity levels are in sentence case on the page, in the '
      "profile's dialog and by name", (tester) async {
    await pumpOnPhone(
      tester,
      OnboardingActivityPageBody(setButtonContent: (_, _) {}),
      textScale: 1,
    );
    expect(find.text('Lightly active'), findsOneWidget);
    expect(find.text('Very active'), findsOneWidget);
    expect(find.text('Low Active'), findsNothing);

    await pumpOnPhone(tester, const SetPALCategoryDialog(), textScale: 1);
    expect(find.text('Lightly active'), findsOneWidget);
    expect(find.text('Very active'), findsOneWidget);

    final context = tester.element(find.byType(SetPALCategoryDialog));
    expect(UserPALEntity.lowActive.getName(context), 'Lightly active');
    expect(UserPALEntity.veryActive.getName(context), 'Very active');
    expect(UserPALEntity.active.getName(context), l10nEn.palActiveLabel);
  });

  testWidgets('other options: one spelling, and the reminder says what it '
      'does', (tester) async {
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider<ThemeModeProvider>(
        create: (_) => ThemeModeProvider(appTheme: AppThemeEntity.system),
        child: OnboardingOtherOptionsPageBody(
          setPageContent: (_, _, _, _, _) {},
          initialTheme: AppThemeEntity.system,
          initialFoodSourceToggles: const {},
          initialDailyReminderEnabled: false,
          initialUseMaterialYou: false,
          initialAccentColor: null,
        ),
      ),
      textScale: 1,
    );
    expect(
      find.text(
        'Personalise the app. You can change all of this later in Settings.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'A reminder once a day to log your meals. Set its time in Settings.',
      ),
      findsOneWidget,
    );
    expect(find.text(l10nEn.notificationsDailyReminderBody), findsNothing);
  });
}
