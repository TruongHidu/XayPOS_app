import 'package:flutter/widgets.dart';

import 'inventory_section_screen.dart';

class InventoryDocumentsScreen extends StatelessWidget {
  const InventoryDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const InventorySectionScreen(section: InventorySection.documents);
}
