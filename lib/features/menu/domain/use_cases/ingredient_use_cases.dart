import '../../../../core/result/result.dart';
import '../entities/ingredient.dart';
import '../entities/ingredient_inputs.dart';
import '../entities/ingredient_query.dart';
import '../entities/menu_page.dart';
import '../repositories/ingredient_repository.dart';

class GetIngredients {
  const GetIngredients(this._repository);
  final IngredientRepository _repository;
  Future<Result<MenuPage<Ingredient>>> call(IngredientQuery query) =>
      _repository.list(query);
}

class GetIngredientDetail {
  const GetIngredientDetail(this._repository);
  final IngredientRepository _repository;
  Future<Result<Ingredient>> call(String id) => _repository.detail(id);
}

class CreateIngredient {
  const CreateIngredient(this._repository);
  final IngredientRepository _repository;
  Future<Result<Ingredient>> call(CreateIngredientInput input) =>
      _repository.create(input);
}

class UpdateIngredient {
  const UpdateIngredient(this._repository);
  final IngredientRepository _repository;
  Future<Result<Ingredient>> call(String id, UpdateIngredientInput input) =>
      _repository.update(id, input);
}

class SetIngredientStatus {
  const SetIngredientStatus(this._repository);
  final IngredientRepository _repository;
  Future<Result<Ingredient>> call(
    String id,
    bool active,
    int expectedVersion,
  ) => _repository.setStatus(id, active, expectedVersion);
}

class DeleteIngredient {
  const DeleteIngredient(this._repository);
  final IngredientRepository _repository;
  Future<Result<void>> call(String id, int expectedVersion) =>
      _repository.delete(id, expectedVersion);
}
