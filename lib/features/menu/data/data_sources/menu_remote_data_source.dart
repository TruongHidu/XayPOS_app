import 'package:dio/dio.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/ingredient_inputs.dart';
import '../../domain/entities/ingredient_query.dart';
import '../../domain/entities/menu_group.dart';
import '../../domain/entities/menu_item.dart';
import '../../domain/entities/menu_inputs.dart';
import '../../domain/entities/menu_query.dart';
import '../dto/ingredient_dto.dart';
import '../dto/ingredient_requests.dart';
import '../dto/menu_dto.dart';
import '../dto/menu_requests.dart';

class MenuRemoteDataSource {
  const MenuRemoteDataSource(this._dio);
  final Dio _dio;

  Future<MenuPageDto<MenuGroup>> listGroups(MenuQuery query) async {
    final response = await _dio.get<Object>(
      '/api/v1/menu/groups',
      queryParameters: MenuRequests.query(query),
    );
    return MenuPageDto.fromJson(
      response.data,
      (json) => MenuGroupDto.fromJson(json).toEntity(),
    );
  }

  Future<MenuGroupDto> getGroup(String id) async {
    final response = await _dio.get<Object>(
      '/api/v1/menu/groups/${Uri.encodeComponent(id)}',
    );
    return MenuGroupDto.fromJson(response.data);
  }

  Future<MenuGroupDto> createGroup(CreateMenuGroupInput input) async {
    final response = await _dio.post<Object>(
      '/api/v1/menu/groups',
      data: MenuRequests.createGroup(input),
    );
    return MenuGroupDto.fromJson(response.data);
  }

  Future<MenuGroupDto> updateGroup(
    String id,
    UpdateMenuGroupInput input,
  ) async {
    final response = await _dio.patch<Object>(
      '/api/v1/menu/groups/${Uri.encodeComponent(id)}',
      data: MenuRequests.updateGroup(input),
    );
    return MenuGroupDto.fromJson(response.data);
  }

  Future<MenuGroupDto> setGroupStatus(
    String id,
    bool active,
    int expectedVersion,
  ) async {
    final response = await _dio.patch<Object>(
      '/api/v1/menu/groups/${Uri.encodeComponent(id)}/status',
      data: {'active': active, 'expectedVersion': expectedVersion},
    );
    return MenuGroupDto.fromJson(response.data);
  }

  Future<void> deleteGroup(String id, int expectedVersion) async {
    await _dio.delete<void>(
      '/api/v1/menu/groups/${Uri.encodeComponent(id)}',
      queryParameters: {'expectedVersion': expectedVersion},
    );
  }

  Future<MenuPageDto<MenuItem>> listItems(MenuQuery query) async {
    final response = await _dio.get<Object>(
      '/api/v1/menu/items',
      queryParameters: MenuRequests.query(query),
    );
    return MenuPageDto.fromJson(
      response.data,
      (json) => MenuItemDto.fromJson(json).toEntity(),
    );
  }

  Future<MenuItemDto> getItem(String id) async {
    final response = await _dio.get<Object>(
      '/api/v1/menu/items/${Uri.encodeComponent(id)}',
    );
    return MenuItemDto.fromJson(response.data);
  }

  Future<MenuItemDto> createItem(CreateMenuItemInput input) async {
    final response = await _dio.post<Object>(
      '/api/v1/menu/items',
      data: MenuRequests.createItem(input),
    );
    return MenuItemDto.fromJson(response.data);
  }

  Future<MenuItemDto> updateItem(String id, UpdateMenuItemInput input) async {
    final response = await _dio.patch<Object>(
      '/api/v1/menu/items/${Uri.encodeComponent(id)}',
      data: MenuRequests.updateItem(input),
    );
    return MenuItemDto.fromJson(response.data);
  }

  Future<MenuItemDto> setItemStatus(
    String id,
    bool active,
    int expectedVersion,
  ) async {
    final response = await _dio.patch<Object>(
      '/api/v1/menu/items/${Uri.encodeComponent(id)}/status',
      data: {'active': active, 'expectedVersion': expectedVersion},
    );
    return MenuItemDto.fromJson(response.data);
  }

  Future<void> deleteItem(String id, int expectedVersion) async {
    await _dio.delete<void>(
      '/api/v1/menu/items/${Uri.encodeComponent(id)}',
      queryParameters: {'expectedVersion': expectedVersion},
    );
  }

  Future<MenuItemDto> setAvailability(
    String id,
    AvailabilityStatus status,
    int expectedVersion,
  ) async {
    final response = await _dio.patch<Object>(
      '/api/v1/menu/items/${Uri.encodeComponent(id)}/availability',
      data: {
        'availabilityStatus': status.code,
        'expectedVersion': expectedVersion,
      },
    );
    return MenuItemDto.fromJson(response.data);
  }

  Future<MenuItemDto> setGroup(
    String id,
    String? groupId,
    int expectedVersion,
  ) async {
    final response = await _dio.put<Object>(
      '/api/v1/menu/items/${Uri.encodeComponent(id)}/group',
      data: {'groupId': groupId, 'expectedVersion': expectedVersion},
    );
    return MenuItemDto.fromJson(response.data);
  }

  // ── INGREDIENTS ──
  Future<MenuPageDto<Ingredient>> listIngredients(IngredientQuery query) async {
    final response = await _dio.get<Object>(
      '/api/v1/menu/ingredients',
      queryParameters: IngredientRequests.query(query),
    );
    return MenuPageDto.fromJson(
      response.data,
      (json) => IngredientDto.fromJson(json).toEntity(),
    );
  }

  Future<IngredientDto> getIngredient(String id) async {
    final response = await _dio.get<Object>(
      '/api/v1/menu/ingredients/${Uri.encodeComponent(id)}',
    );
    return IngredientDto.fromJson(response.data);
  }

  Future<IngredientDto> createIngredient(CreateIngredientInput input) async {
    final response = await _dio.post<Object>(
      '/api/v1/menu/ingredients',
      data: IngredientRequests.create(input),
    );
    return IngredientDto.fromJson(response.data);
  }

  Future<IngredientDto> updateIngredient(
    String id,
    UpdateIngredientInput input,
  ) async {
    final response = await _dio.patch<Object>(
      '/api/v1/menu/ingredients/${Uri.encodeComponent(id)}',
      data: IngredientRequests.update(input),
    );
    return IngredientDto.fromJson(response.data);
  }

  Future<IngredientDto> setIngredientStatus(
    String id,
    bool active,
    int expectedVersion,
  ) async {
    final response = await _dio.patch<Object>(
      '/api/v1/menu/ingredients/${Uri.encodeComponent(id)}/status',
      data: {'active': active, 'expectedVersion': expectedVersion},
    );
    return IngredientDto.fromJson(response.data);
  }

  Future<void> deleteIngredient(String id, int expectedVersion) async {
    await _dio.delete<void>(
      '/api/v1/menu/ingredients/${Uri.encodeComponent(id)}',
      queryParameters: {'expectedVersion': expectedVersion},
    );
  }
}
