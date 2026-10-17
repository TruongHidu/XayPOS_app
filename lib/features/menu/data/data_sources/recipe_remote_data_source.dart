import 'package:dio/dio.dart';

import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_inputs.dart';
import '../../domain/entities/recipe_query.dart';
import '../dto/menu_dto.dart';
import '../dto/recipe_dto.dart';
import '../dto/recipe_requests.dart';

class RecipeRemoteDataSource {
  /// Inject the existing authenticated client so JWT/refresh use shared policy.
  const RecipeRemoteDataSource(this._dio);
  final Dio _dio;

  String _prefix(String menuItemId) =>
      '/api/v1/menu/items/${Uri.encodeComponent(menuItemId)}/recipes';

  Options get _readOptions =>
      Options(headers: {'Accept': Headers.jsonContentType});
  Options get _writeOptions => Options(
    contentType: Headers.jsonContentType,
    headers: {'Accept': Headers.jsonContentType},
  );

  Future<RecipeDto> active(String menuItemId) async {
    final response = await _dio.get<Object>(
      '${_prefix(menuItemId)}/active',
      options: _readOptions,
    );
    return RecipeDto.fromJson(response.data);
  }

  Future<MenuPageDto<RecipeSummary>> history(
    String menuItemId,
    RecipeQuery query,
  ) async {
    final response = await _dio.get<Object>(
      _prefix(menuItemId),
      queryParameters: RecipeRequests.query(query),
      options: _readOptions,
    );
    return MenuPageDto.fromJson(
      response.data,
      (json) => RecipeSummaryDto.fromJson(json).toEntity(),
    );
  }

  Future<RecipeDto> detail(String menuItemId, String recipeId) async {
    final response = await _dio.get<Object>(
      '${_prefix(menuItemId)}/${Uri.encodeComponent(recipeId)}',
      options: _readOptions,
    );
    return RecipeDto.fromJson(response.data);
  }

  Future<RecipeDto> create(String menuItemId, RecipeInput input) async {
    final response = await _dio.post<Object>(
      _prefix(menuItemId),
      data: RecipeRequests.create(input),
      options: _writeOptions,
    );
    return RecipeDto.fromJson(response.data);
  }

  Future<RecipeDto> createVersion(
    String menuItemId,
    String activeRecipeId,
    CreateRecipeVersionInput input,
  ) async {
    final response = await _dio.post<Object>(
      '${_prefix(menuItemId)}/${Uri.encodeComponent(activeRecipeId)}/versions',
      data: RecipeRequests.createVersion(input),
      options: _writeOptions,
    );
    return RecipeDto.fromJson(response.data);
  }

  Future<void> deactivate(
    String menuItemId,
    String recipeId,
    int expectedVersion,
  ) async {
    await _dio.delete<void>(
      '${_prefix(menuItemId)}/${Uri.encodeComponent(recipeId)}',
      queryParameters: {'expectedVersion': expectedVersion},
      options: _readOptions,
    );
  }
}
