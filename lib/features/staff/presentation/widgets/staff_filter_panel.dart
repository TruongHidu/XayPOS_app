import 'package:flutter/material.dart';

import '../../../../core/ui/widgets/responsive_columns.dart';
import '../controllers/staff_list_controller.dart';

class StaffFilterPanel extends StatelessWidget {
  const StaffFilterPanel({super.key, required this.controller});

  final StaffListController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: ObjectKey(controller),
            initialValue: state.query,
            decoration: _decoration(
              context,
              'Tìm nhân viên',
              icon: Icons.search,
            ).copyWith(hintText: 'Tên, email hoặc số điện thoại'),
            onChanged: controller.setSearchQuery,
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune_rounded, size: 20),
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text('Bộ lọc và sắp xếp'),
            childrenPadding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              ResponsiveColumns(
                minColumnWidth: 200,
                maxColumns: 5,
                children: [
                  DropdownButtonFormField<String>(
                    value: state.selectedRoleCode ?? '',
                    isExpanded: true,
                    decoration: _decoration(context, 'Vai trò'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Tất cả vai trò'),
                      ),
                      if (state.selectedRoleCode != null &&
                          !state.roles.any(
                            (r) => r.code == state.selectedRoleCode,
                          ))
                        DropdownMenuItem(
                          value: state.selectedRoleCode,
                          child: Text(state.selectedRoleCode!),
                        ),
                      ...state.roles.map(
                        (r) => DropdownMenuItem(
                          value: r.code,
                          child: Text(r.name),
                        ),
                      ),
                    ],
                    onChanged: (v) =>
                        controller.setRoleFilter(v == '' ? null : v),
                  ),
                  DropdownButtonFormField<String>(
                    value: state.selectedActive?.toString() ?? '',
                    isExpanded: true,
                    decoration: _decoration(context, 'Trạng thái'),
                    items: const [
                      DropdownMenuItem(
                        value: '',
                        child: Text('Tất cả trạng thái'),
                      ),
                      DropdownMenuItem(value: 'true', child: Text('Hoạt động')),
                      DropdownMenuItem(
                        value: 'false',
                        child: Text('Đã vô hiệu hóa'),
                      ),
                    ],
                    onChanged: (v) => controller.setStatusFilter(
                      v == '' ? null : v == 'true',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    value: state.sortBy,
                    isExpanded: true,
                    decoration: _decoration(context, 'Sắp xếp theo'),
                    items: const [
                      DropdownMenuItem(
                        value: 'createdAt',
                        child: Text('Ngày tạo'),
                      ),
                      DropdownMenuItem(value: 'name', child: Text('Tên')),
                      DropdownMenuItem(value: 'email', child: Text('Email')),
                      DropdownMenuItem(
                        value: 'lastLoginAt',
                        child: Text('Đăng nhập cuối'),
                      ),
                    ],
                    onChanged: (v) =>
                        controller.setSorting(v!, state.direction),
                  ),
                  DropdownButtonFormField<String>(
                    value: state.direction,
                    isExpanded: true,
                    decoration: _decoration(context, 'Thứ tự'),
                    items: const [
                      DropdownMenuItem(value: 'asc', child: Text('Tăng dần')),
                      DropdownMenuItem(value: 'desc', child: Text('Giảm dần')),
                    ],
                    onChanged: (v) => controller.setSorting(state.sortBy, v!),
                  ),
                  DropdownButtonFormField<int>(
                    value: state.size,
                    isExpanded: true,
                    decoration: _decoration(context, 'Số dòng mỗi trang'),
                    items: [10, 20, 50, 100]
                        .map(
                          (n) => DropdownMenuItem(value: n, child: Text('$n')),
                        )
                        .toList(),
                    onChanged: (v) => controller.setSize(v!),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(
    BuildContext context,
    String label, {
    IconData? icon,
  }) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(10);
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      filled: true,
      fillColor: colors.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
    );
  }
}
