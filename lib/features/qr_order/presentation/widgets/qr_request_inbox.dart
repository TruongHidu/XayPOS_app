import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../order/presentation/widgets/order_widgets.dart';
import '../../domain/entities/qr_request.dart';
import '../providers/qr_request_providers.dart';
import 'qr_inbox_visibility.dart';
import 'qr_request_review_dialog.dart';
import 'qr_request_format.dart';

Future<void> showQrRequestInbox(
  BuildContext context,
  WidgetRef ref, {
  String? tableId,
  Map<String, String> tableNames = const {},
}) => showOrderDialog<void>(
  context,
  ref,
  permission: 'ORDER_VIEW',
  child: QrRequestInbox(tableId: tableId, tableNames: tableNames),
);

class QrRequestInbox extends ConsumerWidget {
  const QrRequestInbox({super.key, this.tableId, this.tableNames = const {}});
  final String? tableId;
  final Map<String, String> tableNames;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(qrInboxProvider);
    final rows = inbox.pending
        .where((r) => tableId == null || r.tableId == tableId)
        .toList();
    final selectedName = tableNames[tableId];
    return QrInboxVisibility(
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 900,
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedName == null
                            ? 'Yêu cầu QR tại bàn'
                            : 'Yêu cầu QR · $selectedName',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng yêu cầu QR',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: inbox.refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      const Text(
                        'Khách đang chờ nhà hàng duyệt. Món chưa được tính vào hóa đơn hoặc gửi bếp.',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('${rows.length} yêu cầu chờ duyệt'),
                          OutlinedButton.icon(
                            onPressed: inbox.loading || inbox.coolingDown
                                ? null
                                : inbox.refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tải lại yêu cầu'),
                          ),
                        ],
                      ),
                      if (inbox.loading) const LinearProgressIndicator(),
                      OrderFailurePanel(failure: inbox.failure),
                      if (inbox.failure != null && inbox.lastUpdated != null)
                        const Text(
                          'Danh sách đang giữ dữ liệu lần tải trước. Hãy tải lại trước khi đối chiếu.',
                        ),
                      if (!inbox.loading && rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Text('Không có yêu cầu QR chờ duyệt.'),
                        ),
                      for (final row in rows)
                        _RequestCard(
                          request: row,
                          tableName:
                              tableNames[row.tableId] ??
                              'Bàn ${shortQrId(row.tableId)}',
                          onTap: () async {
                            await showOrderDialog<void>(
                              context,
                              ref,
                              permission: 'ORDER_VIEW',
                              child: QrRequestReviewDialog(
                                id: row.id,
                                tableName:
                                    tableNames[row.tableId] ??
                                    'Bàn ${shortQrId(row.tableId)}',
                              ),
                            );
                            if (context.mounted && inbox.current) {
                              await inbox.refresh();
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.tableName,
    required this.onTap,
  });
  final QrRequest request;
  final String tableName;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('qr-request-${request.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(tableName, style: Theme.of(context).textTheme.titleMedium),
                const Chip(
                  avatar: Icon(Icons.qr_code_2, size: 18),
                  label: Text('Chờ duyệt'),
                ),
                Text('Gửi lúc ${qrRequestTime(request.createdAt)}'),
              ],
            ),
            if (request.customerName?.isNotEmpty == true)
              Text('Khách: ${request.customerName}'),
            Text(
              request.items
                  .map((line) => '${line.quantity} ${line.unit} ${line.name}')
                  .join(' · '),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (request.note?.isNotEmpty == true)
              Text('Ghi chú: ${request.note}'),
            const SizedBox(height: 8),
            Text(
              'Tạm tính yêu cầu: ${orderMoney(BigInt.from(request.estimatedAmount.minorUnits), currency: request.currency)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const Text(
              'Xem và duyệt',
              style: TextStyle(fontSize: 13, color: Color(0xFF1565C0)),
            ),
          ],
        ),
      ),
    ),
  );
}
