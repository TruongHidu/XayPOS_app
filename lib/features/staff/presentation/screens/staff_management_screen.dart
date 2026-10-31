import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../domain/entities/staff_member.dart';
import '../widgets/create_staff_dialog.dart';
import '../widgets/staff_filter_panel.dart';
import '../widgets/staff_member_card.dart';
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
      _ => ResponsiveDialog(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                staff.name,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Thông tin nhân viên',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 20),
              ResponsiveColumns(
                children: [
                  _StaffDetailField(label: 'Email', value: staff.email),
                  _StaffDetailField(
                    label: 'Số điện thoại',
                    value: staff.phone ?? 'Chưa có số điện thoại',
                  ),
                  _StaffDetailField(label: 'Vai trò', value: staff.role.name),
                  _StaffDetailField(
                    label: 'Trạng thái',
                    value: staff.active ? 'Hoạt động' : 'Đã vô hiệu hóa',
                  ),
                  _StaffDetailField(
                    label: 'Đăng nhập cuối',
                    value: _formatDate(staff.lastLoginAt),
                  ),
                  _StaffDetailField(
                    label: 'Ngày tạo',
                    value: _formatDate(staff.createdAt),
                  ),
                  _StaffDetailField(
                    label: 'Cập nhật',
                    value: _formatDate(staff.updatedAt),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                  child: const Text('Đóng'),
                ),
              ),
            ],
          ),
        ),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLow,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quản lý nhân viên',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Thông tin, vai trò và quyền truy cập của đội ngũ.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
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
                  IconButton.outlined(
                    onPressed: controller.loadInitial,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Tải lại',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _StaffNotice(
            icon: Icons.info_outline_rounded,
            message:
                'Giới hạn nhân viên hoạt động: ${session!.maxStaff ?? "Không giới hạn"} (không tính chủ nhà hàng).',
          ),
          const SizedBox(height: 16),
          StaffFilterPanel(controller: controller),
          if (state.rolesError != null) ...[
            const SizedBox(height: 12),
            _StaffNotice(
              icon: Icons.error_outline_rounded,
              message: state.rolesError!,
              isError: true,
              actionLabel: 'Tải lại vai trò',
              onAction: controller.loadRoles,
            ),
          ],
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            _StaffNotice(
              icon: Icons.error_outline_rounded,
              message: state.errorMessage!,
              isError: true,
              actionLabel: 'Thử lại',
              onAction: controller.loadInitial,
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Danh sách nhân viên',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${state.totalElements} kết quả',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.isLoading)
            const _StaffListPlaceholder(isLoading: true)
          else if (state.staffList.isEmpty && state.errorMessage == null)
            const _StaffListPlaceholder()
          else
            ...state.staffList.map(
              (staff) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StaffMemberCard(
                  key: ValueKey('staff-card-${staff.id}'),
                  staff: staff,
                  actions: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => _open(context, ref, staff, 'detail'),
                      icon: const Icon(Icons.info_outline, size: 18),
                      label: const Text('Chi tiết'),
                    ),
                    if (AccessPolicy.canManageStaff(
                      session,
                      'STAFF_UPDATE',
                      staff.id,
                      staff.role.code,
                    ))
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: state.roles.isEmpty
                            ? null
                            : () => _open(context, ref, staff, 'edit'),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Sửa'),
                      ),
                    if (AccessPolicy.canManageStaff(
                      session,
                      'STAFF_DISABLE',
                      staff.id,
                      staff.role.code,
                    ))
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          foregroundColor: staff.active
                              ? colors.error
                              : colors.primary,
                        ),
                        onPressed: () => _open(context, ref, staff, 'status'),
                        icon: Icon(
                          staff.active
                              ? Icons.block_outlined
                              : Icons.check_circle_outline,
                          size: 18,
                        ),
                        label: Text(
                          staff.active ? 'Vô hiệu hóa' : 'Kích hoạt lại',
                        ),
                      ),
                    if (AccessPolicy.canManageStaff(
                      session,
                      'STAFF_PERMISSION_MANAGE',
                      staff.id,
                      staff.role.code,
                    ))
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: () =>
                            _open(context, ref, staff, 'permissions'),
                        icon: const Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 18,
                        ),
                        label: const Text('Phân quyền'),
                      ),
                  ],
                ),
              ),
            ),
          if (state.staffList.isNotEmpty)
            EndlessListFooter(
              hasMore: state.page < state.totalPages - 1,
              failureMessage: controller.endless.failure?.message,
              endLabel: 'Đã hiển thị tất cả ${state.totalElements} nhân viên',
              onLoadMore: controller.loadMore,
            ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? value) {
  if (value == null) return 'Chưa đăng nhập';
  final date = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year} '
      '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
}

class _StaffDetailField extends StatelessWidget {
  const _StaffDetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(value, style: theme.textTheme.bodyLarge),
      ],
    );
  }
}

class _StaffPanel extends StatelessWidget {
  const _StaffPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }
}

class _StaffNotice extends StatelessWidget {
  const _StaffNotice({
    required this.icon,
    required this.message,
    this.isError = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = isError
        ? colors.onErrorContainer
        : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? colors.errorContainer : colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? colors.errorContainer : colors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
          if (actionLabel != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: foreground),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ),
        ],
      ),
    );
  }
}

class _StaffListPlaceholder extends StatelessWidget {
  const _StaffListPlaceholder({this.isLoading = false});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _StaffPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            if (isLoading)
              const SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              Icon(
                Icons.person_search_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            const SizedBox(height: 16),
            Text(
              isLoading
                  ? 'Đang tải danh sách nhân viên…'
                  : 'Không tìm thấy nhân viên nào.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (!isLoading) ...[
              const SizedBox(height: 8),
              Text(
                'Thử thay đổi từ khóa hoặc bộ lọc để tìm lại.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
