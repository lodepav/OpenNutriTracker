import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';

import 'amount_test_foods.dart';

void main() {
  late Directory dir;
  late OwnPortions portions;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('own-portions');
    Hive.init(dir.path);
    portions = OwnPortions(() => Hive.openBox<dynamic>('own'));
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('kept per food, a name saved again takes the new weight', () async {
    expect(await portions.of(rye()), isEmpty);

    await portions.add(rye(), 'slice', 35);
    await portions.add(rye(), 'heel', 20);
    await portions.add(rye(), 'slice', 38);
    await portions.add(bread(), 'toast', 30);

    final rye_ = await portions.of(rye());
    expect(rye_.map((p) => (p.label, p.gramWeight)), [
      ('heel', 20.0),
      ('slice', 38.0),
    ]);
    expect((await portions.of(bread())).single.label, 'toast');
  });

  test('removed by name; nothing saved without a name or a weight', () async {
    await portions.add(rye(), 'slice', 35);
    await portions.add(rye(), '  ', 35);
    await portions.add(rye(), 'crumb', 0);
    await portions.remove(rye(), 'slice');
    expect(await portions.of(rye()), isEmpty);
  });
}
