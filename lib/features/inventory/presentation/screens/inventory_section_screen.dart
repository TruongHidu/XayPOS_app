import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../domain/entities/inventory_entities.dart';
import '../widgets/inventory_widgets.dart';
import '../widgets/warehouse_picker.dart';
import '../widgets/warehouse_form.dart';
import '../widgets/warehouse_list.dart';
import '../widgets/inventory_balance_list.dart';
import '../widgets/stock_document_list.dart';
import '../widgets/inventory_transaction_list.dart';
import '../widgets/inventory_alert_list.dart';
import '../widgets/stock_audit_list.dart';

/// Shared presentation layout; only the selected function's content is mounted.
class InventorySectionScreen extends ConsumerWidget {
  const InventorySectionScreen({super.key, required this.section});
  final InventorySection section;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(inventoryScopeProvider);
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canInventory(session, 'INVENTORY_VIEW')) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bạn cần quyền xem kho và tính năng quản lý tồn kho để mở màn hình này.',
          ),
        ),
      );
    }
    final allowed = switch (section) {
      InventorySection.alerts ||
      InventorySection.lowStock => AccessPolicy.canViewInventoryAlerts(session),
      InventorySection.audits => AccessPolicy.canViewStockAudits(session),
      _ => true,
    };
    if (!allowed) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Bạn chưa có quyền hoặc tính năng cho mục kho này.'),
        ),
      );
    }
    return _InventoryWorkspace(
      key: ValueKey((scope, section)),
      section: section,
    );
  }
}

enum InventorySection {
  balances('Tồn kho', 'Theo dõi số lượng nguyên liệu tại từng kho.'),
  warehouses('Quản lý kho', 'Quản lý kho nguyên liệu và kho mặc định.'),
  lowStock(
    'Tồn thấp hiện tại',
    'Theo dõi nguyên liệu đang chạm ngưỡng tồn thấp.',
  ),
  documents('Chứng từ kho', 'Theo dõi phiếu nhập, xuất và điều chỉnh tồn kho.'),
  transactions('Biến động kho', 'Tra cứu lịch sử biến động nguyên liệu.'),
  alerts('Cảnh báo tồn kho', 'Theo dõi và xử lý các đợt cảnh báo tồn kho.'),
  audits('Kiểm kê', 'Đối chiếu tồn thực tế và chốt kết quả kiểm kê.');

  const InventorySection(this.title, this.description);
  final String title, description;
}

class _InventoryWorkspace extends ConsumerStatefulWidget {
  const _InventoryWorkspace({super.key, required this.section});
  final InventorySection section;
  @override
  ConsumerState<_InventoryWorkspace> createState() =>
      _InventoryWorkspaceState();
}

class _InventoryWorkspaceState extends ConsumerState<_InventoryWorkspace> {
  InventorySection get _tab => widget.section;

  bool _allWarehouses = true;
  Future<void> _refresh() async {
    if (_tab == InventorySection.warehouses) {
      await ref.read(warehouseListProvider).load();
      return;
    }
    if (_tab == InventorySection.alerts) {
      await ref.read(inventoryAlertListProvider).load();
      return;
    }
    if (_tab == InventorySection.audits) {
      await ref.read(stockAuditListProvider).load();
      return;
    }
    if (_tab == InventorySection.documents) {
      await ref.read(stockDocumentListProvider).load();
      return;
    }
    if (_tab == InventorySection.transactions) {
      await ref
          .read(inventoryTransactionsProvider(const StockHistoryTarget()))
          .load();
      return;
    }
    final selector = ref.read(warehouseSelectorProvider);
    final warehouse = selector.selected;
    final jobs = <Future<void>>[selector.load(), selector.refreshSelection()];
    if (_tab == InventorySection.lowStock) {
      jobs.add(ref.read(inventoryLowStockCountProvider).load());
    }
    if (_tab == InventorySection.lowStock || warehouse != null) {
      jobs.add(
        ref
            .read(
              inventoryBalancesProvider((
                warehouseId: _tab == InventorySection.lowStock && _allWarehouses
                    ? null
                    : warehouse?.id,
                lowStock: _tab == InventorySection.lowStock,
              )),
            )
            .load(),
      );
    }
    await Future.wait(jobs);
  }

  @override
  Widget build(BuildContext context) {
    final warehouseTab = const {
      InventorySection.balances,
      InventorySection.lowStock,
    }.contains(_tab);
    final selector = warehouseTab ? ref.watch(warehouseSelectorProvider) : null;
    final session = ref.watch(authControllerProvider).state.session;
    final warehouse = selector?.selected;
    final lowAllowed = session?.features.contains('LOW_STOCK_ALERT') == true;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: PageStorageKey('inventory-${_tab.name}'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tab.title,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(_tab.description),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          IconButton(
                            tooltip: 'Tải lại kho',
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                          ),
                          if (_tab == InventorySection.warehouses &&
                              AccessPolicy.canInventory(
                                session,
                                'WAREHOUSE_CREATE',
                              ))
                            FilledButton.icon(
                              onPressed: () async {
                                final result =
                                    await showInventoryDialog<Warehouse>(
                                      context,
                                      ref,
                                      permission: 'WAREHOUSE_CREATE',
                                      child: const WarehouseForm(),
                                    );
                                if (context.mounted && result != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã tạo kho.'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Thêm kho'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if (_tab == InventorySection.balances ||
                      _tab == InventorySection.lowStock) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => pickInventoryWarehouse(context, ref),
                          icon: const Icon(Icons.warehouse_outlined),
                          label: Text(
                            warehouse == null
                                ? 'Chọn kho'
                                : '${warehouse.name} · ${warehouse.code}',
                          ),
                        ),
                        if (warehouse?.isDefault == true)
                          const InventoryBadge('Kho mặc định', positive: true),
                        if (_tab == InventorySection.lowStock)
                          FilterChip(
                            label: const Text('Tất cả kho'),
                            selected: _allWarehouses,
                            onSelected: (v) =>
                                setState(() => _allWarehouses = v),
                          ),
                      ],
                    ),
                    if (selector?.loading == true && warehouse == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    InventoryFailurePanel(
                      failure: selector?.failure ?? selector?.selectionFailure,
                      retry: selector?.loading == true
                          ? null
                          : () => Future.wait([
                              selector!.load(),
                              selector.refreshSelection(),
                            ]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverToBoxAdapter(
              child: _tab == InventorySection.alerts
                  ? const InventoryAlertList()
                  : _tab == InventorySection.audits
                  ? const StockAuditList()
                  : _tab == InventorySection.documents
                  ? const StockDocumentList()
                  : _tab == InventorySection.transactions
                  ? const InventoryTransactionList()
                  : _tab == InventorySection.warehouses
                  ? const WarehouseList()
                  : _tab == InventorySection.lowStock && !lowAllowed
                  ? const Text('Tính năng cảnh báo tồn thấp chưa khả dụng.')
                  : (_tab == InventorySection.lowStock && _allWarehouses ||
                        warehouse != null)
                  ? InventoryBalanceList(
                      key: ValueKey((warehouse?.id, _tab, _allWarehouses)),
                      target: (
                        warehouseId:
                            _tab == InventorySection.lowStock && _allWarehouses
                            ? null
                            : warehouse?.id,
                        lowStock: _tab == InventorySection.lowStock,
                      ),
                      warehouseActive:
                          _tab == InventorySection.lowStock && _allWarehouses
                          ? null
                          : warehouse?.active,
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        selector?.loading == true
                            ? 'Đang tải danh sách kho…'
                            : 'Chọn một kho để xem tồn. Nếu chưa có kho, hãy thêm kho đầu tiên.',
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
