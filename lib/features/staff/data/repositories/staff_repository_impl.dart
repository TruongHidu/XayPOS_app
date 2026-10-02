import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/paginated_staff_result.dart';
import '../../domain/entities/permission_catalog_item.dart';
import '../../domain/entities/staff_member.dart';
import '../../domain/entities/staff_permission_config.dart';
import '../../domain/entities/staff_role.dart';
import '../../domain/repositories/staff_repository.dart';
import '../data_sources/staff_remote_data_source.dart';

class StaffRepositoryImpl implements StaffRepository {
  const StaffRepositoryImpl(this._remoteDataSource);

  final StaffRemoteDataSource _remoteDataSource;

  @override
  Future<Result<PaginatedStaffResult>> getStaffList({
    String? query,
    String? roleCode,
    bool? active,
    int page = 0,
    int size = 20,
    String sortBy = 'createdAt',
    String direction = 'desc',
  }) async {
    try {
      final dto = await _remoteDataSource.getStaffList(
        query: query,
        roleCode: roleCode,
        active: active,
        page: page,
        size: size,
        sortBy: sortBy,
        direction: direction,
      );
      return Success(dto.toEntity());
    } catch (e) {
      return Error(ApiErrorMapper.fromException(e));
    }
  }

  @override
  Future<Result<List<StaffRole>>> getAssignableRoles() async {
    try {
      final dtos = await _remoteDataSource.getAssignableRoles();
      return Success(dtos.map((d) => d.toEntity()).toList());
    } catch (e) {
      return Error(ApiErrorMapper.fromException(e));
    }
  }

  @override
  Future<Result<StaffMember>> getStaffDetail(String staffId) async {
    try {
      final dto = await _remoteDataSource.getStaffDetail(staffId);
      return Success(dto.toEntity());
    } catch (e) {
      return Error(ApiErrorMapper.fromException(e));
    }
  }

  @override
  Future<Result<StaffMember>> createStaff({
    required String name,
    required String email,
    String? phone,
    required String roleCode,
    required String initialPassword,
  }) async {
    try {
      final dto = await _remoteDataSource.createStaff(
        name: name,
        email: email,
        phone: phone,
        roleCode: roleCode,
        initialPassword: initialPassword,
      );
      return Success(dto.toEntity());
    } catch (e) {
      return Error(ApiErrorMapper.fromException(e));
    }
  }

  @override
  Future<Result<StaffMember>> updateStaff({
    required String staffId,
    String? name,
    String? email,
    String? phone,
    String? roleCode,
  }) async {
    try {
      final dto = await _remoteDataSource.updateStaff(
        staffId: staffId,
        name: name,
        email: email,
        phone: phone,
        roleCode: roleCode,
      );
      return Success(dto.toEntity());
    } catch (e) {
      return Error(ApiErrorMapper.fromException(e));
    }
  }

  @override
  Future<Result<StaffMember>> toggleStaffStatus({
    required String staffId,
    required bool active,
    String? reason,
  }) async {
    try {
      final dto = await _remoteDataSource.toggleStaffStatus(
        staffId: staffId,
        active: active,
        reason: reason,
      );
      return Success(dto.toEntity());
    } catch (e) {
      return Error(ApiErrorMapper.fromException(e));
    }
  }

  @override
  Future<Result<List<PermissionCatalogItem>>> getPermissionCatalog() async {
    try {
      final dtos = await _remoteDataSource.getPermissionCatalog();
      return Success(dtos.map((d) => d.toEntity()).toList());
    } catch (e) {
      return Error(ApiErrorMapper.fromException(e));
    }
  }

  @override
  Future<Result<StaffPermissionConfig>> getStaffPermissions(
    String staffId,
  ) async {
    try {
      final dto = await _remoteDataSource.getStaffPermissions(staffId);
      return Success(dto.toEntity());
    } catch (e) {
      return Error(ApiErrorMapper.fromException(e));
    }
  }

  @override
  Future<Result<StaffPermissionConfig>> updateStaffPermissions({
    required String staffId,
    required List<String> grants,
    required List<String> denies,
  }) async {
    try {
      final dto = await _remoteDataSource.updateStaffPermissions(
        staffId: staffId,
        grants: grants,
        denies: denies,
      );
      return Success(dto.toEntity());
    } catch (e) {
      return Error(ApiErrorMapper.fromException(e));
    }
  }
}
