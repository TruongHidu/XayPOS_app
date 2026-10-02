import 'package:dio/dio.dart';

import '../dto/paginated_staff_dto.dart';
import '../dto/permission_catalog_dto.dart';
import '../dto/staff_member_dto.dart';
import '../dto/staff_permission_config_dto.dart';
import '../dto/staff_role_dto.dart';

abstract interface class StaffRemoteDataSource {
  Future<PaginatedStaffDto> getStaffList({
    String? query,
    String? roleCode,
    bool? active,
    int page = 0,
    int size = 20,
    String sortBy = 'createdAt',
    String direction = 'desc',
  });

  Future<List<StaffRoleDto>> getAssignableRoles();

  Future<StaffMemberDto> getStaffDetail(String staffId);

  Future<StaffMemberDto> createStaff({
    required String name,
    required String email,
    String? phone,
    required String roleCode,
    required String initialPassword,
  });

  Future<StaffMemberDto> updateStaff({
    required String staffId,
    String? name,
    String? email,
    String? phone,
    String? roleCode,
  });

  Future<StaffMemberDto> toggleStaffStatus({
    required String staffId,
    required bool active,
    String? reason,
  });

  Future<List<PermissionCatalogDto>> getPermissionCatalog();

  Future<StaffPermissionConfigDto> getStaffPermissions(String staffId);

  Future<StaffPermissionConfigDto> updateStaffPermissions({
    required String staffId,
    required List<String> grants,
    required List<String> denies,
  });
}

class StaffRemoteDataSourceImpl implements StaffRemoteDataSource {
  const StaffRemoteDataSourceImpl(this._dio);

  final Dio _dio;

  @override
  Future<PaginatedStaffDto> getStaffList({
    String? query,
    String? roleCode,
    bool? active,
    int page = 0,
    int size = 20,
    String sortBy = 'createdAt',
    String direction = 'desc',
  }) async {
    final queryParams = <String, dynamic>{
      'page': page,
      'size': size,
      'sortBy': sortBy,
      'direction': direction,
    };
    if (query != null && query.trim().isNotEmpty) {
      queryParams['q'] = query.trim();
    }
    if (roleCode != null && roleCode.trim().isNotEmpty) {
      queryParams['roleCode'] = roleCode.trim();
    }
    if (active != null) {
      queryParams['active'] = active;
    }

    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/staff',
      queryParameters: queryParams,
    );

    return PaginatedStaffDto.fromJson(response.data!);
  }

  @override
  Future<List<StaffRoleDto>> getAssignableRoles() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/staff/roles');
    return (response.data!)
        .map((e) => StaffRoleDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<StaffMemberDto> getStaffDetail(String staffId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/staff/$staffId',
    );
    return StaffMemberDto.fromJson(response.data!);
  }

  @override
  Future<StaffMemberDto> createStaff({
    required String name,
    required String email,
    String? phone,
    required String roleCode,
    required String initialPassword,
  }) async {
    final body = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'roleCode': roleCode.trim(),
      'initialPassword': initialPassword,
    };
    if (phone != null && phone.trim().isNotEmpty) {
      body['phone'] = phone.trim();
    }

    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/staff',
      data: body,
    );
    return StaffMemberDto.fromJson(response.data!);
  }

  @override
  Future<StaffMemberDto> updateStaff({
    required String staffId,
    String? name,
    String? email,
    String? phone,
    String? roleCode,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name.trim();
    if (email != null) body['email'] = email.trim();
    if (phone != null) {
      body['phone'] = phone; // "" clears phone number according to spec
    }
    if (roleCode != null) body['roleCode'] = roleCode.trim();

    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/staff/$staffId',
      data: body,
    );
    return StaffMemberDto.fromJson(response.data!);
  }

  @override
  Future<StaffMemberDto> toggleStaffStatus({
    required String staffId,
    required bool active,
    String? reason,
  }) async {
    final body = <String, dynamic>{'active': active};
    if (!active && reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }

    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/staff/$staffId/status',
      data: body,
    );
    return StaffMemberDto.fromJson(response.data!);
  }

  @override
  Future<List<PermissionCatalogDto>> getPermissionCatalog() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/staff/permissions');
    return (response.data!)
        .map((e) => PermissionCatalogDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<StaffPermissionConfigDto> getStaffPermissions(String staffId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/staff/$staffId/permissions',
    );
    return StaffPermissionConfigDto.fromJson(response.data!);
  }

  @override
  Future<StaffPermissionConfigDto> updateStaffPermissions({
    required String staffId,
    required List<String> grants,
    required List<String> denies,
  }) async {
    final body = <String, dynamic>{'grants': grants, 'denies': denies};

    final response = await _dio.put<Map<String, dynamic>>(
      '/api/v1/staff/$staffId/permissions',
      data: body,
    );
    return StaffPermissionConfigDto.fromJson(response.data!);
  }
}
