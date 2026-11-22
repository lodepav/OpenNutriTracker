import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/fork/custom_food/serving_mode.dart';

// G3-19: which custom foods were typed per serving survives a restart, an
// edit that changes the food's key moves the mark, and a food saved before
// this has none.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('serving_mode');
    Hive.init(dir.path);
    CustomFoodModes.perServing.value = const {};
  });

  tearDown(() async {
    await Hive.close();
    CustomFoodModes.perServing.value = const {};
  });

  Future<Box<dynamic>> box() => Hive.openBox<dynamic>('modes');

  test('a mark is kept, moved on an edit, and dropped per 100 g', () async {
    final store = CustomFoodModes(box);
    await store.record('Pierogi ż', perServing: true);
    await store.record('bar', perServing: true);
    expect(CustomFoodModes.perServing.value, {'Pierogi ż', 'bar'});

    // a fresh start reads what was stored
    CustomFoodModes.perServing.value = const {};
    await store.load();
    expect(CustomFoodModes.perServing.value, {'Pierogi ż', 'bar'});

    await store.record('bar-2', perServing: true, previousKey: 'bar');
    expect(CustomFoodModes.perServing.value, {'Pierogi ż', 'bar-2'});

    await store.record('Pierogi ż', perServing: false);
    expect(CustomFoodModes.perServing.value, {'bar-2'});
  });

  test('an empty box marks nothing', () async {
    await CustomFoodModes(box).load();
    expect(CustomFoodModes.perServing.value, isEmpty);
  });
}
