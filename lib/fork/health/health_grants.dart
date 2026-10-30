import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

const _channel = MethodChannel('openbite/health_grants');

/// Whether the Health Connect grants [names] (`READ_WEIGHT`, …) are held; on
/// Android through the fork's channel, as the health plugin's own check ends
/// the process when Health Connect refuses the call (rate limited, updating).
/// Elsewhere the plugin's answer, null where the platform will not say.
/// Throws a [PlatformException] when Health Connect refuses.
Future<bool?> hasHealthGrants(
  List<String> names,
  List<HealthDataType> types,
  List<HealthDataAccess> access,
) async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return await _channel.invokeMethod<bool>('hasGrants', {'names': names}) ??
        false;
  }
  return Health().hasPermissions(types, permissions: access);
}

/// [hasHealthGrants] right after a request: a refused check counts as not
/// granted, and a platform that will not say as granted.
Future<bool> hasHealthGrantsOrFalse(
  List<String> names,
  List<HealthDataType> types,
  List<HealthDataAccess> access,
) async {
  try {
    return await hasHealthGrants(names, types, access) != false;
  } on PlatformException {
    return false;
  }
}
