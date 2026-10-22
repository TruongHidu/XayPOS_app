import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../widgets/stock_widgets.dart';
import '../widgets/inventory_transaction_list.dart';

/// Reject malformed deep links before constructing a ledger provider.
class InventoryTransactionRoute extends StatelessWidget {
  const InventoryTransactionRoute({super.key, required this.query});
  final Map<String, String> query;
  @override
  Widget build(BuildContext context) {
    try {
      return InventoryTransactionScreen(
        target: StockHistoryTarget.fromQuery(query),
      );
    } on FormatException {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Bộ lọc giao dịch không hợp lệ. Hãy mở lại lịch sử kho.'),
        ),
      );
    }
  }
}

class InventoryTransactionScreen extends ConsumerWidget {
  const InventoryTransactionScreen({super.key, required this.target});
  final StockHistoryTarget target;
  @override
  Widget build(BuildContext context, WidgetRef ref) => StockPageFrame(
    key: ValueKey((ref.watch(inventoryScopeProvider), target)),
    title: 'Lịch sử biến động kho',
    onRefresh: () => ref.read(inventoryTransactionsProvider(target)).load(),
    child: InventoryTransactionList(target: target),
  );
}
