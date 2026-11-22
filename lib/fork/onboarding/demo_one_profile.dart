import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';

/// Whether onboarding may offer Try Demo (S430). The demo wipe clears the
/// recipe, custom food and activity template boxes every profile shares, so
/// it is offered only while the active profile is the only one.
bool canOfferDemo() {
  if (!locator.isRegistered<GetProfilesUsecase>()) return true; // widget tests
  return locator<GetProfilesUsecase>().getProfiles().length <= 1;
}
