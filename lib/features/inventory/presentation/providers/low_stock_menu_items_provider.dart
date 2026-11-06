import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../../../core/values/item_type.dart';
import '../../domain/entities/inventory_queries.dart';
import '../controllers/inventory_events.dart';

/// Menu items sold directly from stock (trackInventory) that are at or under
/// their threshold in the default warehouse, which orders consume from.
///
/// Advisory only: an empty set when the session cannot read low stock, there
/// is no default warehouse, or a read fails. Recipe-based items are not
/// covered; their ingredient shortfall is not known on this screen.
final lowStockMenuItemIdsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  ref.watch(inventoryScopeProvider);
  final session = ref.read(authControllerProvider).state.session;
  if (!AccessPolicy.canViewInventoryAlerts(session)) return const {};

  // Orders and stock documents change balances; re-read after them.
  ref.listen(inventoryEventsProvider, (_, events) {
    if (const {
      InventoryChangeKind.warehouse,
      InventoryChangeKind.balance,
      InventoryChangeKind.orderStock,
      InventoryChangeKind.alertSync,
    }.contains(events.change?.kind)) {
      ref.invalidateSelf();
    }
  });

  final warehouses = await ref
      .read(warehouseRepositoryProvider)
      .list(
        const WarehouseQuery(
          active: true,
          size: 100,
          sortBy: 'name',
          direction: 'asc',
        ),
      );
  if (!ref.mounted) return const {};
  final defaultId = switch (warehouses) {
    Success(value: final page) =>
      page.content.where((w) => w.isDefault).firstOrNull?.id,
    Error() => null,
  };
  if (defaultId == null) return const {};

  final balances = ref.read(inventoryBalanceRepositoryProvider);
  final ids = <String>{};
  const maxPages = 5;
  for (var page = 0; page < maxPages; page++) {
    final result = await balances.lowStock(
      LowStockQuery(
        warehouseId: defaultId,
        filters: InventoryBalanceQuery(
          page: page,
          size: 100,
          sortBy: 'quantity',
        ),
      ),
    );
    if (!ref.mounted) return const {};
    if (result case Success(value: final rows)) {
      ids.addAll(
        rows.content
            .where((row) => row.itemType == ItemType.menuItem)
            .map((row) => row.stockItemId),
      );
      if (page + 1 >= rows.totalPages) break;
    } else {
      break;
    }
  }
  return ids;
}, name: 'lowStockMenuItemIds');
