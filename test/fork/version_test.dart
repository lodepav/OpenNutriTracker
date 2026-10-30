// About names the upstream release OpenBite is built on (D16).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/version.dart';

void main() {
  test("upstreamVersion is pubspec's version name: update it at each upstream "
      'merge', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final name = RegExp(
      r'^version: ([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(upstreamVersion, name);
  });

  test("fork/VERSION is OpenBite's own semver", () {
    expect(
      File('fork/VERSION').readAsStringSync().trim(),
      matches(RegExp(r'^\d+\.\d+\.\d+$')),
    );
    expect(
      aboutVersion('0.1.0'),
      '0.1.0 · based on OpenNutriTracker $upstreamVersion',
    );
  });
}
