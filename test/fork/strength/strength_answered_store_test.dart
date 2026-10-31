import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/strength/strength_signal.dart';

void main() {
  test('an answer outlasts the box closing, beside the settings', () async {
    final dir = await Directory.systemTemp.createTemp('strength_answered');
    addTearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });
    Hive.init(dir.path);
    final store = AdaptiveStore(() => Hive.openBox<dynamic>('adaptive'));
    final at = DateTime(2026, 10, 31);
    await store.writeKey(
      'strengthAnswered',
      StrengthAnswered('falling|Chest', at).encode(),
    );
    await Hive.close();
    Hive.init(dir.path);
    final read = StrengthAnswered.decode(
      await store.readKey('strengthAnswered'),
    );
    expect(read?.key, 'falling|Chest');
    expect(read?.at, at);
    expect((await store.read()).fixedKcal, 2000);
  });
}
