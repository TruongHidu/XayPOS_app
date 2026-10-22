import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../domain/entities/inventory_alert.dart';
import '../../domain/entities/inventory_instant_range.dart';
import 'inventory_widgets.dart';
import 'stock_widgets.dart';

String inventoryAlertLocation(String id) =>
    '/app/inventory/alerts/${Uri.encodeComponent(id)}';
String alertMoment(DateTime value) {
  final local = value.toLocal();
  return '${stockDay(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class InventoryAlertBadge extends StatelessWidget {
  const InventoryAlertBadge(this.status, {super.key});
  final InventoryAlertStatus status;
  @override
  Widget build(BuildContext context) => InventoryBadge(
    status.label,
    warning: status == InventoryAlertStatus.open,
    positive: status == InventoryAlertStatus.resolved,
  );
}

/// Dialogs also enforce the alert feature. The generic inventory guard alone
/// cannot protect a date picker after LOW_STOCK_ALERT is revoked.
class InventoryAlertScopeGuard extends ConsumerWidget {
  const InventoryAlertScopeGuard({
    super.key,
    required this.scope,
    required this.child,
  });
  final Object? scope;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (scope != AccessPolicy.inventoryScope(session) ||
        !AccessPolicy.canViewInventoryAlerts(session)) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && route?.isActive == true) {
          Navigator.of(context).removeRoute(route!);
        }
      });
      return const SizedBox.shrink();
    }
    return child;
  }
}

class InventoryAlertDateFilter extends ConsumerWidget {
  const InventoryAlertDateFilter({
    super.key,
    required this.range,
    required this.changed,
  });
  final InventoryInstantRange? range;
  final ValueChanged<InventoryInstantRange?> changed;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final from = range?.from?.toLocal(), exclusive = range?.to?.toLocal();
    // The stored end is exclusive. Subtract only for the date-picker label;
    // requests always send the original instant unchanged.
    final last = exclusive?.subtract(const Duration(microseconds: 1));
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_outlined),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          label: Text(
            from == null && last == null
                ? 'Ngày phát cảnh báo'
                : from == null
                ? 'Đến ${stockDay(last!)}'
                : last == null
                ? 'Từ ${stockDay(from)}'
                : '${stockDay(from)} – ${stockDay(last)}',
          ),
          onPressed: () async {
            final session = ref.read(authControllerProvider).state.session;
            if (!AccessPolicy.canViewInventoryAlerts(session)) return;
            final scope = AccessPolicy.inventoryScope(session);
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(1),
              lastDate: DateTime(9999, 12, 30),
              initialDateRange: from == null || last == null
                  ? null
                  : DateTimeRange(start: from, end: last),
              helpText: 'Chọn ngày phát cảnh báo',
              saveText: 'Áp dụng',
              builder: (_, child) =>
                  InventoryAlertScopeGuard(scope: scope, child: child!),
            );
            if (context.mounted &&
                scope == ref.read(inventoryScopeProvider) &&
                AccessPolicy.canViewInventoryAlerts(
                  ref.read(authControllerProvider).state.session,
                ) &&
                picked != null) {
              changed(InventoryInstantRange.days(picked.start, picked.end));
            }
          },
        ),
        if (range != null)
          IconButton(
            tooltip: 'Bỏ lọc ngày phát',
            onPressed: () => changed(null),
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }
}
