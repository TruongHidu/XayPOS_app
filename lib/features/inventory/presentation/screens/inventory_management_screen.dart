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

class InventoryManagementScreen extends ConsumerWidget {
  const InventoryManagementScreen({super.key, this.initialTab});
  final String? initialTab;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(inventoryScopeProvider);
    if (!AccessPolicy.canInventory(
      ref.watch(authControllerProvider).state.session,
      'INVENTORY_VIEW',
    )) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bạn cần quyền xem kho và tính năng quản lý tồn kho để mở màn hình này.',
          ),
        ),
      );
    }
    return _InventoryWorkspace(
      key: ValueKey((scope, initialTab)),
      initialTab: initialTab,
    );
  }
}

enum _InventoryTab { balances, warehouses, lowStock, documents, transactions }

class _InventoryWorkspace extends ConsumerStatefulWidget {
  const _InventoryWorkspace({super.key, this.initialTab});
  final String? initialTab;
  @override
  ConsumerState<_InventoryWorkspace> createState() =>
      _InventoryWorkspaceState();
}

class _InventoryWorkspaceState extends ConsumerState<_InventoryWorkspace> {
  _InventoryTab _tab = _InventoryTab.balances;
  @override
  void initState() {
    super.initState();
    _tab = switch (widget.initialTab) {
      'documents' => _InventoryTab.documents,
      'transactions' => _InventoryTab.transactions,
      _ => _InventoryTab.balances,
    };
  }

  bool _allWarehouses = true;
  Future<void> _refresh() async {
    if (_tab == _InventoryTab.documents) {
      await ref.read(stockDocumentListProvider).load();
      return;
    }
    if (_tab == _InventoryTab.transactions) {
      await ref
          .read(inventoryTransactionsProvider(const StockHistoryTarget()))
          .load();
      return;
    }
    final selector = ref.read(warehouseSelectorProvider);
    final warehouse = selector.selected;
    final jobs = <Future<void>>[selector.load(), selector.refreshSelection()];
    if (_tab == _InventoryTab.warehouses) {
      jobs.add(ref.read(warehouseListProvider).load());
    } else if (_tab == _InventoryTab.lowStock || warehouse != null) {
      jobs.add(
        ref
            .read(
              inventoryBalancesProvider((
                warehouseId: _tab == _InventoryTab.lowStock && _allWarehouses
                    ? null
                    : warehouse?.id,
                lowStock: _tab == _InventoryTab.lowStock,
              )),
            )
            .load(),
      );
    }
    await Future.wait(jobs);
  }

  @override
  Widget build(BuildContext context) {
    final selector = ref.watch(warehouseSelectorProvider),
        session = ref.watch(authControllerProvider).state.session;
    final warehouse = selector.selected;
    final lowAllowed = session?.features.contains('LOW_STOCK_ALERT') == true;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: const PageStorageKey('inventory-workspace'),
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
                            'Kho nguyên liệu',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Xem số dư tồn và quản lý ngưỡng cảnh báo.',
                          ),
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
                          if ((_tab == _InventoryTab.balances ||
                                  _tab == _InventoryTab.warehouses) &&
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
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in {
                        _InventoryTab.balances: 'Tồn kho',
                        _InventoryTab.warehouses: 'Kho',
                        _InventoryTab.documents: 'Chứng từ',
                        _InventoryTab.transactions: 'Biến động',
                        if (lowAllowed)
                          _InventoryTab.lowStock: 'Cảnh báo tồn thấp',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _tab == entry.key,
                          onSelected: (_) => setState(() => _tab = entry.key),
                        ),
                    ],
                  ),
                  if (_tab == _InventoryTab.balances ||
                      _tab == _InventoryTab.lowStock) ...[
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
                        if (_tab == _InventoryTab.lowStock)
                          FilterChip(
                            label: const Text('Tất cả kho'),
                            selected: _allWarehouses,
                            onSelected: (v) =>
                                setState(() => _allWarehouses = v),
                          ),
                      ],
                    ),
                    if (selector.loading && warehouse == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    InventoryFailurePanel(
                      failure: selector.failure ?? selector.selectionFailure,
                      retry: selector.loading
                          ? null
                          : () => Future.wait([
                              selector.load(),
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
              child: _tab == _InventoryTab.documents
                  ? const StockDocumentList()
                  : _tab == _InventoryTab.transactions
                  ? const InventoryTransactionList()
                  : _tab == _InventoryTab.warehouses
                  ? const WarehouseList()
                  : _tab == _InventoryTab.lowStock && !lowAllowed
                  ? const Text('Tính năng cảnh báo tồn thấp chưa khả dụng.')
                  : (_tab == _InventoryTab.lowStock && _allWarehouses ||
                        warehouse != null)
                  ? InventoryBalanceList(
                      key: ValueKey((warehouse?.id, _tab, _allWarehouses)),
                      target: (
                        warehouseId:
                            _tab == _InventoryTab.lowStock && _allWarehouses
                            ? null
                            : warehouse?.id,
                        lowStock: _tab == _InventoryTab.lowStock,
                      ),
                      warehouseActive:
                          _tab == _InventoryTab.lowStock && _allWarehouses
                          ? null
                          : warehouse?.active,
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        selector.loading
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
