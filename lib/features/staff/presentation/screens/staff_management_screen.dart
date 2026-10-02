import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../domain/entities/staff_member.dart';
import '../widgets/create_staff_dialog.dart';
import '../widgets/edit_staff_dialog.dart';
import '../widgets/staff_permission_dialog.dart';
import '../widgets/toggle_status_dialog.dart';

class StaffManagementScreen extends ConsumerWidget {
  const StaffManagementScreen({super.key});

  Future<void> _dialog(
    BuildContext context,
    WidgetRef ref,
    AppSession session,
    String permission,
    Widget child, {
    StaffMember? target,
  }) async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final current = ref.watch(authControllerProvider).state.session;
          final allowed = target == null
              ? AccessPolicy.canStaff(current, permission)
              : AccessPolicy.canManageStaff(
                  current,
                  permission,
                  target.id,
                  target.role.code,
                );
          if (AccessPolicy.staffScope(current) !=
                  AccessPolicy.staffScope(session) ||
              !allowed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            });
            return const SizedBox.shrink();
          }
          return child;
        },
      ),
    );
    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu thay đổi nhân viên.')),
      );
    }
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    StaffMember row,
    String action,
  ) async {
    final controller = ref.read(staffListControllerProvider);
    final session = ref.read(authControllerProvider).state.session;
    final staff = await controller.detail(row.id);
    if (!context.mounted ||
        AccessPolicy.staffScope(session) !=
            AccessPolicy.staffScope(
              ref.read(authControllerProvider).state.session,
            )) {
      return;
    }
    if (staff == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            controller.lastFailure?.message ??
                'Không thể tải chi tiết nhân viên.',
          ),
        ),
      );
      return;
    }
    final permission = switch (action) {
      'edit' => 'STAFF_UPDATE',
      'status' => 'STAFF_DISABLE',
      'permissions' => 'STAFF_PERMISSION_MANAGE',
      _ => 'STAFF_VIEW',
    };
    if (action != 'detail' &&
        !AccessPolicy.canManageStaff(
          session,
          permission,
          staff.id,
          staff.role.code,
        )) {
      return;
    }
    final child = switch (action) {
      'edit' => EditStaffDialog(
        staff: staff,
        roles: controller.state.roles,
        fieldErrors: () => controller.lastFailure?.fieldErrors ?? {},
        onSubmit: controller.editStaff,
      ),
      'status' => ToggleStatusDialog(
        staff: staff,
        fieldErrors: () => controller.lastFailure?.fieldErrors ?? {},
        onSubmit: controller.toggleStatus,
      ),
      'permissions' => StaffPermissionDialog(staff: staff),
      _ => AlertDialog(
        title: Text(staff.name),
        scrollable: true,
        content: Text(
          '${staff.email}\n${staff.phone ?? "—"}\n${staff.role.name}\n'
          '${staff.active ? "Hoạt động" : "Đã vô hiệu hóa"}\n'
          'Đăng nhập cuối: ${staff.lastLoginAt?.toLocal() ?? "—"}\n'
          'Ngày tạo: ${staff.createdAt.toLocal()}\nCập nhật: ${staff.updatedAt.toLocal()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    };
    await _dialog(
      context,
      ref,
      session!,
      permission,
      child,
      target: action == 'detail' ? null : staff,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canStaff(session, 'STAFF_VIEW')) {
      return const Center(
        child: Text('Bạn không có quyền truy cập quản lý nhân viên.'),
      );
    }
    final controller = ref.watch(staffListControllerProvider);
    final state = controller.state;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Quản lý nhân viên',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (AccessPolicy.canStaff(session, 'STAFF_CREATE'))
                FilledButton.icon(
                  onPressed: state.isRolesLoading || state.roles.isEmpty
                      ? null
                      : () => _dialog(
                          context,
                          ref,
                          session!,
                          'STAFF_CREATE',
                          CreateStaffDialog(
                            roles: state.roles,
                            fieldErrors: () =>
                                controller.lastFailure?.fieldErrors ?? {},
                            onSubmit: controller.addStaff,
                          ),
                        ),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Thêm nhân viên'),
                ),
              IconButton(
                onPressed: controller.loadInitial,
                icon: const Icon(Icons.refresh),
                tooltip: 'Tải lại',
              ),
            ],
          ),
          Text(
            'Giới hạn nhân viên hoạt động: ${session!.maxStaff ?? "Không giới hạn"} (không tính OWNER).',
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ObjectKey(controller),
            initialValue: state.query,
            decoration: const InputDecoration(
              labelText: 'Tìm tên, email, số điện thoại',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: controller.setSearchQuery,
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Bộ lọc và sắp xếp'),
            children: [
              DropdownButtonFormField<String>(
                value: state.selectedRoleCode ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Vai trò'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Tất cả vai trò'),
                  ),
                  if (state.selectedRoleCode != null &&
                      !state.roles.any((r) => r.code == state.selectedRoleCode))
                    DropdownMenuItem(
                      value: state.selectedRoleCode,
                      child: Text(state.selectedRoleCode!),
                    ),
                  ...state.roles.map(
                    (r) => DropdownMenuItem(value: r.code, child: Text(r.name)),
                  ),
                ],
                onChanged: (v) => controller.setRoleFilter(v == '' ? null : v),
              ),
              DropdownButtonFormField<String>(
                value: state.selectedActive?.toString() ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Trạng thái'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Tất cả trạng thái')),
                  DropdownMenuItem(value: 'true', child: Text('Hoạt động')),
                  DropdownMenuItem(
                    value: 'false',
                    child: Text('Đã vô hiệu hóa'),
                  ),
                ],
                onChanged: (v) =>
                    controller.setStatusFilter(v == '' ? null : v == 'true'),
              ),
              DropdownButtonFormField<String>(
                value: state.sortBy,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Sắp xếp theo'),
                items: const [
                  DropdownMenuItem(value: 'createdAt', child: Text('Ngày tạo')),
                  DropdownMenuItem(value: 'name', child: Text('Tên')),
                  DropdownMenuItem(value: 'email', child: Text('Email')),
                  DropdownMenuItem(
                    value: 'lastLoginAt',
                    child: Text('Đăng nhập cuối'),
                  ),
                ],
                onChanged: (v) => controller.setSorting(v!, state.direction),
              ),
              DropdownButtonFormField<String>(
                value: state.direction,
                decoration: const InputDecoration(labelText: 'Thứ tự'),
                items: const [
                  DropdownMenuItem(value: 'asc', child: Text('Tăng dần')),
                  DropdownMenuItem(value: 'desc', child: Text('Giảm dần')),
                ],
                onChanged: (v) => controller.setSorting(state.sortBy, v!),
              ),
              DropdownButtonFormField<int>(
                value: state.size,
                decoration: const InputDecoration(
                  labelText: 'Số dòng mỗi trang',
                ),
                items: [10, 20, 50, 100]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (v) => controller.setSize(v!),
              ),
            ],
          ),
          if (state.rolesError != null) ...[
            Text(
              state.rolesError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: controller.loadRoles,
              child: const Text('Tải lại vai trò'),
            ),
          ],
          if (state.errorMessage != null) ...[
            Text(
              state.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: controller.loadInitial,
              child: const Text('Thử lại'),
            ),
          ],
          if (state.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (state.staffList.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Không tìm thấy nhân viên nào.'),
            )
          else
            ...state.staffList.map(
              (staff) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        staff.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(staff.email),
                      Text(staff.phone ?? 'Chưa có số điện thoại'),
                      Text(
                        '${staff.role.name} • ${staff.active ? "Hoạt động" : "Đã vô hiệu hóa"}',
                      ),
                      Text(
                        'Đăng nhập cuối: ${staff.lastLoginAt?.toLocal() ?? "—"}',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () =>
                                _open(context, ref, staff, 'detail'),
                            child: const Text('Chi tiết'),
                          ),
                          if (AccessPolicy.canManageStaff(
                            session,
                            'STAFF_UPDATE',
                            staff.id,
                            staff.role.code,
                          ))
                            TextButton(
                              onPressed: state.roles.isEmpty
                                  ? null
                                  : () => _open(context, ref, staff, 'edit'),
                              child: const Text('Sửa'),
                            ),
                          if (AccessPolicy.canManageStaff(
                            session,
                            'STAFF_DISABLE',
                            staff.id,
                            staff.role.code,
                          ))
                            TextButton(
                              onPressed: () =>
                                  _open(context, ref, staff, 'status'),
                              child: Text(
                                staff.active ? 'Vô hiệu hóa' : 'Kích hoạt lại',
                              ),
                            ),
                          if (AccessPolicy.canManageStaff(
                            session,
                            'STAFF_PERMISSION_MANAGE',
                            staff.id,
                            staff.role.code,
                          ))
                            TextButton(
                              onPressed: () =>
                                  _open(context, ref, staff, 'permissions'),
                              child: const Text('Phân quyền'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Tổng ${state.totalElements} nhân viên • Trang ${state.page + 1}/${state.totalPages == 0 ? 1 : state.totalPages}',
              ),
              IconButton(
                onPressed: state.isLoading || state.page == 0
                    ? null
                    : () => controller.setPage(state.page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: state.isLoading || state.page >= state.totalPages - 1
                    ? null
                    : () => controller.setPage(state.page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
