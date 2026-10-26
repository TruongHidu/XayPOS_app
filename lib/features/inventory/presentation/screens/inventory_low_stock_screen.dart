import 'package:flutter/widgets.dart';

import 'inventory_section_screen.dart';

class InventoryLowStockScreen extends StatelessWidget {
  const InventoryLowStockScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const InventorySectionScreen(section: InventorySection.lowStock);
}
