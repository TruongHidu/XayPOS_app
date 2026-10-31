import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/permission_catalog_item.dart';
import '../../domain/entities/staff_member.dart';
import '../controllers/staff_permission_controller.dart';
import 'staff_permission_labels.dart';

/// One on/off switch per permission, starting from the staff member's role.
/// Grants and denies stay a controller detail so owners never see them.
class StaffPermissionDialog extends ConsumerStatefulWidget {
  const StaffPermissionDialog({super.key, required this.staff});
  final StaffMember staff;
  @override
  ConsumerState<StaffPermissionDialog> createState() =>
      _StaffPermissionDialogState();
}

class _StaffPermissionDialogState extends ConsumerState<StaffPermissionDialog> {
  String _search = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(staffPermissionControllerProvider).load(widget.staff.id);
      }
    });
  }

  @override
  void didUpdateWidget(covariant StaffPermissionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.staff.id != widget.staff.id) {
      Future.microtask(() {
        if (mounted) {
          ref.read(staffPermissionControllerProvider).load(widget.staff.id);
        }
      });
    }
  }

  Future<void> _close(bool dirty) async {
    final navigator = Navigator.of(context);
    if (!dirty) {
      navigator.pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bỏ thay đổi chưa lưu?'),
        content: const Text(
          'Các quyền vừa bật hoặc tắt sẽ không được áp dụng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Tiếp tục sửa'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bỏ thay đổi'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) navigator.pop();
  }

  bool _matches(PermissionCatalogItem item) {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return true;
    return '${staffPermissionName(item)} ${item.description ?? ''}'
        .toLowerCase()
        .contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(staffPermissionControllerProvider);
    final state = controller.state;
    final valid = state.config?.staffId == widget.staff.id;
    final dirty = valid && state.changedCodes.isNotEmpty;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: Theme.of(context).colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: double.infinity,
        height: MediaQuery.sizeOf(context).height - 48,
        child: PopScope(
          canPop: !dirty && !state.isSaving,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !state.isSaving) _close(dirty);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, controller, valid, dirty),
              const Divider(height: 1),
              Expanded(child: _content(context, controller, valid)),
              const Divider(height: 1),
              _footer(context, controller, valid, dirty),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    StaffPermissionController controller,
    bool valid,
    bool dirty,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final state = controller.state;
    final name = widget.staff.name.trim();
    final role = widget.staff.role.name;
    final enabled = state.catalog
        .where((item) => controller.isEnabled(item.code))
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  valid
                      ? '$role · Đang có $enabled/${state.catalog.length} quyền'
                      : role,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Đóng',
            onPressed: state.isSaving ? null : () => _close(dirty),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    StaffPermissionController controller,
    bool valid,
  ) {
    final theme = Theme.of(context);
    final state = controller.state;
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!valid) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.errorMessage ?? 'Chưa tải được danh sách quyền.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => controller.load(widget.staff.id),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    final colors = theme.colorScheme;
    final muted = colors.onSurfaceVariant;
    final searching = _search.trim().isNotEmpty;
    final groups = groupStaffPermissions(state.catalog.where(_matches));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Quyền mặc định lấy theo vai trò ${widget.staff.role.name}. Bật hoặc tắt bên dưới để điều chỉnh riêng cho nhân viên này.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('staff-permission-search'),
          onChanged: (value) => setState(() => _search = value),
          decoration: InputDecoration(
            hintText: 'Tìm quyền, ví dụ: hủy đơn',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'Không tìm thấy quyền phù hợp.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
        ResponsiveColumns(
          minColumnWidth: 420,
          maxColumns: 2,
          spacing: 8,
          children: [
            for (final (index, group) in groups.indexed)
              _PermissionGroupCard(
                // The key re-applies initiallyExpanded when a search changes.
                key: ValueKey((group.label, searching)),
                group: group,
                controller: controller,
                expanded: searching || index == 0,
              ),
          ],
        ),
      ],
    );
  }

  Widget _footer(
    BuildContext context,
    StaffPermissionController controller,
    bool valid,
    bool dirty,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final state = controller.state;
    final count = state.changedCodes.length;
    final canEdit = valid && controller.canSave;
    final hasOverrides =
        state.localGrants.isNotEmpty || state.localDenies.isNotEmpty;
    final saveFailed = valid ? state.errorMessage : null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (saveFailed != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  saveFailed,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
                ),
              )
            else if (dirty || state.successMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  dirty ? '$count thay đổi chưa lưu' : state.successMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: dirty ? colors.primary : const Color(0xFF0D9488),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: canEdit && hasOverrides
                      ? controller.resetAllOverrides
                      : null,
                  child: const Text('Khôi phục theo vai trò'),
                ),
                FilledButton(
                  onPressed: canEdit && dirty
                      ? () => controller.saveOverrides(widget.staff.id)
                      : null,
                  child: Text(state.isSaving ? 'Đang lưu…' : 'Lưu thay đổi'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionGroupCard extends StatelessWidget {
  const _PermissionGroupCard({
    super.key,
    required this.group,
    required this.controller,
    required this.expanded,
  });

  final StaffPermissionGroup group;
  final StaffPermissionController controller;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final codes = [for (final item in group.items) item.code];
    final enabled = codes.where(controller.isEnabled).length;
    final changeable = codes.where(controller.canToggle);
    final canAllOn = changeable.any((code) => !controller.isEnabled(code));
    final canAllOff = changeable.any(controller.isEnabled);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: colors.primaryContainer.withValues(alpha: 0.5),
          child: Icon(group.icon, size: 20, color: colors.primary),
        ),
        title: Text(
          group.label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          enabled == codes.length
              ? 'Có tất cả ${codes.length} quyền'
              : enabled == 0
              ? 'Chưa có quyền nào trong ${codes.length} quyền'
              : 'Có $enabled/${codes.length} quyền',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 4),
        children: [
          if (codes.length > 1)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: canAllOn
                        ? () => controller.setGroupEnabled(codes, true)
                        : null,
                    child: const Text('Bật cả nhóm'),
                  ),
                  TextButton(
                    onPressed: canAllOff
                        ? () => controller.setGroupEnabled(codes, false)
                        : null,
                    child: const Text('Tắt cả nhóm'),
                  ),
                ],
              ),
            ),
          for (final item in group.items)
            _PermissionTile(item: item, controller: controller),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({required this.item, required this.controller});

  final PermissionCatalogItem item;
  final StaffPermissionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = controller.isEnabled(item.code);
    final inRole =
        controller.state.config?.rolePermissions.contains(item.code) ?? false;
    final canToggle = controller.canToggle(item.code);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final note = enabled == inRole
        ? null
        : enabled
        ? 'Thêm riêng cho nhân viên này'
        : 'Đã tắt riêng cho nhân viên này';
    return SwitchListTile(
      key: ValueKey('staff-permission-${item.code}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      visualDensity: VisualDensity.compact,
      title: Text(staffPermissionName(item), style: theme.textTheme.bodyMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.description?.isNotEmpty == true)
            Text(item.description!, style: muted),
          if (note != null)
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: enabled ? const Color(0xFF0D9488) : colors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (!canToggle && controller.canSave)
            Text(
              'Bạn chưa có quyền này nên không thể cấp cho người khác.',
              style: muted,
            ),
        ],
      ),
      value: enabled,
      onChanged: canToggle
          ? (value) => controller.setEnabled(item.code, value)
          : null,
    );
  }
}
