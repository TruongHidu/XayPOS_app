import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/result/result.dart';
import '../../domain/entities/permission_catalog_item.dart';
import '../../domain/entities/staff_permission_config.dart';
import '../../domain/use_cases/get_permission_catalog.dart';
import '../../domain/use_cases/get_staff_permissions.dart';
import '../../domain/use_cases/update_staff_permissions.dart';

class StaffPermissionState {
  const StaffPermissionState({
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.successMessage,
    this.catalog = const [],
    this.config,
    this.localGrants = const {},
    this.localDenies = const {},
  });

  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final String? successMessage;
  final List<PermissionCatalogItem> catalog;
  final StaffPermissionConfig? config;
  final Set<String> localGrants;
  final Set<String> localDenies;

  StaffPermissionState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? Function()? errorMessage,
    String? Function()? successMessage,
    List<PermissionCatalogItem>? catalog,
    StaffPermissionConfig? config,
    Set<String>? localGrants,
    Set<String>? localDenies,
  }) {
    return StaffPermissionState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      successMessage: successMessage != null
          ? successMessage()
          : this.successMessage,
      catalog: catalog ?? this.catalog,
      config: config ?? this.config,
      localGrants: localGrants ?? this.localGrants,
      localDenies: localDenies ?? this.localDenies,
    );
  }

  /// Calculates effective permissions in real-time based on role permissions and local grants/denies:
  /// (rolePermissions + localGrants) - localDenies
  Set<String> get calculatedEffectivePermissions {
    if (config == null) return {};
    final base = config!.rolePermissions.toSet();
    base.addAll(localGrants);
    base.removeAll(localDenies);
    return base;
  }

  /// Permissions whose saved override differs from the current draft.
  Set<String> get changedCodes {
    if (config == null) return {};
    final grants = config!.grants.toSet();
    final denies = config!.denies.toSet();
    return {
      ...grants.difference(localGrants),
      ...localGrants.difference(grants),
      ...denies.difference(localDenies),
      ...localDenies.difference(denies),
    };
  }
}

class StaffPermissionController extends ChangeNotifier {
  StaffPermissionController({
    required GetPermissionCatalog getPermissionCatalog,
    required AppSession? Function() session,
    this.onAccessDenied,
    required GetStaffPermissions getStaffPermissions,
    required UpdateStaffPermissions updateStaffPermissions,
  }) : _session = session,
       _getPermissionCatalog = getPermissionCatalog,
       _getStaffPermissions = getStaffPermissions,
       _updateStaffPermissions = updateStaffPermissions;

  final AppSession? Function() _session;
  final Future<void> Function(Failure)? onAccessDenied;
  bool _disposed = false;
  int _generation = 0;
  String? _staffId;
  bool _ready = false;
  bool get canSave =>
      !_disposed &&
      _ready &&
      !_state.isLoading &&
      !_state.isSaving &&
      _state.config?.staffId == _staffId &&
      AccessPolicy.canManageStaff(
        _session(),
        'STAFF_PERMISSION_MANAGE',
        _staffId!,
        _state.config!.roleCode,
      );
  bool canGrant(String code) => _session()?.permissions.contains(code) ?? false;
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  Future<void> _handleFailure(Failure failure) async {
    if (const {
      FailureType.forbidden,
      FailureType.unauthorized,
      FailureType.featureNotEntitled,
      FailureType.subscriptionNotActive,
    }.contains(failure.type)) {
      _ready = false;
      await onAccessDenied?.call(failure);
    }
  }

  final GetPermissionCatalog _getPermissionCatalog;
  final GetStaffPermissions _getStaffPermissions;
  final UpdateStaffPermissions _updateStaffPermissions;

  StaffPermissionState _state = const StaffPermissionState();
  StaffPermissionState get state => _state;

  Future<void> load(String staffId) async {
    if (_disposed) return;
    final generation = ++_generation;
    _staffId = staffId;
    _ready = false;
    _state = const StaffPermissionState(isLoading: true);
    notifyListeners();
    if (!AccessPolicy.canStaff(_session(), 'STAFF_PERMISSION_MANAGE')) {
      _state = const StaffPermissionState(
        errorMessage: 'Không có quyền phân quyền nhân viên.',
      );
      notifyListeners();
      return;
    }
    final catalogResult = await _getPermissionCatalog();
    if (_disposed || generation != _generation) return;
    if (catalogResult is Error<List<PermissionCatalogItem>>) {
      _state = StaffPermissionState(
        errorMessage: catalogResult.failure.message,
      );
      notifyListeners();
      await _handleFailure(catalogResult.failure);
      return;
    }
    final permissionsResult = await _getStaffPermissions(staffId);
    if (_disposed || generation != _generation) return;
    if (permissionsResult is Error<StaffPermissionConfig>) {
      _state = StaffPermissionState(
        errorMessage: permissionsResult.failure.message,
      );
      notifyListeners();
      await _handleFailure(permissionsResult.failure);
      return;
    }
    final config = (permissionsResult as Success<StaffPermissionConfig>).value;
    if (config.staffId != staffId ||
        !AccessPolicy.canManageStaff(
          _session(),
          'STAFF_PERMISSION_MANAGE',
          staffId,
          config.roleCode,
        )) {
      _state = const StaffPermissionState(
        errorMessage: 'Dữ liệu hoặc đối tượng phân quyền không hợp lệ.',
      );
    } else {
      _ready = true;
      _state = StaffPermissionState(
        catalog: (catalogResult as Success<List<PermissionCatalogItem>>).value,
        config: config,
        localGrants: config.grants.toSet(),
        localDenies: config.denies.toSet(),
      );
    }
    notifyListeners();
  }

  /// Sets state for a given permission code:
  /// 'default' -> not in grants, not in denies
  /// 'grant' -> in grants, not in denies
  /// 'deny' -> not in grants, in denies
  void setPermissionState(String code, String mode) {
    if (!canSave ||
        !_state.catalog.any((p) => p.code == code) ||
        (mode == 'grant' && !canGrant(code))) {
      return;
    }
    final grants = Set<String>.from(_state.localGrants);
    final denies = Set<String>.from(_state.localDenies);

    switch (mode) {
      case 'grant':
        grants.add(code);
        denies.remove(code);
        break;
      case 'deny':
        denies.add(code);
        grants.remove(code);
        break;
      case 'default':
      default:
        grants.remove(code);
        denies.remove(code);
        break;
    }

    _state = _state.copyWith(
      localGrants: grants,
      localDenies: denies,
      successMessage: () => null,
    );
    notifyListeners();
  }

  bool isEnabled(String code) =>
      _state.calculatedEffectivePermissions.contains(code);

  /// Turning off is always allowed; turning on may need a grant the actor lacks.
  bool canToggle(String code) =>
      canSave &&
      (isEnabled(code) ||
          (_state.config?.rolePermissions.contains(code) ?? false) ||
          canGrant(code));

  /// The on/off view of grants and denies: matching the role clears the
  /// override, anything else becomes one.
  void setEnabled(String code, bool enabled) {
    if (!canToggle(code)) return;
    final inRole = _state.config!.rolePermissions.contains(code);
    setPermissionState(
      code,
      enabled == inRole
          ? 'default'
          : enabled
          ? 'grant'
          : 'deny',
    );
  }

  void setGroupEnabled(Iterable<String> codes, bool enabled) {
    for (final code in codes) {
      if (isEnabled(code) != enabled) setEnabled(code, enabled);
    }
  }

  void resetAllOverrides() {
    if (!canSave) return;
    _state = _state.copyWith(
      localGrants: {},
      localDenies: {},
      successMessage: () => null,
    );
    notifyListeners();
  }

  Future<String?> saveOverrides(String staffId) async {
    if (!canSave || _staffId != staffId) {
      return 'Chưa tải xong cấu hình đúng nhân viên hoặc không còn quyền lưu.';
    }
    final generation = _generation;
    _state = _state.copyWith(
      isSaving: true,
      errorMessage: () => null,
      successMessage: () => null,
    );
    notifyListeners();

    final result = await _updateStaffPermissions(
      staffId: staffId,
      grants: _state.localGrants.toList(),
      denies: _state.localDenies.toList(),
    );

    if (_disposed || generation != _generation) {
      return 'Phiên làm việc đã thay đổi.';
    }
    if (result is Success<StaffPermissionConfig> &&
        result.value.staffId != staffId) {
      _ready = false;
      _state = const StaffPermissionState(
        errorMessage: 'Dữ liệu phản hồi không đúng nhân viên.',
      );
      notifyListeners();
      return _state.errorMessage;
    }
    if (result is Success<StaffPermissionConfig>) {
      final updatedConfig = result.value;
      _state = _state.copyWith(
        isSaving: false,
        config: updatedConfig,
        localGrants: updatedConfig.grants.toSet(),
        localDenies: updatedConfig.denies.toSet(),
        successMessage: () => 'Cập nhật phân quyền thành công!',
      );
      notifyListeners();
      return null;
    } else if (result is Error<StaffPermissionConfig>) {
      _state = _state.copyWith(
        isSaving: false,
        errorMessage: () => result.failure.message,
      );
      notifyListeners();
      await _handleFailure(result.failure);
      return result.failure.message;
    }
    _state = _state.copyWith(isSaving: false);
    notifyListeners();
    return 'Lỗi không xác định';
  }
}
