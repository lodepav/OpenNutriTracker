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
