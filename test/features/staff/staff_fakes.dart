import 'dart:async';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/staff/domain/entities/paginated_staff_result.dart';
import 'package:pos_saas_app/features/staff/domain/entities/permission_catalog_item.dart';
import 'package:pos_saas_app/features/staff/domain/entities/staff_member.dart';
import 'package:pos_saas_app/features/staff/domain/entities/staff_permission_config.dart';
import 'package:pos_saas_app/features/staff/domain/entities/staff_role.dart';
import 'package:pos_saas_app/features/staff/domain/repositories/staff_repository.dart';
import 'package:pos_saas_app/features/staff/domain/use_cases/create_staff.dart';
import 'package:pos_saas_app/features/staff/domain/use_cases/get_assignable_roles.dart';
import 'package:pos_saas_app/features/staff/domain/use_cases/get_staff_detail.dart';
import 'package:pos_saas_app/features/staff/domain/use_cases/get_staff_list.dart';
import 'package:pos_saas_app/features/staff/domain/use_cases/get_permission_catalog.dart';
import 'package:pos_saas_app/features/staff/domain/use_cases/get_staff_permissions.dart';
import 'package:pos_saas_app/features/staff/domain/use_cases/update_staff_permissions.dart';
import 'package:pos_saas_app/features/staff/domain/use_cases/update_staff.dart';
import 'package:pos_saas_app/features/staff/domain/use_cases/toggle_staff_status.dart';
import 'package:pos_saas_app/features/staff/presentation/controllers/staff_list_controller.dart';
import 'package:pos_saas_app/features/staff/presentation/controllers/staff_permission_controller.dart';
import '../../helpers/auth_fakes.dart';

const staffPermissions = {
  'STAFF_VIEW',
  'STAFF_CREATE',
  'STAFF_UPDATE',
  'STAFF_DISABLE',
  'STAFF_PERMISSION_MANAGE',
  'ORDER_CANCEL',
};
const staffFeatures = {'STAFF_MANAGEMENT', 'STAFF_PERMISSION'};
AppSession staffSession() =>
    makeAppSession(permissions: staffPermissions, features: staffFeatures);
const waiterRole = StaffRole(id: 'role', code: 'WAITER', name: 'Waiter');
StaffMember member([String id = 'A']) => StaffMember(
  id: id,
  name: 'Alice',
  email: 'alice@example.com',
  active: true,
  role: waiterRole,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
StaffPermissionConfig config(
  String id, {
  List<String> grants = const [],
  List<String> denies = const [],
}) => StaffPermissionConfig(
  staffId: id,
  roleCode: 'WAITER',
  rolePermissions: ['ORDER_VIEW'],
  grants: grants,
  denies: denies,
  effectivePermissions: ({'ORDER_VIEW', ...grants}..removeAll(denies)).toList(),
);
PaginatedStaffResult page(String id, {int page = 0}) => PaginatedStaffResult(
  content: [member(id)],
  page: page,
  size: 20,
  totalElements: 40,
  totalPages: 2,
);

class FakeStaffRepository implements StaffRepository {
  bool delayedList = false;
  bool delayedPermissions = false;
  final lists = <Completer<Result<PaginatedStaffResult>>>[];
  final queries = <Map<String, Object?>>[];
  final configs = <String, Completer<Result<StaffPermissionConfig>>>{};
  Result<List<PermissionCatalogItem>> catalog = const Success([
    PermissionCatalogItem(
      code: 'ORDER_CANCEL',
      module: 'ORDER',
      name: 'Cancel order',
    ),
    PermissionCatalogItem(
      code: 'ORDER_VIEW',
      module: 'ORDER',
      name: 'View order',
    ),
  ]);
  Result<StaffPermissionConfig>? putResult;
  List<String>? savedGrants;
  List<String>? savedDenies;
  String? savedId;
  int creates = 0, updates = 0, statuses = 0;
  Map<String, Object?>? patch;
  @override
  Future<Result<PaginatedStaffResult>> getStaffList({
    String? query,
    String? roleCode,
    bool? active,
    int page = 0,
    int size = 20,
    String sortBy = 'createdAt',
    String direction = 'desc',
  }) {
    queries.add({
      'q': query,
      'roleCode': roleCode,
      'active': active,
      'page': page,
      'size': size,
      'sortBy': sortBy,
      'direction': direction,
    });
    if (!delayedList) {
      return Future.value(
        Success(
          PaginatedStaffResult(
            content: [member()],
            page: page,
            size: size,
            totalElements: 40,
            totalPages: 2,
          ),
        ),
      );
    }
    final c = Completer<Result<PaginatedStaffResult>>();
    lists.add(c);
    return c.future;
  }

  @override
  Future<Result<List<StaffRole>>> getAssignableRoles() async =>
      const Success([waiterRole]);
  @override
  Future<Result<StaffMember>> getStaffDetail(String id) async =>
      Success(member(id));
  @override
  Future<Result<StaffMember>> createStaff({
    required String name,
    required String email,
    String? phone,
    required String roleCode,
    required String initialPassword,
  }) async {
    creates++;
    return Success(member());
  }

  @override
  Future<Result<StaffMember>> updateStaff({
    required String staffId,
    String? name,
    String? email,
    String? phone,
    String? roleCode,
  }) async {
    updates++;
    patch = {
      'name': name,
      'email': email,
      'phone': phone,
      'roleCode': roleCode,
    };
    return Success(member(staffId));
  }

  @override
  Future<Result<StaffMember>> toggleStaffStatus({
    required String staffId,
    required bool active,
    String? reason,
  }) async {
    statuses++;
    return Success(member(staffId));
  }

  @override
  Future<Result<List<PermissionCatalogItem>>> getPermissionCatalog() async =>
      catalog;
  @override
  Future<Result<StaffPermissionConfig>> getStaffPermissions(String id) {
    if (!delayedPermissions) return Future.value(Success(config(id)));
    return (configs[id] = Completer<Result<StaffPermissionConfig>>()).future;
  }

  @override
  Future<Result<StaffPermissionConfig>> updateStaffPermissions({
    required String staffId,
    required List<String> grants,
    required List<String> denies,
  }) async {
    savedId = staffId;
    savedGrants = grants;
    savedDenies = denies;
    return putResult ??
        Success(config(staffId, grants: grants, denies: denies));
  }
}

StaffListController listController(
  FakeStaffRepository r, {
  AppSession? Function()? session,
}) => StaffListController(
  session: session ?? staffSession,
  getStaffDetail: GetStaffDetail(r),
  getStaffList: GetStaffList(r),
  getAssignableRoles: GetAssignableRoles(r),
  createStaff: CreateStaff(r),
  updateStaff: UpdateStaff(r),
  toggleStaffStatus: ToggleStaffStatus(r),
);
StaffPermissionController permissionController(FakeStaffRepository r) =>
    StaffPermissionController(
      session: staffSession,
      getPermissionCatalog: GetPermissionCatalog(r),
      getStaffPermissions: GetStaffPermissions(r),
      updateStaffPermissions: UpdateStaffPermissions(r),
    );
