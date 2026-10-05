import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../domain/entities/menu_group.dart';
import '../providers/menu_providers.dart';
import 'menu_dialogs.dart';

class MenuGroupChoice {
  const MenuGroupChoice(this.group);
  final MenuItemGroupSummary? group;
}

class MenuGroupPicker extends ConsumerWidget {
  const MenuGroupPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeOnly = true,
    this.permission = 'MENU_UPDATE',
    this.errorText,
  });
  final MenuItemGroupSummary? value;
  final ValueChanged<MenuItemGroupSummary?> onChanged;
  final bool activeOnly;
  final String permission;
  final String? errorText;
  @override
  Widget build(BuildContext context, WidgetRef ref) => OutlinedButton(
    onPressed: () async {
      final choice = await showMenuDialog<MenuGroupChoice>(
        context,
        ref,
        permission: permission,
        child: _GroupSelector(activeOnly: activeOnly, current: value),
      );
      if (choice != null && context.mounted) onChanged(choice.group);
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value == null
                      ? (activeOnly ? 'Chưa phân nhóm' : 'Tất cả nhóm')
                      : value!.name,
                ),
                if (value != null && !value!.active)
                  const Text('Nhóm đang ngừng hoạt động'),
                if (errorText != null)
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.expand_more),
        ],
      ),
    ),
  );
}

class _GroupSelector extends ConsumerWidget {
  const _GroupSelector({required this.activeOnly, required this.current});
  final bool activeOnly;
  final MenuItemGroupSummary? current;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(menuGroupSelectorProvider(activeOnly));
    final state = controller.state;
    return ResponsiveDialog(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Chọn nhóm món',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (current != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Nhóm hiện tại: ${current!.name}${current!.active ? "" : " (ngừng hoạt động)"}',
                ),
              ),
            TextFormField(
              key: ObjectKey(controller),
              initialValue: state.query.q,
              maxLength: 100,
              decoration: menuField('Tìm nhóm'),
              onChanged: controller.search,
            ),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(activeOnly ? 'Chưa phân nhóm' : 'Tất cả nhóm'),
              onTap: () =>
                  Navigator.of(context).pop(const MenuGroupChoice(null)),
            ),
            if (state.loading) const LinearProgressIndicator(),
            MenuFailurePanel(failure: state.failure, onReload: controller.load),
            if (state.hasLoaded && state.rows.isEmpty && state.failure == null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Không tìm thấy nhóm phù hợp.'),
              ),
            for (final group in state.rows)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(group.name),
                subtitle: Text(
                  group.active ? 'Đang hoạt động' : 'Ngừng hoạt động',
                ),
                enabled: !state.loading && (!activeOnly || group.active),
                selected: current?.id == group.id,
                onTap: () => Navigator.of(context).pop(
                  MenuGroupChoice(
                    MenuItemGroupSummary(
                      id: group.id,
                      name: group.name,
                      active: group.active,
                    ),
                  ),
                ),
              ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Trang ${state.query.page + 1}/${state.totalPages == 0 ? 1 : state.totalPages}',
                ),
                Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Nhóm: trang trước',
                      onPressed: state.loading || state.query.page == 0
                          ? null
                          : () => controller.setPage(state.query.page - 1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      tooltip: 'Nhóm: trang sau',
                      onPressed:
                          state.loading ||
                              state.query.page >= state.totalPages - 1
                          ? null
                          : () => controller.setPage(state.query.page + 1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Đóng lựa chọn nhóm'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
