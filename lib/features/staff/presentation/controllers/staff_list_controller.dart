import 'dart:async';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/use_cases/get_staff_detail.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/result/result.dart';
import '../../../../core/paging/endless_pages.dart';
import '../../domain/entities/paginated_staff_result.dart';
import '../../domain/entities/staff_member.dart';
import '../../domain/entities/staff_role.dart';
import '../../domain/use_cases/create_staff.dart';
import '../../domain/use_cases/get_assignable_roles.dart';
import '../../domain/use_cases/get_staff_list.dart';
import '../../domain/use_cases/toggle_staff_status.dart';
import '../../domain/use_cases/update_staff.dart';

class StaffListState {
  const StaffListState({
    this.isLoading = false,
    this.isRolesLoading = false,
    this.errorMessage,
    this.rolesError,
    this.staffList = const [],
    this.roles = const [],
    this.page = 0,
    this.size = 20,
    this.totalElements = 0,
    this.totalPages = 0,
    this.query = '',
    this.selectedRoleCode,
    this.selectedActive,
    this.sortBy = 'createdAt',
    this.direction = 'desc',
  });

  final bool isLoading;
  final bool isRolesLoading;
  final String? errorMessage;
  final String? rolesError;
  final List<StaffMember> staffList;
  final List<StaffRole> roles;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
  final String query;
  final String? selectedRoleCode;
  final bool? selectedActive;
  final String sortBy;
  final String direction;

  StaffListState copyWith({
    bool? isLoading,
    bool? isRolesLoading,
    String? Function()? errorMessage,
    String? Function()? rolesError,
    List<StaffMember>? staffList,
    List<StaffRole>? roles,
    int? page,
    int? size,
    int? totalElements,
    int? totalPages,
    String? query,
    String? Function()? selectedRoleCode,
    bool? Function()? selectedActive,
    String? sortBy,
    String? direction,
  }) {
    return StaffListState(
      isLoading: isLoading ?? this.isLoading,
      isRolesLoading: isRolesLoading ?? this.isRolesLoading,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      rolesError: rolesError != null ? rolesError() : this.rolesError,
      staffList: staffList ?? this.staffList,
      roles: roles ?? this.roles,
      page: page ?? this.page,
      size: size ?? this.size,
      totalElements: totalElements ?? this.totalElements,
      totalPages: totalPages ?? this.totalPages,
      query: query ?? this.query,
      selectedRoleCode: selectedRoleCode != null
          ? selectedRoleCode()
          : this.selectedRoleCode,
      selectedActive: selectedActive != null
          ? selectedActive()
          : this.selectedActive,
      sortBy: sortBy ?? this.sortBy,
      direction: direction ?? this.direction,
    );
  }
}

class StaffListController extends ChangeNotifier {
  StaffListController({
    required GetStaffList getStaffList,
    required AppSession? Function() session,
    required GetStaffDetail getStaffDetail,
    this.onAccessDenied,
    required GetAssignableRoles getAssignableRoles,
    required CreateStaff createStaff,
    required UpdateStaff updateStaff,
    required ToggleStaffStatus toggleStaffStatus,
  }) : _session = session,
       _getStaffDetail = getStaffDetail,
       _getStaffList = getStaffList,
       _getAssignableRoles = getAssignableRoles,
       _createStaff = createStaff,
       _updateStaff = updateStaff,
       _toggleStaffStatus = toggleStaffStatus;

  final AppSession? Function() _session;
  final GetStaffDetail _getStaffDetail;
  final Future<void> Function(Failure)? onAccessDenied;
  bool _disposed = false;
  int _request = 0;
  int _rolesRequest = 0;
  Timer? _debounce;
  Failure? lastFailure;
  bool _allowed(String permission) =>
      !_disposed && AccessPolicy.canStaff(_session(), permission);
  Future<String> _failure(Failure failure) async {
    lastFailure = failure;
    if (const {
      FailureType.forbidden,
      FailureType.unauthorized,
      FailureType.featureNotEntitled,
      FailureType.subscriptionNotActive,
    }.contains(failure.type)) {
      await onAccessDenied?.call(failure);
    }
    return failure.message;
  }

  Future<StaffMember?> detail(String id) async {
    if (!_allowed('STAFF_VIEW')) return null;
    lastFailure = null;
    final result = await _getStaffDetail(id);
    if (_disposed) return null;
    if (result is Success<StaffMember>) return result.value;
    if (result is Error<StaffMember>) await _failure(result.failure);
    return null;
  }

  Future<bool> _target(String permission, String id) async {
    if (!_allowed(permission)) return false;
    final staff = await detail(id);
    return !_disposed &&
        staff != null &&
        AccessPolicy.canManageStaff(
          _session(),
          permission,
          id,
          staff.role.code,
        );
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _rolesRequest++;
    _debounce?.cancel();
    super.dispose();
  }

  final GetStaffList _getStaffList;
  final GetAssignableRoles _getAssignableRoles;
  final CreateStaff _createStaff;
  final UpdateStaff _updateStaff;
  final ToggleStaffStatus _toggleStaffStatus;

  StaffListState _state = const StaffListState();
  StaffListState get state => _state;
  final endless = EndlessPages<StaffMember>((staff) => staff.id);

  Future<void> loadInitial() async {
    await Future.wait([loadRoles(), loadStaffList(resetPage: true)]);
  }

  Future<void> loadRoles() async {
    if (!_allowed('STAFF_VIEW')) return;
    final request = ++_rolesRequest;
    _state = _state.copyWith(isRolesLoading: true, rolesError: () => null);
    notifyListeners();

    final result = await _getAssignableRoles();
    if (_disposed || request != _rolesRequest) return;
    if (result is Success<List<StaffRole>>) {
      _state = _state.copyWith(
        isRolesLoading: false,
        roles: result.value
            .where((r) => AccessPolicy.canAssignStaffRole(_session(), r.code))
            .toList(),
      );
    } else if (result is Error<List<StaffRole>>) {
      final message = await _failure(result.failure);
      if (_disposed) return;
      _state = _state.copyWith(
        isRolesLoading: false,
        rolesError: () => message,
        roles: [],
      );
    }
    notifyListeners();
  }

  Future<void> loadStaffList({bool resetPage = false}) async {
    if (!_allowed('STAFF_VIEW')) return;
    _debounce?.cancel();
    final request = ++_request;
    final targetPage = resetPage ? 0 : _state.page;
    _state = _state.copyWith(
      isLoading: true,
      errorMessage: () => null,
      page: targetPage,
    );
    notifyListeners();

    final result = await endless.read(
      page: targetPage,
      fetch: _fetchPage,
      content: (data) => data.content,
      totalPages: (data) => data.totalPages,
      active: () => !_disposed && request == _request,
    );

    if (_disposed || request != _request) return;
    if (result is Success<EndlessRead<StaffMember, PaginatedStaffResult>>) {
      final pages = result.value;
      final data = pages.last;
      if (pages.rows.isEmpty && targetPage > 0) {
        _state = _state.copyWith(
          page: data.totalPages > 0 ? data.totalPages - 1 : 0,
        );
        await loadStaffList();
        return;
      }
      _state = _state.copyWith(
        isLoading: false,
        staffList: pages.rows,
        page: data.page,
        size: data.size,
        totalElements: data.totalElements,
        totalPages: data.totalPages,
      );
    } else if (result case Error(failure: final failure)) {
      final message = await _failure(failure);
      if (_disposed || request != _request) return;
      _state = _state.copyWith(isLoading: false, errorMessage: () => message);
    }
    notifyListeners();
  }

  /// Appends the next page; a failure keeps the staff already shown.
  Future<void> loadMore() async {
    if (!_allowed('STAFF_VIEW') ||
        _state.isLoading ||
        endless.loadingMore ||
        _state.page >= _state.totalPages - 1) {
      return;
    }
    final request = ++_request;
    endless.begin();
    notifyListeners();
    final result = await _fetchPage(_state.page + 1);
    if (_disposed || request != _request) return;
    switch (result) {
      case Success(value: final data):
        _state = _state.copyWith(
          staffList: endless.append(_state.staffList, data.content),
          page: data.page,
          totalElements: data.totalElements,
          totalPages: data.totalPages,
        );
      case Error(failure: final failure):
        await _failure(failure);
        if (_disposed || request != _request) return;
        endless.fail(failure);
    }
    notifyListeners();
  }

  Future<Result<PaginatedStaffResult>> _fetchPage(int page) => _getStaffList(
    query: _state.query.isEmpty ? null : _state.query,
    roleCode: _state.selectedRoleCode,
    active: _state.selectedActive,
    page: page,
    size: _state.size,
    sortBy: _state.sortBy,
    direction: _state.direction,
  );

  void setSearchQuery(String query) {
    if (_state.query == query) return;
    _request++;
    _debounce?.cancel();
    _state = _state.copyWith(query: query, page: 0, isLoading: true);
    notifyListeners();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => loadStaffList(resetPage: true),
    );
  }

  void setRoleFilter(String? roleCode) {
    if (_state.selectedRoleCode == roleCode) return;
    _state = _state.copyWith(selectedRoleCode: () => roleCode);
    loadStaffList(resetPage: true);
  }

  void setStatusFilter(bool? active) {
    if (_state.selectedActive == active) return;
    _state = _state.copyWith(selectedActive: () => active);
    loadStaffList(resetPage: true);
  }

  void setSorting(String sortBy, String direction) {
    if (!const {'createdAt', 'name', 'email', 'lastLoginAt'}.contains(sortBy) ||
        !const {'asc', 'desc'}.contains(direction)) {
      return;
    }
    _state = _state.copyWith(sortBy: sortBy, direction: direction);
    loadStaffList(resetPage: true);
  }

  void setSize(int size) {
    if (size < 1 || size > 100) return;
    _state = _state.copyWith(size: size);
    loadStaffList(resetPage: true);
  }

  void setPage(int page) {
    if (page < 0 || page >= _state.totalPages && _state.totalPages > 0) return;
    _state = _state.copyWith(page: page);
    loadStaffList(resetPage: false);
  }

  Future<String?> addStaff({
    required String name,
    required String email,
    String? phone,
    required String roleCode,
    required String initialPassword,
  }) async {
    lastFailure = null;
    if (!_allowed('STAFF_CREATE') ||
        !AccessPolicy.canAssignStaffRole(_session(), roleCode) ||
        !_state.roles.any((r) => r.code == roleCode)) {
      return 'Không có quyền tạo nhân viên với vai trò này.';
    }
    if (name.trim().isEmpty ||
        name.trim().length > 150 ||
        email.length > 254 ||
        (phone?.length ?? 0) > 30 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        initialPassword.length < 8 ||
        initialPassword.length > 100) {
      return 'Thông tin nhân viên không hợp lệ.';
    }
    final result = await _createStaff(
      name: name,
      email: email,
      phone: phone,
      roleCode: roleCode,
      initialPassword: initialPassword,
    );

    if (_disposed) return 'Phiên làm việc đã thay đổi.';
    if (result is Success<StaffMember>) {
      await loadStaffList();
      return null; // Success, return no error
    } else if (result is Error<StaffMember>) {
      return _failure(result.failure);
    }
    return 'Lỗi không xác định';
  }

  Future<String?> editStaff({
    required String staffId,
    String? name,
    String? email,
    String? phone,
    String? roleCode,
  }) async {
    lastFailure = null;
    if (!await _target('STAFF_UPDATE', staffId)) {
      return lastFailure?.message ?? 'Không có quyền sửa nhân viên này.';
    }
    if (roleCode != null &&
        (!AccessPolicy.canAssignStaffRole(_session(), roleCode) ||
            !_state.roles.any((r) => r.code == roleCode))) {
      return 'Vai trò không hợp lệ.';
    }
    if (name == null && email == null && phone == null && roleCode == null) {
      return 'Chưa có thay đổi để lưu.';
    }
    if ((name != null && (name.trim().isEmpty || name.trim().length > 150)) ||
        (email != null &&
            (email.length > 254 ||
                !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email))) ||
        (phone?.length ?? 0) > 30) {
      return 'Thông tin nhân viên không hợp lệ.';
    }
    final result = await _updateStaff(
      staffId: staffId,
      name: name,
      email: email,
      phone: phone,
      roleCode: roleCode,
    );

    if (_disposed) return 'Phiên làm việc đã thay đổi.';
    if (result is Success<StaffMember>) {
      await loadStaffList();
      return null;
    } else if (result is Error<StaffMember>) {
      return _failure(result.failure);
    }
    return 'Lỗi không xác định';
  }

  Future<String?> toggleStatus({
    required String staffId,
    required bool active,
    String? reason,
  }) async {
    lastFailure = null;
    if (!await _target('STAFF_DISABLE', staffId)) {
      return lastFailure?.message ??
          'Không có quyền đổi trạng thái nhân viên này.';
    }
    if (!active &&
        (reason == null || reason.trim().isEmpty || reason.length > 500)) {
      return 'Lý do bắt buộc, tối đa 500 ký tự.';
    }
    final result = await _toggleStaffStatus(
      staffId: staffId,
      active: active,
      reason: reason,
    );

    if (_disposed) return 'Phiên làm việc đã thay đổi.';
    if (result is Success<StaffMember>) {
      await loadStaffList();
      return null;
    } else if (result is Error<StaffMember>) {
      return _failure(result.failure);
    }
    return 'Lỗi không xác định';
  }
}
