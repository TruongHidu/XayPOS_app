import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import 'inventory_controller.dart';

/// Keeps the specialised feature guard at the controller boundary as well as UI.
class StockAuditController extends InventoryController {
  StockAuditController({
    required super.session,
    required super.events,
    super.onAccessDenied,
  });

  bool get canView => current && AccessPolicy.canViewStockAudits(session());
  bool get canManage => current && AccessPolicy.canManageStockAudits(session());
  bool get canConfirm =>
      current && AccessPolicy.canConfirmStockAudits(session());

  Future<Result<T>> auditRead<T>(
    String key,
    Future<Result<T>> Function() call,
  ) async {
    if (!canView) return const Error(InventoryController.denied);
    final response = await read(key, call);
    return canView ? response : const Error(InventoryController.denied);
  }
}
