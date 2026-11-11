import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/scale_rows.dart';

MealEntity _meal(String name) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: MealSourceEntity.fdc,
);

class _Resolver implements ResolveParsedMealsUseCase {
  @override
  Future<List<ResolvedMealItem>> resolve(
    List<ParsedMealItem> items, {
    bool fromPhoto = false,
  }) async => [
    for (final item in items)
      ResolvedMealItem(
        parsed: item,
        candidates: [_meal(item.query), _meal('${item.query}, other')],
        selectedIndex: 0,
        confidence: 1,
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoText implements ReadMealTextUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhotoReader implements ReadMealPhotoUseCase {
  @override
  Future<MealPhotoReadResult> read(
    MealPhoto photo, {
    String? localeCode,
    String? note,
  }) async => const MealPhotoRead(
    MealTextParseResult(
      items: [
        ParsedMealItem(query: 'rice', quantity: 150, unit: 'g'),
        ParsedMealItem(query: 'chicken', quantity: 120, unit: 'g'),
      ],
      errors: [],
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late BulkAddBloc bloc;

  setUp(() async {
    bloc = BulkAddBloc(_Resolver(), _NoText(), _PhotoReader());
    bloc.add(
      ReadMealPhotoEvent(
        photo: MealPhoto(bytes: Uint8List(1), mediaType: 'image/webp'),
        usesImperialUnits: false,
      ),
    );
    await bloc.stream.firstWhere((s) => s is BulkAddLoadedState);
  });

  tearDown(() => bloc.close());

  List<BulkAddRow> rows() => (bloc.state as BulkAddLoadedState).rows;

  test('sets each row named, in one state, the rows left unedited', () async {
    final before = rows();
    final states = <BulkAddState>[];
    final listening = bloc.stream.listen(states.add);
    bloc.add(
      ScaleRowsEvent({before[0].resolved: '90', before[1].resolved: '72'}),
    );
    await Future<void>.delayed(Duration.zero);
    await listening.cancel();

    expect(states, hasLength(1));
    expect([for (final row in rows()) row.amountText], ['90', '72']);
    expect(rows().every((row) => !row.amountEditedByUser), isTrue);
    expect(rows().every((row) => row.isPristine), isTrue);
    expect([for (final row in rows()) row.unit], ['g', 'g']);
  });

  test('finds its rows by identity, wherever they moved', () async {
    final chicken = rows()[1].resolved;
    bloc.add(ScaleRowsEvent({chicken: '60'}));
    await Future<void>.delayed(Duration.zero);
    expect([for (final row in rows()) row.amountText], ['150', '60']);
  });

  test('a match picked after it still re-derives the amount', () async {
    bloc.add(ScaleRowsEvent({rows()[0].resolved: '90'}));
    await Future<void>.delayed(Duration.zero);
    bloc.add(const ChangeRowCandidateEvent(0, 1));
    await Future<void>.delayed(Duration.zero);
    expect(rows()[0].amountText, '150');
  });
}
