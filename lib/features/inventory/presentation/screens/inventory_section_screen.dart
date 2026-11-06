import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../app/router/app_routes.dart';
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
  const InventorySectionScreen({
    super.key,
    required this.section,
    this.lowStockOnly = false,
  });
  final InventorySection section;

  /// Opens Tồn kho already narrowed to low-stock rows in every warehouse.
  final bool lowStockOnly;
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
      InventorySection.alerts => AccessPolicy.canViewInventoryAlerts(session),
      InventorySection.audits => AccessPolicy.canViewStockAudits(session),
      _ => !lowStockOnly || AccessPolicy.canViewInventoryAlerts(session),
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
      key: ValueKey((scope, section, lowStockOnly)),
      section: section,
      lowStockOnly: lowStockOnly,
    );
  }
}

enum InventorySection {
  balances('Tồn kho', 'Theo dõi số lượng hàng hóa tại từng kho.'),
  warehouses('Quản lý kho', 'Quản lý kho hàng và kho mặc định.'),
  documents('Chứng từ kho', 'Theo dõi phiếu nhập, xuất và điều chỉnh tồn kho.'),
  transactions(
    'Biến động kho',
    'Xem lại mọi lần nhập, xuất, điều chỉnh và tiêu thụ hàng hóa.',
  ),
  alerts('Cảnh báo tồn kho', 'Theo dõi và xử lý các đợt cảnh báo tồn kho.'),
  audits('Kiểm kê', 'Đối chiếu tồn thực tế và chốt kết quả kiểm kê.');

  const InventorySection(this.title, this.description);
  final String title, description;
}

class _InventoryWorkspace extends ConsumerStatefulWidget {
  const _InventoryWorkspace({
    super.key,
    required this.section,
    required this.lowStockOnly,
  });
  final InventorySection section;
  final bool lowStockOnly;
  @override
  ConsumerState<_InventoryWorkspace> createState() =>
      _InventoryWorkspaceState();
}

class _InventoryWorkspaceState extends ConsumerState<_InventoryWorkspace> {
  InventorySection get _tab => widget.section;

  late bool _lowOnly = widget.lowStockOnly;

  /// Tồn kho narrowed to rows at or under their threshold.
  bool get _low => _tab == InventorySection.balances && _lowOnly;

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
    if (_low) {
      jobs.add(ref.read(inventoryLowStockCountProvider).load());
    }
    if (_low || warehouse != null) {
      jobs.add(
        ref
            .read(
              inventoryBalancesProvider((
                warehouseId: _low && _allWarehouses ? null : warehouse?.id,
                lowStock: _low,
              )),
            )
            .load(),
      );
    }
    await Future.wait(jobs);
  }

  @override
  Widget build(BuildContext context) {
    final warehouseTab = _tab == InventorySection.balances;
    final selector = warehouseTab ? ref.watch(warehouseSelectorProvider) : null;
    final session = ref.watch(authControllerProvider).state.session;
    final warehouse = selector?.selected;
    final lowAllowed = session?.features.contains('LOW_STOCK_ALERT') == true;
    final canFilterLow =
        warehouseTab && AccessPolicy.canViewInventoryAlerts(session);
    final documentsTab = _tab == InventorySection.documents;
    final body = RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: PageStorageKey('inventory-${_tab.name}'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Chứng từ kho starts at its search bar; creation moves to the FAB.
          if (!documentsTab)
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
                            // These lists carry their own reload button.
                            if (!const {
                              InventorySection.documents,
                              InventorySection.transactions,
                              // InventorySection.alerts,
                              InventorySection.audits,
                            }.contains(_tab))
                              IconButton(
                                tooltip: 'Tải lại kho',
                                onPressed: _refresh,
                                icon: const Icon(Icons.refresh),
                              ),
                            // Less frequent stock pages open from Tồn kho.
                            if (warehouseTab) ...[
                              IconButton(
                                tooltip: 'Biến động kho',
                                onPressed: () => context.push(
                                  AppRoutes.inventoryTransactions,
                                ),
                                icon: const Icon(Icons.history),
                              ),
                              IconButton(
                                tooltip: 'Quản lý kho',
                                onPressed: () =>
                                    context.push(AppRoutes.inventoryWarehouses),
                                icon: const Icon(Icons.store_outlined),
                              ),
                            ],
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
                    if (warehouseTab) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                pickInventoryWarehouse(context, ref),
                            icon: const Icon(Icons.warehouse_outlined),
                            label: Text(
                              warehouse == null
                                  ? 'Chọn kho'
                                  : '${warehouse.name} · ${warehouse.code}',
                            ),
                          ),
                          if (warehouse?.isDefault == true)
                            const InventoryBadge(
                              'Kho mặc định',
                              positive: true,
                            ),
                          if (canFilterLow)
                            FilterChip(
                              avatar: const Icon(
                                Icons.warning_amber_outlined,
                                size: 18,
                              ),
                              label: const Text('Chỉ tồn thấp'),
                              selected: _lowOnly,
                              onSelected: (v) => setState(() => _lowOnly = v),
                            ),
                          if (_low)
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
                        failure:
                            selector?.failure ?? selector?.selectionFailure,
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
            // Documents: room above for the missing header, below for the FAB.
            padding: documentsTab
                ? const EdgeInsets.fromLTRB(16, 16, 16, 88)
                : const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
                  : _low && !lowAllowed
                  ? const Text('Tính năng cảnh báo tồn thấp chưa khả dụng.')
                  : (_low && _allWarehouses || warehouse != null)
                  ? InventoryBalanceList(
                      key: ValueKey((warehouse?.id, _low, _allWarehouses)),
                      target: (
                        warehouseId: _low && _allWarehouses
                            ? null
                            : warehouse?.id,
                        lowStock: _low,
                      ),
                      warehouseActive: _low && _allWarehouses
                          ? null
                          : warehouse?.active,
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        selector?.loading == true
                            ? 'Đang tải danh sách kho…'
                            : selector?.initial == false &&
                                  selector?.totalElements == 0 &&
                                  selector?.query.q.isEmpty == true
                            ? 'Chưa có kho nào. Bấm nút “Quản lý kho” ở trên để tạo kho đầu tiên.'
                            : 'Bấm “Chọn kho” để xem tồn.',
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
    return documentsTab
        ? Scaffold(
            floatingActionButton: const StockDocumentCreateFab(),
            body: body,
          )
        : body;
  }
}
