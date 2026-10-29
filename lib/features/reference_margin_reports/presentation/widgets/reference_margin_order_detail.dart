import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart' show authControllerProvider;
import '../../../../core/auth/access_policy.dart';
import '../../../order/domain/entities/order_entities.dart' show ServiceType;
import '../../../reports/domain/entities/report_meta.dart';
import '../../domain/entities/reference_margin_report.dart';
import '../providers/reference_margin_providers.dart';
import 'reference_margin_common.dart';
import 'reference_margin_format.dart';
import 'reference_margin_summary.dart';

String marginServiceLabel(ServiceType type) =>
    type == ServiceType.dineIn ? 'Tại bàn' : 'Mang đi';

/// Shows only the already-loaded row. The dialog closes itself as soon as the
/// authority scope changes or the report capability is revoked.
Future<void> showMarginOrderDetail(
  BuildContext context, {
  required ReferenceMarginOrderRow row,
  required ReportMeta meta,
}) {
  final session = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(authControllerProvider).state.session;
  final scope = AccessPolicy.referenceMarginScope(session);
  final compact =
      MarginLayout.of(MediaQuery.sizeOf(context).width) == MarginLayout.compact;
  return showDialog<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final currentSession = ref.watch(authControllerProvider).state.session;
        final validScope =
            scope == AccessPolicy.referenceMarginScope(currentSession) &&
            AccessPolicy.canViewReferenceMarginReports(currentSession);
        final allowed =
            validScope &&
            ref.watch(
              referenceMarginReportsProvider.select(
                (controller) => controller.allowed,
              ),
            );
        if (!allowed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted &&
                (ModalRoute.of(context)?.isCurrent ?? false)) {
              Navigator.of(context).pop();
            }
          });
          return const SizedBox.shrink();
        }
        final body = _MarginOrderDetailBody(row: row, meta: meta);
        final title = Text('Đối chiếu ${row.orderCode}');
        void close() => Navigator.of(context).pop();
        if (compact) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                title: title,
                actions: [
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: close,
                    child: const Text('Đóng'),
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: body,
              ),
            ),
          );
        }
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: MediaQuery.sizeOf(context).height * .9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    child: title,
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: body,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: close,
                      child: const Text('Đóng'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _MarginOrderDetailBody extends StatelessWidget {
  const _MarginOrderDetailBody({required this.row, required this.meta});
  final ReferenceMarginOrderRow row;
  final ReportMeta meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = meta.currencyCode;
    final eligible = row.eligibleItemCount;
    final costed = eligible == 0
        ? 0.0
        : (row.fullyCostedItemCount / eligible).clamp(0.0, 1.0);
    final margin = row.referenceMarginAmount;
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: MarginSectionCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            child,
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MarginCoverageChip(status: row.costCoverageStatus),
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.restaurant_outlined, size: 16),
              label: Text(
                '${marginServiceLabel(row.serviceType)} · ${row.sourceChannel.label}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Hoàn tất: ${marginTimestamp(row.completedAt, meta.timezone)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Dòng đủ giá vốn: ${row.fullyCostedItemCount}/$eligible dòng được xét.',
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: costed, minHeight: 6),
        ),
        section(
          'Cơ cấu doanh số',
          MarginSalesBreakdown(
            subtotal: row.subtotalAmount,
            discount: row.discountAmount,
            tax: row.taxAmount,
            serviceCharge: row.serviceChargeAmount,
            netSales: row.netSalesAmount,
            sales: row.salesAmount,
            currency: currency,
          ),
        ),
        section(
          'Giá vốn & lãi tham chiếu',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MarginAmountRow(
                label: 'Doanh số thuần',
                value: marginMoney(row.netSalesAmount, currency),
              ),
              MarginAmountRow(
                label: '− Giá vốn tham chiếu',
                value: marginMoney(row.referenceCostAmount, currency),
                unknown: row.referenceCostAmount == null,
              ),
              const Divider(height: 8),
              MarginAmountRow(
                label: '= Lãi tham chiếu',
                value: marginMoney(margin, currency),
                emphasis: true,
                negative: margin?.isNegative ?? false,
                unknown: margin == null,
              ),
              MarginAmountRow(
                label: 'Tỷ lệ lãi',
                value: marginPercent(row.referenceMarginPercent),
                unknown: row.referenceMarginPercent == null,
              ),
            ],
          ),
        ),
        if (row.costIssues.isNotEmpty)
          section(
            'Nguyên nhân thiếu giá vốn',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final issue in row.costIssues)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      Icons.report_gmailerrorred_outlined,
                      color: theme.colorScheme.tertiary,
                    ),
                    title: Text(issue.label),
                    subtitle: Text('${issue.code} · ${issue.itemCount} dòng'),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        const MarginNotice(
          message:
              'Giá tham chiếu được chốt khi nhận món. Thay đổi giá hiện tại không bổ sung lại dữ liệu giá vốn cho đơn cũ.',
        ),
      ],
    );
  }
}
