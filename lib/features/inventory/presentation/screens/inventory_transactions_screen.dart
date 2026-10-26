import 'package:flutter/widgets.dart';

import 'inventory_section_screen.dart';

class InventoryTransactionsScreen extends StatelessWidget {
  const InventoryTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const InventorySectionScreen(section: InventorySection.transactions);
}
