import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
export 'realtime_providers.dart';

export '../features/menu/presentation/providers/menu_providers.dart';
export '../features/tables/presentation/providers/tables_providers.dart';
export '../features/order/presentation/providers/order_providers.dart';
export '../features/qr_order/presentation/providers/qr_request_providers.dart';
export '../features/inventory/presentation/providers/inventory_providers.dart';
export '../features/inventory/presentation/providers/inventory_low_stock_count_providers.dart';
export '../features/inventory/presentation/providers/stock_document_providers.dart';
export '../features/inventory/presentation/providers/inventory_alert_providers.dart';
export '../features/inventory/presentation/providers/inventory_alert_notice_providers.dart';
export '../features/inventory/presentation/providers/inventory_alert_polling_providers.dart';
export '../features/inventory/presentation/providers/stock_audit_providers.dart';
export '../features/reports/presentation/providers/report_providers.dart';

import '../core/auth/session_events.dart';
import '../core/auth/access_policy.dart';
import '../core/network/api_client.dart';
import '../core/storage/secure_token_storage.dart';
import '../core/storage/token_storage.dart';
import '../features/auth/data/data_sources/auth_local_data_source.dart';
import '../features/auth/data/data_sources/auth_remote_data_source.dart';
import '../features/auth/data/repositories/auth_repository_impl.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/auth/domain/use_cases/login_use_case.dart';
import '../features/auth/domain/use_cases/logout.dart';
import '../features/auth/domain/use_cases/restore_session.dart';
import '../features/auth/presentation/controllers/auth_controller.dart';
import '../features/staff/data/data_sources/staff_remote_data_source.dart';
import '../features/staff/data/repositories/staff_repository_impl.dart';
import '../features/staff/domain/repositories/staff_repository.dart';
import '../features/staff/domain/use_cases/create_staff.dart';
import '../features/staff/domain/use_cases/get_assignable_roles.dart';
import '../features/staff/domain/use_cases/get_permission_catalog.dart';
import '../features/staff/domain/use_cases/get_staff_detail.dart';
import '../features/staff/domain/use_cases/get_staff_list.dart';
import '../features/staff/domain/use_cases/get_staff_permissions.dart';
import '../features/staff/domain/use_cases/toggle_staff_status.dart';
import '../features/staff/domain/use_cases/update_staff.dart';
import '../features/staff/domain/use_cases/update_staff_permissions.dart';
import '../features/staff/presentation/controllers/staff_list_controller.dart';
import '../features/staff/presentation/controllers/staff_permission_controller.dart';
import '../features/subscription/data/data_sources/entitlement_remote_data_source.dart';
import '../features/subscription/data/repositories/entitlement_repository_impl.dart';
import '../features/subscription/domain/repositories/entitlement_repository.dart';
import '../features/subscription/domain/use_cases/get_current_entitlements.dart';

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(),
);

final sessionEventsProvider = Provider<SessionEvents>((ref) {
  final events = SessionEvents();
  ref.onDispose(events.dispose);
  return events;
});

final apiClientsProvider = Provider<ApiClients>((ref) {
  return ApiClients(
    tokenStorage: ref.watch(tokenStorageProvider),
    sessionEvents: ref.watch(sessionEventsProvider),
  );
});

final authLocalDataSourceProvider = Provider<AuthLocalDataSource>((ref) {
  return AuthLocalDataSourceImpl(ref.watch(tokenStorageProvider));
});

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSourceImpl(ref.watch(apiClientsProvider).authenticated);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    remote: ref.watch(authRemoteDataSourceProvider),
    local: ref.watch(authLocalDataSourceProvider),
    refreshCoordinator: ref.watch(apiClientsProvider).refreshCoordinator,
    sessionEvents: ref.watch(sessionEventsProvider),
  );
});

final entitlementRepositoryProvider = Provider<EntitlementRepository>((ref) {
  final remote = EntitlementRemoteDataSourceImpl(
    ref.watch(apiClientsProvider).authenticated,
  );
  return EntitlementRepositoryImpl(remote);
});

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  final controller = AuthController(
    login: LoginUseCase(repository),
    restoreSession: RestoreSession(repository),
    logout: Logout(repository),
    getEntitlements: GetCurrentEntitlements(
      ref.watch(entitlementRepositoryProvider),
    ),
    sessionEvents: ref.watch(sessionEventsProvider),
  );
  Future.microtask(controller.restore);
  return controller;
});

// ── Staff Management Providers ─────────────────────────────

final staffRemoteDataSourceProvider = Provider<StaffRemoteDataSource>((ref) {
  return StaffRemoteDataSourceImpl(ref.watch(apiClientsProvider).authenticated);
});

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepositoryImpl(ref.watch(staffRemoteDataSourceProvider));
});

final getStaffListUseCaseProvider = Provider<GetStaffList>((ref) {
  return GetStaffList(ref.watch(staffRepositoryProvider));
});

final getAssignableRolesUseCaseProvider = Provider<GetAssignableRoles>((ref) {
  return GetAssignableRoles(ref.watch(staffRepositoryProvider));
});

final getStaffDetailUseCaseProvider = Provider<GetStaffDetail>((ref) {
  return GetStaffDetail(ref.watch(staffRepositoryProvider));
});

final createStaffUseCaseProvider = Provider<CreateStaff>((ref) {
  return CreateStaff(ref.watch(staffRepositoryProvider));
});

final updateStaffUseCaseProvider = Provider<UpdateStaff>((ref) {
  return UpdateStaff(ref.watch(staffRepositoryProvider));
});

final toggleStaffStatusUseCaseProvider = Provider<ToggleStaffStatus>((ref) {
  return ToggleStaffStatus(ref.watch(staffRepositoryProvider));
});

final getPermissionCatalogUseCaseProvider = Provider<GetPermissionCatalog>((
  ref,
) {
  return GetPermissionCatalog(ref.watch(staffRepositoryProvider));
});

final getStaffPermissionsUseCaseProvider = Provider<GetStaffPermissions>((ref) {
  return GetStaffPermissions(ref.watch(staffRepositoryProvider));
});

final updateStaffPermissionsUseCaseProvider = Provider<UpdateStaffPermissions>((
  ref,
) {
  return UpdateStaffPermissions(ref.watch(staffRepositoryProvider));
});

final staffNoticeProvider = StateProvider<String?>((ref) => null);

final staffListControllerProvider = ChangeNotifierProvider<StaffListController>(
  (ref) {
    ref.watch(
      authControllerProvider.select(
        (c) => AccessPolicy.staffScope(c.state.session),
      ),
    );
    final auth = ref.read(authControllerProvider);
    final controller = StaffListController(
      session: () => auth.state.session,
      getStaffDetail: ref.watch(getStaffDetailUseCaseProvider),
      onAccessDenied: (failure) async {
        ref.read(staffNoticeProvider.notifier).state = failure.message;
        await auth.restore();
      },
      getStaffList: ref.watch(getStaffListUseCaseProvider),
      getAssignableRoles: ref.watch(getAssignableRolesUseCaseProvider),
      createStaff: ref.watch(createStaffUseCaseProvider),
      updateStaff: ref.watch(updateStaffUseCaseProvider),
      toggleStaffStatus: ref.watch(toggleStaffStatusUseCaseProvider),
    );
    Future.microtask(controller.loadInitial);
    return controller;
  },
);

final staffPermissionControllerProvider =
    ChangeNotifierProvider<StaffPermissionController>((ref) {
      ref.watch(
        authControllerProvider.select(
          (c) => AccessPolicy.staffScope(c.state.session),
        ),
      );
      final auth = ref.read(authControllerProvider);
      return StaffPermissionController(
        session: () => auth.state.session,
        onAccessDenied: (failure) async {
          ref.read(staffNoticeProvider.notifier).state = failure.message;
          await auth.restore();
        },
        getPermissionCatalog: ref.watch(getPermissionCatalogUseCaseProvider),
        getStaffPermissions: ref.watch(getStaffPermissionsUseCaseProvider),
        updateStaffPermissions: ref.watch(
          updateStaffPermissionsUseCaseProvider,
        ),
      );
    });
