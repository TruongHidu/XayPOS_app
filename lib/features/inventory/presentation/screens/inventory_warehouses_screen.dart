import 'package:flutter/widgets.dart';

import 'inventory_section_screen.dart';

class InventoryWarehousesScreen extends StatelessWidget {
  const InventoryWarehousesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const InventorySectionScreen(section: InventorySection.warehouses);
}
