import 'package:flutter_riverpod/legacy.dart';

import '../../../../app/providers.dart';
import '../../domain/use_cases/inventory_use_cases.dart';
import '../controllers/inventory_low_stock_count_controller.dart';

final inventoryLowStockCountProvider =
    ChangeNotifierProvider.autoDispose<InventoryLowStockCountController>((ref) {
      ref.watch(inventoryScopeProvider);
      final auth = ref.read(authControllerProvider);
      final controller = InventoryLowStockCountController(
        session: () => auth.state.session,
        events: ref.read(inventoryEventsProvider),
        get: GetLowStockBalances(ref.watch(inventoryBalanceRepositoryProvider)),
        foreground: ref.read(realtimeForegroundProvider),
        onAccessDenied: (_) => auth.revalidateAccess(),
      );
      ref.listen(realtimeForegroundProvider, (_, foreground) {
        controller.setForeground(foreground);
      });
      Future.microtask(controller.load);
      return controller;
    });
