import '../../../../core/result/result.dart';
import '../entities/ingredient.dart';
import '../entities/ingredient_inputs.dart';
import '../entities/ingredient_query.dart';
import '../entities/menu_page.dart';

abstract class IngredientRepository {
  Future<Result<MenuPage<Ingredient>>> list(IngredientQuery query);
  Future<Result<Ingredient>> detail(String id);
  Future<Result<Ingredient>> create(CreateIngredientInput input);
  Future<Result<Ingredient>> update(String id, UpdateIngredientInput input);
  Future<Result<Ingredient>> setStatus(
    String id,
    bool active,
    int expectedVersion,
  );
  Future<Result<void>> delete(String id, int expectedVersion);
}
