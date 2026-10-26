import 'package:flutter/widgets.dart';

import 'inventory_section_screen.dart';

class InventoryAlertsScreen extends StatelessWidget {
  const InventoryAlertsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const InventorySectionScreen(section: InventorySection.alerts);
}
