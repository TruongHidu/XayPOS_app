import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../widgets/inventory_widgets.dart';
import '../widgets/stock_audit_widgets.dart';

class StockAuditCreateScreen extends ConsumerWidget {
  const StockAuditCreateScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canManageStockAudits(session)) {
      return const Center(
        child: Text('Bạn chưa có quyền quản lý kiểm kê kho.'),
      );
    }
    final c = ref.watch(stockAuditCreateProvider);
    if (c.result != null) {
      return StockAuditPageFrame(
        title: 'Phiên kiểm kê đã tạo',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.result!.auditCode),
            StockAuditStatusBadge(c.result!.status),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go(stockAuditLocation(c.result!.id)),
              child: const Text('Mở phiên kiểm kê'),
            ),
          ],
        ),
      );
    }
    return StockAuditPageFrame(
      title: 'Tạo kiểm kê',
      actions: [
        FilledButton.icon(
          onPressed: c.busy
              ? null
              : () async {
                  final response = await c.save();
                  if (!context.mounted || !c.canManage) return;
                  if (response case Success(value: final value)) {
                    context.go(stockAuditLocation(value.id));
                  }
                },
          icon: const Icon(Icons.save_outlined),
          label: Text(
            c.uncertain ? 'Thử lại yêu cầu ban đầu' : 'Tạo phiên nháp',
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tạo phiên nháp chưa chốt dữ liệu và chưa thay đổi tồn kho. Kho được chọn sẽ không đổi sau khi tạo. Nên bắt đầu kiểm kê lúc ít giao dịch.',
          ),
          const SizedBox(height: 16),
          if (c.busy) const LinearProgressIndicator(),
          InventoryFailurePanel(failure: c.failure),
          if (c.uncertain) ...[
            const Text(
              'Chưa rõ phiên kiểm kê đã được tạo hay chưa. Nội dung được giữ nguyên; bấm thử lại sẽ không tạo trùng phiên.',
            ),
            TextButton(
              onPressed: () => context.go('/app/inventory/audits'),
              child: const Text('Đối chiếu danh sách kiểm kê'),
            ),
            if (c.failure?.code == 'IDEMPOTENCY_KEY_REUSED')
              OutlinedButton(
                onPressed: c.busy
                    ? null
                    : () async {
                        if (await confirmAuditAction(
                          context,
                          ref,
                          permission: 'STOCK_AUDIT_MANAGE',
                          title: 'Đã đối chiếu yêu cầu tạo?',
                          message:
                              'Chỉ mở yêu cầu mới sau khi đã kiểm tra đúng phiên trong danh sách. Không dùng thao tác này để thay thế yêu cầu timeout chưa xác minh.',
                          confirm: 'Đã đối chiếu',
                        )) {
                          c.acknowledgeKeyConflict();
                        }
                      },
                child: const Text('Đã đối chiếu xung đột mã'),
              ),
          ],
          OutlinedButton.icon(
            onPressed: !c.editable
                ? null
                : () async {
                    final value = await chooseStockAuditWarehouse(
                      context,
                      ref,
                      manage: true,
                    );
                    if (!context.mounted || !c.canManage || value == null) {
                      return;
                    }
                    if (!value.active) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Hãy chọn kho đang hoạt động.'),
                        ),
                      );
                      return;
                    }
                    c.selectWarehouse(value);
                  },
            icon: const Icon(Icons.warehouse_outlined),
            label: Text(
              c.warehouse == null
                  ? 'Chọn kho đang hoạt động'
                  : '${c.warehouse!.name} · ${c.warehouse!.code}',
            ),
          ),
          if (c.failure?.fieldErrors['warehouseId'] != null)
            Text(
              c.failure!.fieldErrors['warehouseId']!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey(('audit-create-note', c)),
            initialValue: c.note,
            enabled: c.editable,
            minLines: 2,
            maxLines: 6,
            maxLength: 2000,
            decoration: inventoryField(
              'Ghi chú kiểm kê',
              error: c.failure?.fieldErrors['note'],
            ),
            onChanged: c.setNote,
          ),
        ],
      ),
    );
  }
}
