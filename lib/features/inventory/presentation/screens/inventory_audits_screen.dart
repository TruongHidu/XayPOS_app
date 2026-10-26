import 'package:flutter/widgets.dart';

import 'inventory_section_screen.dart';

class InventoryAuditsScreen extends StatelessWidget {
  const InventoryAuditsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const InventorySectionScreen(section: InventorySection.audits);
}
