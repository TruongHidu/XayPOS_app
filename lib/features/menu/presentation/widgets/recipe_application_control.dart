import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../domain/entities/menu_item.dart';
import '../providers/recipe_providers.dart';

/// A menu action; do not place it behind the recipe-screen entitlement gate.
class RecipeApplicationControl extends ConsumerWidget {
  const RecipeApplicationControl({
    super.key,
    required this.menuItemId,
    this.initialMenuItem,
  });
  final String menuItemId;
  final MenuItem? initialMenuItem;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canMenu(session, 'MENU_VIEW')) {
      return const SizedBox.shrink();
    }
    if (!AccessPolicy.canMenu(session, 'MENU_UPDATE')) {
      final item = initialMenuItem;
      return item == null || item.id != menuItemId
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Sử dụng công thức: ${item.recipeEnabled ? "Đang bật" : "Đang tắt"}',
              ),
            );
    }
    final controller = ref.watch(recipeApplicationProvider(menuItemId));
    controller.seed(initialMenuItem);
    final item = controller.item;
    final enabled = item?.recipeEnabled ?? false;
    final allowed =
        item != null &&
        controller.canSet(!enabled) &&
        !controller.busy &&
        !controller.loading &&
        !controller.stale &&
        !controller.needsVerification;
    return Card(
      key: ValueKey(('recipe-application', menuItemId)),
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.loading || controller.busy)
            const LinearProgressIndicator(),
          SwitchListTile(
            key: const ValueKey('recipe-application-switch'),
            title: const Text('Sử dụng công thức'),
            subtitle: Text(
              item == null
                  ? 'Chưa tải được cấu hình món.'
                  : enabled
                  ? 'Đang dùng công thức cho những lượt gửi món tiếp theo.'
                  : 'Đang tắt. Các phiên bản công thức vẫn được giữ.',
            ),
            value: enabled,
            onChanged: allowed ? (value) => controller.setEnabled(value) : null,
          ),
          if (item != null && !controller.canSet(!enabled))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                !AccessPolicy.canMenu(session, 'MENU_UPDATE')
                    ? 'Cần quyền cập nhật món để thay đổi lựa chọn này.'
                    : 'Cần tính năng quản lý công thức để bật. Bạn vẫn có thể tắt nếu món đang sử dụng công thức.',
              ),
            ),
          if (controller.failure != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                controller.failure!.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (item == null || controller.failure != null || controller.stale)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: controller.busy || controller.loading
                    ? null
                    : controller.load,
                icon: const Icon(Icons.refresh),
                label: const Text('Tải lại cấu hình món'),
              ),
            ),
        ],
      ),
    );
  }
}
