import 'package:flutter/widgets.dart';

import 'inventory_section_screen.dart';

/// Tồn kho with the low-stock filter already on, for older links.
class InventoryLowStockScreen extends StatelessWidget {
  const InventoryLowStockScreen({super.key});

  @override
  Widget build(BuildContext context) => const InventorySectionScreen(
    section: InventorySection.balances,
    lowStockOnly: true,
  );
}
