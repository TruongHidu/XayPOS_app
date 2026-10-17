import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/ingredient_inputs.dart';
import '../../domain/entities/ingredient_query.dart';
import '../../domain/entities/menu_page.dart';
import '../../domain/repositories/ingredient_repository.dart';
import '../data_sources/menu_remote_data_source.dart';

class IngredientRepositoryImpl implements IngredientRepository {
  const IngredientRepositoryImpl(this._remote);
  final MenuRemoteDataSource _remote;

  Future<Result<T>> _result<T>(Future<T> Function() operation) async {
    try {
      return Success(await operation());
    } on FormatException {
      return Error(
        Failure(
          type: FailureType.internal,
          code: 'INVALID_INGREDIENT_RESPONSE',
          message:
              'Dữ liệu nguyên liệu từ máy chủ không hợp lệ. Vui lòng tải lại.',
        ),
      );
    } catch (error) {
      final failure = ApiErrorMapper.fromException(error);
      return Error(
        failure.type == FailureType.internal
            ? Failure(
                type: failure.type,
                code: failure.code,
                fieldErrors: failure.fieldErrors,
                message: 'Không thể xử lý nguyên liệu. Vui lòng thử lại sau.',
              )
            : failure,
      );
    }
  }

  @override
  Future<Result<MenuPage<Ingredient>>> list(IngredientQuery query) =>
      _result(() async => (await _remote.listIngredients(query)).toEntity());

  @override
  Future<Result<Ingredient>> detail(String id) =>
      _result(() async => (await _remote.getIngredient(id)).toEntity());

  @override
  Future<Result<Ingredient>> create(CreateIngredientInput input) =>
      _result(() async => (await _remote.createIngredient(input)).toEntity());

  @override
  Future<Result<Ingredient>> update(String id, UpdateIngredientInput input) =>
      _result(
        () async => (await _remote.updateIngredient(id, input)).toEntity(),
      );

  @override
  Future<Result<Ingredient>> setStatus(
    String id,
    bool active,
    int expectedVersion,
  ) => _result(
    () async => (await _remote.setIngredientStatus(
      id,
      active,
      expectedVersion,
    )).toEntity(),
  );

  @override
  Future<Result<void>> delete(String id, int expectedVersion) =>
      _result(() => _remote.deleteIngredient(id, expectedVersion));
}
