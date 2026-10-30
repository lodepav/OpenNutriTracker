/// The OpenNutriTracker release this OpenBite is built on (D16): pubspec's
/// version name, which stays upstream's, while the app's own version is
/// fork/VERSION. A test keeps the two in step at each upstream merge.
const upstreamVersion = '2.6.0';

/// About's version line: "0.1.0 · based on OpenNutriTracker 2.6.0".
String aboutVersion(String version) =>
    '$version · based on OpenNutriTracker $upstreamVersion';
