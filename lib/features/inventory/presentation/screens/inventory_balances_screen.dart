import 'package:flutter/widgets.dart';

import 'inventory_section_screen.dart';

class InventoryBalancesScreen extends StatelessWidget {
  const InventoryBalancesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const InventorySectionScreen(section: InventorySection.balances);
}
