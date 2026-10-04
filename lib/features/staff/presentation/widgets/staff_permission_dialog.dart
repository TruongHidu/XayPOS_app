import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../domain/entities/staff_member.dart';

class StaffPermissionDialog extends ConsumerStatefulWidget {
  const StaffPermissionDialog({super.key, required this.staff});
  final StaffMember staff;
  @override
  ConsumerState<StaffPermissionDialog> createState() =>
      _StaffPermissionDialogState();
}

class _StaffPermissionDialogState extends ConsumerState<StaffPermissionDialog> {
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

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(staffPermissionControllerProvider);
    final state = controller.state;
    final valid = state.config?.staffId == widget.staff.id;
    return ResponsiveDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Phân quyền: ${widget.staff.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.isLoading)
                    const Center(child: CircularProgressIndicator()),
                  if (state.errorMessage != null) ...[
                    Text(
                      state.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    TextButton(
                      onPressed: state.isSaving
                          ? null
                          : () => controller.load(widget.staff.id),
                      child: const Text('Thử lại'),
                    ),
                  ],
                  if (valid && !state.isLoading) ...[
                    const Text(
                      'Quyền hiệu lực = (quyền của vai trò + cho phép thêm) − quyền bị chặn.',
                    ),
                    Text(
                      'Đã lưu: ${state.config!.effectivePermissions.where((code) => state.catalog.any((item) => item.code == code)).join(", ")}',
                    ),
                    if (state.successMessage != null)
                      Text(state.successMessage!),
                    const SizedBox(height: 16),
                    ResponsiveColumns(
                      children: state.catalog.map((item) {
                        final mode = state.localDenies.contains(item.code)
                            ? 'deny'
                            : state.localGrants.contains(item.code)
                            ? 'grant'
                            : 'default';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.module} • ${item.name}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(item.code),
                              if (item.description != null)
                                Text(item.description!),
                              Text(
                                'Kế thừa vai trò: ${state.config!.rolePermissions.contains(item.code) ? "Có" : "Không"} • Dự kiến: ${state.calculatedEffectivePermissions.contains(item.code) ? "Có" : "Không"}',
                              ),
                              DropdownButton<String>(
                                value: mode,
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(
                                    value: 'default',
                                    child: Text('Kế thừa'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'grant',
                                    enabled: controller.canGrant(item.code),
                                    child: const Text('Cho phép thêm'),
                                  ),
                                  const DropdownMenuItem(
                                    value: 'deny',
                                    child: Text('Chặn'),
                                  ),
                                ],
                                onChanged: !controller.canSave
                                    ? null
                                    : (v) => controller.setPermissionState(
                                        item.code,
                                        v!,
                                      ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Đóng'),
              ),
              TextButton(
                onPressed: valid && controller.canSave
                    ? controller.resetAllOverrides
                    : null,
                child: const Text('Xóa mọi override'),
              ),
              FilledButton(
                onPressed: valid && controller.canSave
                    ? () => controller.saveOverrides(widget.staff.id)
                    : null,
                child: Text(state.isSaving ? 'Đang lưu…' : 'Lưu thay đổi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
