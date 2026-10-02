import '../../../../core/result/result.dart';
import '../entities/paginated_staff_result.dart';
import '../entities/permission_catalog_item.dart';
import '../entities/staff_member.dart';
import '../entities/staff_permission_config.dart';
import '../entities/staff_role.dart';

abstract interface class StaffRepository {
  Future<Result<PaginatedStaffResult>> getStaffList({
    String? query,
    String? roleCode,
    bool? active,
    int page = 0,
    int size = 20,
    String sortBy = 'createdAt',
    String direction = 'desc',
  });

  Future<Result<List<StaffRole>>> getAssignableRoles();

  Future<Result<StaffMember>> getStaffDetail(String staffId);

  Future<Result<StaffMember>> createStaff({
    required String name,
    required String email,
    String? phone,
    required String roleCode,
    required String initialPassword,
  });

  Future<Result<StaffMember>> updateStaff({
    required String staffId,
    String? name,
    String? email,
    String? phone,
    String? roleCode,
  });

  Future<Result<StaffMember>> toggleStaffStatus({
    required String staffId,
    required bool active,
    String? reason,
  });

  Future<Result<List<PermissionCatalogItem>>> getPermissionCatalog();

  Future<Result<StaffPermissionConfig>> getStaffPermissions(String staffId);

  Future<Result<StaffPermissionConfig>> updateStaffPermissions({
    required String staffId,
    required List<String> grants,
    required List<String> denies,
  });
}
