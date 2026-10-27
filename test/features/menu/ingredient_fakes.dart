import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/data/dto/ingredient_dto.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient_query.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_page.dart';
import 'package:pos_saas_app/features/menu/domain/repositories/ingredient_repository.dart';

import 'menu_fakes.dart' show page;

const ingredientPermissions = {
  'INGREDIENT_VIEW',
  'INGREDIENT_CREATE',
  'INGREDIENT_UPDATE',
  'INGREDIENT_DELETE',
};

Map<String, dynamic> ingredientJson({
  int version = 4,
  bool active = true,
  String name = 'Thịt bò',
  bool costConfigured = true,
}) => {
  'id': 'ingredient-1',
  'sku': 'NL-BO',
  'name': name,
  'baseUnit': 'g',
  'description': 'Thịt bò dùng cho phở',
  'costPrice': 250.25,
  'costConfigured': costConfigured,
  'trackInventory': true,
  'active': active,
  'version': version,
  'createdAt': '2026-10-16T08:00:00Z',
  'updatedAt': '2026-10-16T09:00:00Z',
};

Ingredient ingredient({
  int version = 4,
  bool active = true,
  String name = 'Thịt bò',
  bool costConfigured = true,
}) => IngredientDto.fromJson(
  ingredientJson(
    version: version,
    active: active,
    name: name,
    costConfigured: costConfigured,
  ),
).toEntity();

class FakeIngredients implements IngredientRepository {
  Ingredient current = ingredient();
  List<Ingredient> rows = [ingredient()];
  final queries = <IngredientQuery>[];
  final writes = <(String, int)>[];
  int detailCalls = 0;
  CreateIngredientInput? lastCreate;
  UpdateIngredientInput? lastUpdate;
  bool? lastActive;
  Future<Result<MenuPage<Ingredient>>> Function(IngredientQuery)? onList;
  Future<Result<Ingredient>> Function()? onWrite;
  Future<Result<Ingredient>> Function()? onDetail;

  @override
  Future<Result<MenuPage<Ingredient>>> list(IngredientQuery query) async {
    queries.add(query);
    return onList != null
        ? onList!(query)
        : Success(page(rows, index: query.page));
  }

  @override
  Future<Result<Ingredient>> detail(String id) async {
    detailCalls++;
    return onDetail != null ? onDetail!() : Success(current);
  }

  Future<Result<Ingredient>> _write(String kind, int version) async {
    writes.add((kind, version));
    return onWrite != null ? onWrite!() : Success(current);
  }

  @override
  Future<Result<Ingredient>> create(CreateIngredientInput input) {
    lastCreate = input;
    return _write('create', -1);
  }

  @override
  Future<Result<Ingredient>> update(String id, UpdateIngredientInput input) {
    lastUpdate = input;
    return _write('update', input.expectedVersion);
  }

  @override
  Future<Result<Ingredient>> setStatus(
    String id,
    bool active,
    int expectedVersion,
  ) {
    lastActive = active;
    return _write('status', expectedVersion);
  }

  @override
  Future<Result<void>> delete(String id, int expectedVersion) async {
    return switch (await _write('delete', expectedVersion)) {
      Success() => const Success(null),
      Error(:final failure) => Error(failure),
    };
  }
}
