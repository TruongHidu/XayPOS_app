import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/network/exact_json.dart';
import '../../domain/entities/recipe_cost_estimate.dart';
import '../dto/recipe_cost_estimate_dto.dart';

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

  Future<RecipeCostEstimate> costEstimate(
    String menuItemId,
    String recipeId,
  ) async {
    try {
      // dynamic keeps Dio from forcing its JSON transformer over ResponseType.plain.
      final response = await _dio.get<dynamic>(
        '${_prefix(menuItemId)}/${Uri.encodeComponent(recipeId)}/cost-estimate',
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept': Headers.jsonContentType,
            'Cache-Control': 'no-store',
          },
        ),
      );
      if (response.statusCode != 200) {
        throw const FormatException('Invalid estimate status');
      }
      final result = RecipeCostEstimateDto.fromJson(
        response.data is String
            ? decodeExactJson(response.data as String)
            : response.data,
      );
      if (result.menuItemId != menuItemId || result.recipeId != recipeId) {
        throw const FormatException('Wrong estimate identity');
      }
      return result;
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is String) {
        try {
          error.response!.data = jsonDecode(data);
        } on FormatException {
          /* Keep unknown error. */
        }
      }
      rethrow;
    }
  }

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
