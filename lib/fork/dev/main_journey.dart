// flutter_driver is a dev dependency; this entry point is debug only.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:opennutritracker/fork/dev/journey_handler.dart';
import 'package:opennutritracker/main.dart' as app;

/// The journey check's entry point (fork/ux/JOURNEYS.md): the normal app,
/// with flutter_driver's extension on the VM service, no network, and a
/// camera that gives a bundled photo. Not lib/dev/main_dev.dart, which
/// reseeds on every launch.
///
///   flutter build apk --flavor develop --debug \
///     -t lib/fork/dev/main_journey.dart --dart-define=FORK_FAKE_AI=true
Future<void> main() async {
  if (kReleaseMode) {
    throw UnsupportedError(
      'lib/fork/dev/main_journey.dart drives the app and must never be built '
      'in release mode',
    );
  }
  HttpOverrides.global = JourneyOffline();
  enableFlutterDriverExtension(
    handler: journeyHandler,
    finders: [JourneyFinder()],
  );
  ImagePickerPlatform.instance = JourneyImagePicker();
  await app.main();
}
