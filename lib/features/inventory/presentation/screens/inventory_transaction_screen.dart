import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../widgets/stock_widgets.dart';
import '../widgets/inventory_transaction_list.dart';

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
