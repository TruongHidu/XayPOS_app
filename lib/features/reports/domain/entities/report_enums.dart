enum ReportGranularity {
  day('DAY', 'Theo ngày'),
  month('MONTH', 'Theo tháng');

  const ReportGranularity(this.apiCode, this.label);
  final String apiCode;
  final String label;

  static ReportGranularity fromCode(String? code) {
    if (code == 'MONTH') return ReportGranularity.month;
    return ReportGranularity.day;
  }
}

enum ReportDateBasis {
  created('CREATED', 'Ngày tạo đơn'),
  completed('COMPLETED', 'Ngày hoàn tất'),
  cancelled('CANCELLED', 'Ngày hủy đơn'),
  paid('PAID', 'Ngày thu tiền');

  const ReportDateBasis(this.apiCode, this.label);
  final String apiCode;
  final String label;

  static ReportDateBasis fromCode(String? code) {
    return switch (code?.toUpperCase()) {
      'COMPLETED' => ReportDateBasis.completed,
      'CANCELLED' => ReportDateBasis.cancelled,
      'PAID' => ReportDateBasis.paid,
      _ => ReportDateBasis.created,
    };
  }
}

enum ReportSourceChannel {
  cashier('CASHIER', 'Thu ngân'),
  waiter('WAITER', 'Nhân viên'),
  qrStatic('QR_STATIC', 'QR tĩnh'),
  qrTable('QR_TABLE', 'QR tại bàn');

  const ReportSourceChannel(this.apiCode, this.label);
  final String apiCode;
  final String label;

  static ReportSourceChannel? fromCode(String? code) {
    if (code == null || code.trim().isEmpty) return null;
    return switch (code.toUpperCase()) {
      'CASHIER' => ReportSourceChannel.cashier,
      'WAITER' => ReportSourceChannel.waiter,
      'QR_STATIC' => ReportSourceChannel.qrStatic,
      'QR_TABLE' => ReportSourceChannel.qrTable,
      _ => null,
    };
  }
}

enum ReportPaymentMethod {
  cash('CASH', 'Tiền mặt'),
  transfer('TRANSFER', 'Chuyển khoản');

  const ReportPaymentMethod(this.apiCode, this.label);
  final String apiCode;
  final String label;

  static ReportPaymentMethod fromCode(String? code) {
    if (code?.toUpperCase() == 'TRANSFER') return ReportPaymentMethod.transfer;
    return ReportPaymentMethod.cash;
  }
}

enum TopItemSortBy {
  quantity('quantity', 'Số lượng bán'),
  itemSalesAmount('itemSalesAmount', 'Tiền bán món');

  const TopItemSortBy(this.apiCode, this.label);
  final String apiCode;
  final String label;

  static TopItemSortBy fromCode(String? code) {
    if (code == 'itemSalesAmount') return TopItemSortBy.itemSalesAmount;
    return TopItemSortBy.quantity;
  }
}

enum ReportOrderSortBy {
  reportEventAt('reportEventAt', 'Thời điểm sự kiện'),
  totalAmount('totalAmount', 'Tổng giá trị đơn');

  const ReportOrderSortBy(this.apiCode, this.label);
  final String apiCode;
  final String label;

  static ReportOrderSortBy fromCode(String? code) {
    if (code == 'totalAmount') return ReportOrderSortBy.totalAmount;
    return ReportOrderSortBy.reportEventAt;
  }
}

enum ReportSortDirection {
  desc('desc', 'Giảm dần'),
  asc('asc', 'Tăng dần');

  const ReportSortDirection(this.apiCode, this.label);
  final String apiCode;
  final String label;

  static ReportSortDirection fromCode(String? code) {
    if (code?.toLowerCase() == 'asc') return ReportSortDirection.asc;
    return ReportSortDirection.desc;
  }

  ReportSortDirection toggled() => this == ReportSortDirection.desc
      ? ReportSortDirection.asc
      : ReportSortDirection.desc;
}
