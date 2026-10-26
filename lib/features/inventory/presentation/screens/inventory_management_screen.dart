import 'package:flutter/widgets.dart';

import 'inventory_alerts_screen.dart';
import 'inventory_audits_screen.dart';
import 'inventory_balances_screen.dart';
import 'inventory_documents_screen.dart';
import 'inventory_low_stock_screen.dart';
import 'inventory_transactions_screen.dart';
import 'inventory_warehouses_screen.dart';

/// Compatibility entry point for callers using the former tab names.
class InventoryManagementScreen extends StatelessWidget {
  const InventoryManagementScreen({super.key, this.initialTab});
  final String? initialTab;

  @override
  Widget build(BuildContext context) => switch (initialTab) {
    'warehouses' => const InventoryWarehousesScreen(),
    'documents' => const InventoryDocumentsScreen(),
    'transactions' => const InventoryTransactionsScreen(),
    'lowStock' || 'low-stock' => const InventoryLowStockScreen(),
    'alerts' => const InventoryAlertsScreen(),
    'audits' => const InventoryAuditsScreen(),
    _ => const InventoryBalancesScreen(),
  };
}
