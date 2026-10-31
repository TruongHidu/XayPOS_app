import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../../domain/entities/report_enums.dart';
import '../../domain/entities/report_order_row.dart';
import '../../domain/entities/report_page.dart';

class ReportOrdersTable extends StatelessWidget {
  final ReportPage<ReportOrderRow> page;
  final String currencyCode;
  final ReportDateBasis dateBasis;
  final OrderStatus? status;
  final OrderPaymentStatus? paymentStatus;
  final ReportOrderSortBy sortBy;
  final ReportSortDirection direction;
  final bool canViewOrderDetail;
  final ValueChanged<ReportDateBasis> onDateBasisChanged;
  final ValueChanged<OrderStatus?> onStatusChanged;
  final ValueChanged<OrderPaymentStatus?> onPaymentStatusChanged;
  final ValueChanged<ReportOrderSortBy> onSortByChanged;
  final VoidCallback onToggleDirection;
  final VoidCallback onLoadMore;
  final String? loadMoreFailure;

  const ReportOrdersTable({
    super.key,
    required this.page,
    required this.currencyCode,
    required this.dateBasis,
    required this.status,
    required this.paymentStatus,
    required this.sortBy,
    required this.direction,
    required this.canViewOrderDetail,
    required this.onDateBasisChanged,
    required this.onStatusChanged,
    required this.onPaymentStatusChanged,
    required this.onSortByChanged,
    required this.onToggleDirection,
    required this.onLoadMore,
    this.loadMoreFailure,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Controls header
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fact_check_outlined,
                      size: 22,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Đơn đối chiếu ($currencyCode)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Date Basis Selector
                    DropdownButton<ReportDateBasis>(
                      value: dateBasis,
                      items: const [
                        DropdownMenuItem(
                          value: ReportDateBasis.created,
                          child: Text('Cơ sở: Ngày tạo đơn'),
                        ),
                        DropdownMenuItem(
                          value: ReportDateBasis.completed,
                          child: Text('Cơ sở: Ngày hoàn tất'),
                        ),
                        DropdownMenuItem(
                          value: ReportDateBasis.cancelled,
                          child: Text('Cơ sở: Ngày hủy đơn'),
                        ),
                        DropdownMenuItem(
                          value: ReportDateBasis.paid,
                          child: Text('Cơ sở: Ngày thu tiền'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) onDateBasisChanged(val);
                      },
                    ),
                    // Status Filter (disabled/locked if dateBasis is completed or cancelled)
                    DropdownButton<OrderStatus?>(
                      value: status,
                      hint: const Text('Trạng thái đơn: Tất cả'),
                      items: _buildStatusDropdownItems(),
                      onChanged:
                          (dateBasis == ReportDateBasis.completed ||
                              dateBasis == ReportDateBasis.cancelled)
                          ? null
                          : onStatusChanged,
                    ),
                    // Payment Status Filter
                    DropdownButton<OrderPaymentStatus?>(
                      value: paymentStatus,
                      hint: const Text('Thanh toán: Tất cả'),
                      items: const [
                        DropdownMenuItem(
                          value: null,
                          child: Text('Thanh toán: Tất cả'),
                        ),
                        DropdownMenuItem(
                          value: OrderPaymentStatus.unpaid,
                          child: Text('Chưa thanh toán'),
                        ),
                        DropdownMenuItem(
                          value: OrderPaymentStatus.partiallyPaid,
                          child: Text('Thanh toán 1 phần'),
                        ),
                        DropdownMenuItem(
                          value: OrderPaymentStatus.paid,
                          child: Text('Đã thanh toán đủ'),
                        ),
                        DropdownMenuItem(
                          value: OrderPaymentStatus.partiallyRefunded,
                          child: Text('Hoàn tiền 1 phần'),
                        ),
                        DropdownMenuItem(
                          value: OrderPaymentStatus.refunded,
                          child: Text('Đã hoàn tiền'),
                        ),
                      ],
                      onChanged: onPaymentStatusChanged,
                    ),
                    // Sort By Dropdown
                    DropdownButton<ReportOrderSortBy>(
                      value: sortBy,
                      items: const [
                        DropdownMenuItem(
                          value: ReportOrderSortBy.reportEventAt,
                          child: Text('Sắp: Mốc sự kiện'),
                        ),
                        DropdownMenuItem(
                          value: ReportOrderSortBy.totalAmount,
                          child: Text('Sắp: Tổng giá trị'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) onSortByChanged(val);
                      },
                    ),
                    // Direction toggle
                    IconButton.outlined(
                      tooltip: direction == ReportSortDirection.desc
                          ? 'Mới nhất / Lớn nhất trước'
                          : 'Cũ nhất / Nhỏ nhất trước',
                      icon: Icon(
                        direction == ReportSortDirection.desc
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        size: 18,
                      ),
                      onPressed: onToggleDirection,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Content
            if (page.content.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 40),
                alignment: Alignment.center,
                child: Text(
                  'Không có đơn đối chiếu nào thỏa mãn điều kiện lọc.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            else if (isMobile)
              _buildMobileList(context)
            else
              _buildDesktopTable(context),

            if (page.content.isNotEmpty)
              EndlessListFooter(
                hasMore: page.hasNextPage,
                failureMessage: loadMoreFailure,
                endLabel: 'Đã hiển thị tất cả ${page.totalElements} đơn',
                onLoadMore: onLoadMore,
              ),
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<OrderStatus?>> _buildStatusDropdownItems() {
    if (dateBasis == ReportDateBasis.completed) {
      return const [
        DropdownMenuItem(
          value: OrderStatus.completed,
          child: Text('Trạng thái: Hoàn tất'),
        ),
      ];
    }
    if (dateBasis == ReportDateBasis.cancelled) {
      return const [
        DropdownMenuItem(
          value: OrderStatus.cancelled,
          child: Text('Trạng thái: Đã hủy'),
        ),
      ];
    }
    return const [
      DropdownMenuItem(value: null, child: Text('Trạng thái đơn: Tất cả')),
      DropdownMenuItem(value: OrderStatus.open, child: Text('Mới tạo (Open)')),
      DropdownMenuItem(
        value: OrderStatus.confirmed,
        child: Text('Đã xác nhận'),
      ),
      DropdownMenuItem(value: OrderStatus.completed, child: Text('Hoàn tất')),
      DropdownMenuItem(value: OrderStatus.cancelled, child: Text('Đã hủy')),
    ];
  }

  Widget _buildDesktopTable(BuildContext context) {
    final eventLabel = _getEventLabel(dateBasis);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          const DataColumn(label: Text('Mã đơn')),
          const DataColumn(label: Text('Loại')),
          const DataColumn(label: Text('Kênh')),
          const DataColumn(label: Text('Trạng thái')),
          const DataColumn(label: Text('Thanh toán')),
          const DataColumn(label: Text('Tổng giá trị'), numeric: true),
          const DataColumn(label: Text('Tiền thu trong kỳ'), numeric: true),
          DataColumn(label: Text(eventLabel)),
          if (canViewOrderDetail) const DataColumn(label: Text('Thao tác')),
        ],
        rows: page.content.map((row) {
          return DataRow(
            key: ValueKey(row.orderId),
            cells: [
              DataCell(
                Text(
                  row.orderCode,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataCell(Text(_formatServiceType(row.serviceType))),
              DataCell(Text(_formatSourceChannel(row.sourceChannel))),
              DataCell(_buildStatusBadge(row.status)),
              DataCell(_buildPaymentStatusBadge(row.paymentStatus)),
              DataCell(
                Text(
                  row.totalAmount.formatted,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              DataCell(
                Text(
                  row.collectedAmountInRange.formatted,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: row.collectedAmountInRange.minorUnits > BigInt.zero
                        ? const Color(0xFF10B981)
                        : null,
                  ),
                ),
              ),
              DataCell(Text(_formatDateTime(row.reportEventAt))),
              if (canViewOrderDetail)
                DataCell(
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    tooltip: 'Xem chi tiết đơn',
                    onPressed: () {
                      context.push('/app/orders/${row.orderId}');
                    },
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMobileList(BuildContext context) {
    final theme = Theme.of(context);
    final eventLabel = _getEventLabel(dateBasis);

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: page.content.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (context, index) {
        final row = page.content[index];

        return Column(
          key: ValueKey(row.orderId),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      row.orderCode,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${_formatServiceType(row.serviceType)} - ${_formatSourceChannel(row.sourceChannel)})',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                if (canViewOrderDetail)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    tooltip: 'Xem chi tiết đơn',
                    onPressed: () {
                      context.push('/app/orders/${row.orderId}');
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildStatusBadge(row.status),
                _buildPaymentStatusBadge(row.paymentStatus),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tổng đơn: ${row.totalAmount.formatted}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Thu trong kỳ: ${row.collectedAmountInRange.formatted}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            row.collectedAmountInRange.minorUnits > BigInt.zero
                            ? const Color(0xFF10B981)
                            : theme.colorScheme.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  '$eventLabel:\n${_formatDateTime(row.reportEventAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  textAlign: TextAlign.end,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusBadge(OrderStatus status) {
    Color bg;
    Color fg;
    String text;

    switch (status) {
      case OrderStatus.open:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade700;
        text = 'Mới tạo';
      case OrderStatus.confirmed:
        bg = Colors.amber.shade50;
        fg = Colors.amber.shade900;
        text = 'Đã xác nhận';
      case OrderStatus.preparing:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        text = 'Đang chế biến';
      case OrderStatus.ready:
        bg = Colors.cyan.shade50;
        fg = Colors.cyan.shade800;
        text = 'Sẵn sàng';
      case OrderStatus.served:
        bg = Colors.teal.shade50;
        fg = Colors.teal.shade800;
        text = 'Đã phục vụ';
      case OrderStatus.completed:
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        text = 'Hoàn tất';
      case OrderStatus.cancelled:
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        text = 'Đã hủy';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildPaymentStatusBadge(OrderPaymentStatus paymentStatus) {
    Color bg;
    Color fg;
    String text;

    switch (paymentStatus) {
      case OrderPaymentStatus.unpaid:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade700;
        text = 'Chưa thanh toán';
      case OrderPaymentStatus.partiallyPaid:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        text = 'Một phần';
      case OrderPaymentStatus.paid:
        bg = const Color(0xFF10B981).withValues(alpha: 0.12);
        fg = const Color(0xFF059669);
        text = 'Đã thanh toán';
      case OrderPaymentStatus.partiallyRefunded:
        bg = Colors.purple.shade50;
        fg = Colors.purple.shade700;
        text = 'Hoàn một phần';
      case OrderPaymentStatus.refunded:
        bg = Colors.purple.shade100;
        fg = Colors.purple.shade800;
        text = 'Đã hoàn tiền';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _getEventLabel(ReportDateBasis basis) {
    switch (basis) {
      case ReportDateBasis.created:
        return 'Thời điểm tạo';
      case ReportDateBasis.completed:
        return 'Thời điểm hoàn tất';
      case ReportDateBasis.cancelled:
        return 'Thời điểm hủy';
      case ReportDateBasis.paid:
        return 'Thu tiền gần nhất';
    }
  }

  String _formatServiceType(ServiceType type) {
    switch (type) {
      case ServiceType.dineIn:
        return 'Ăn tại bàn';
      case ServiceType.takeaway:
        return 'Mang đi';
    }
  }

  String _formatSourceChannel(ReportSourceChannel? channel) {
    if (channel == null) return '-';
    switch (channel) {
      case ReportSourceChannel.cashier:
        return 'Thu ngân';
      case ReportSourceChannel.waiter:
        return 'Phục vụ';
      case ReportSourceChannel.qrStatic:
        return 'QR tĩnh';
      case ReportSourceChannel.qrTable:
        return 'QR bàn';
    }
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }
}
