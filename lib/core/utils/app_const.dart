import 'dart:io' show Platform;
import 'package:package_info_plus/package_info_plus.dart';

class AppConst {
  // [fork] S76 releases: OpenBite's name and source (GPL), as Open Food Facts
  // and About see them; the version is OpenBite's own (D16)
  static const userAgentAppName = "OpenBite";
  // [/fork]
  static const platformNameAndroid = "Android";
  static const platformNameIOS = "iOS";
  static const reportErrorEmail = "opennutritracker-dev@pm.me";
  // [fork] S76 releases
  static const sourceCodeUrl = "https://github.com/lodepav/OpenNutriTracker";
  // [/fork]

  // Support page links (#1536). Every one opens outside the app.
  static const appStoreUrl = "https://apps.apple.com/app/id6451490901";

  /// The App Store's write-a-review form. iOS only: Play has no documented
  /// review-form link, so Android opens [playStoreUrl] instead (#1531).
  static const appStoreReviewUrl = "$appStoreUrl?action=write-review";
  static const playStoreUrl =
      "https://play.google.com/store/apps/details?id=com.opennutritracker.ont.opennutritracker";
  static const translateUrl =
      "https://hosted.weblate.org/engage/opennutritracker/";
  static const newIssueUrl = "$sourceCodeUrl/issues/new/choose";
  static const contributingUrl = "$sourceCodeUrl/blob/main/CONTRIBUTING.md";

  static Future<String> getVersionNumber() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  static String getPlatformName() {
    if (Platform.isAndroid) {
      return platformNameAndroid;
    } else if (Platform.isIOS) {
      return platformNameIOS;
    } else {
      return "";
    }
  }

  static Future<String> getUserAgentString() async {
    final versionNumber = await getVersionNumber();
    final platformVersion = getPlatformName();
    return '$userAgentAppName - $platformVersion - Version $versionNumber - $sourceCodeUrl';
  }
}
