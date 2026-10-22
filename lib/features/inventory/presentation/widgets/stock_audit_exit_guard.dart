import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import 'inventory_widgets.dart';
import 'stock_audit_widgets.dart';

/// Used by GoRoute.onExit, so AppShell menu navigation has the same protection
/// as Back. Leaving with retention is explicit and never changes server data.
Future<bool> confirmStockAuditExit(
  BuildContext context,
  Ref ref,
  String? auditId,
) async {
  final session = ref.read(authControllerProvider).state.session;
  if (!AccessPolicy.canViewStockAudits(session)) return true;
  final scope = AccessPolicy.inventoryScope(session);
  final detail = auditId == null
      ? null
      : ref.read(stockAuditDetailProvider(auditId));
  final create = auditId == null ? ref.read(stockAuditCreateProvider) : null;
  if (detail?.busy == true || create?.busy == true) return false;
  final dirty = detail?.dirty ?? (create!.dirty && create.result == null);
  final uncertain = detail?.requiresReview ?? create!.uncertain;
  if (!dirty && !uncertain) return true;
  if (!context.mounted) return false;
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StockAuditScopeGuard(
      scope: scope,
      child: InventoryDialogFrame(
        title: uncertain
            ? 'Yêu cầu đang chờ đối chiếu'
            : 'Còn bản nhập chưa lưu',
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('stay'),
            child: const Text('Ở lại'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop('keep'),
            child: const Text('Rời và giữ bản nhập'),
          ),
          if (detail != null && detail.canSaveDrafts && !uncertain)
            FilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('Lưu và rời'),
            ),
          if (!uncertain)
            TextButton(
              onPressed: () => Navigator.of(context).pop('discard'),
              child: const Text('Bỏ bản nhập và rời'),
            ),
        ],
        children: [
          Text(
            uncertain
                ? 'Kết quả thao tác chưa được xác minh. Nếu rời màn hình, yêu cầu ban đầu và bản nhập vẫn được giữ trong phiên làm việc này để tiếp tục đối chiếu.'
                : 'Bản nhập được giữ khi chuyển trang hoặc quay lại trong cùng phiên làm việc. Đăng xuất hoặc đổi tài khoản/quyền sẽ xóa bản nhập chưa lưu.',
          ),
        ],
      ),
    ),
  );
  if (scope !=
      AccessPolicy.inventoryScope(
        ref.read(authControllerProvider).state.session,
      )) {
    return true;
  }
  if (choice == 'keep') return true;
  if (choice == 'discard') {
    detail?.discardDrafts();
    create?.begin();
    return true;
  }
  if (choice == 'save' && detail != null) {
    return await detail.saveDrafts() is Success;
  }
  return false;
}
