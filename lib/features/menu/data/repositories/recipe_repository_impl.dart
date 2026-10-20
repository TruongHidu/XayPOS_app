import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/menu_page.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_cost_estimate.dart';
import '../../domain/entities/recipe_inputs.dart';
import '../../domain/entities/recipe_query.dart';
import '../../domain/repositories/recipe_repository.dart';
import '../../domain/validation/recipe_validation.dart';
import '../data_sources/recipe_remote_data_source.dart';

class RecipeRepositoryImpl implements RecipeRepository {
  const RecipeRepositoryImpl(this._remote);
  final RecipeRemoteDataSource _remote;

  @override
  Future<Result<RecipeCostEstimate>> costEstimate(
    String menuItemId,
    String recipeId,
  ) => _result(() => _remote.costEstimate(menuItemId, recipeId));

  Future<Result<T>> _result<T>(Future<T> Function() operation) async {
    try {
      return Success(await operation());
    } on FormatException {
      return Error(
        Failure(
          type: FailureType.internal,
          code: 'INVALID_RECIPE_RESPONSE',
          message:
              'Dữ liệu công thức từ máy chủ không hợp lệ. Vui lòng tải lại.',
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
                message: 'Không thể xử lý công thức. Vui lòng thử lại sau.',
              )
            : failure,
      );
    }
  }

  Result<T> _invalid<T>(Map<String, String> fieldErrors) => Error(
    Failure(
      type: FailureType.validation,
      code: 'VALIDATION_ERROR',
      message: 'Thông tin công thức chưa hợp lệ. Vui lòng kiểm tra dữ liệu.',
      fieldErrors: fieldErrors,
    ),
  );

  @override
  Future<Result<Recipe>> active(String menuItemId) =>
      _result(() async => (await _remote.active(menuItemId)).toEntity());

  @override
  Future<Result<MenuPage<RecipeSummary>>> history(
    String menuItemId,
    RecipeQuery query,
  ) async {
    if (!query.isValid) {
      return _invalid({'query': 'Bộ lọc lịch sử công thức không hợp lệ.'});
    }
    return _result(
      () async => (await _remote.history(menuItemId, query)).toEntity(),
    );
  }

  @override
  Future<Result<Recipe>> detail(String menuItemId, String recipeId) => _result(
    () async => (await _remote.detail(menuItemId, recipeId)).toEntity(),
  );

  @override
  Future<Result<Recipe>> create(String menuItemId, RecipeInput input) async {
    final errors = RecipeValidation.input(input);
    if (errors.isNotEmpty) return _invalid(errors);
    return _result(
      () async => (await _remote.create(menuItemId, input)).toEntity(),
    );
  }

  @override
  Future<Result<Recipe>> createVersion(
    String menuItemId,
    String activeRecipeId,
    CreateRecipeVersionInput input,
  ) async {
    final errors = RecipeValidation.input(input);
    if (errors.isNotEmpty) return _invalid(errors);
    return _result(
      () async => (await _remote.createVersion(
        menuItemId,
        activeRecipeId,
        input,
      )).toEntity(),
    );
  }

  @override
  Future<Result<void>> deactivate(
    String menuItemId,
    String recipeId,
    int expectedVersion,
  ) async {
    if (expectedVersion < 0) {
      return _invalid({
        'expectedVersion': 'Phiên bản dữ liệu không hợp lệ. Vui lòng tải lại.',
      });
    }
    return _result(
      () => _remote.deactivate(menuItemId, recipeId, expectedVersion),
    );
  }
}
