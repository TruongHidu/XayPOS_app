enum CostCoverageStatus {
  complete('COMPLETE', 'Đủ giá vốn'),
  partial('PARTIAL', 'Một phần đủ giá vốn'),
  unavailable('UNAVAILABLE', 'Chưa đủ giá vốn'),
  noData('NO_DATA', 'Chưa có đơn hoàn tất');

  const CostCoverageStatus(this.code, this.label);
  final String code, label;
}

enum CostCoverageFilter {
  all('ALL', 'Tất cả đơn'),
  complete('COMPLETE', 'Đủ giá vốn'),
  excluded('EXCLUDED', 'Thiếu giá vốn');

  const CostCoverageFilter(this.code, this.label);
  final String code, label;
}

enum ReferenceMarginOrderSort {
  completedAt('completedAt', 'Thời điểm hoàn tất'),
  netSalesAmount('netSalesAmount', 'Doanh số thuần'),
  referenceCostAmount('referenceCostAmount', 'Giá vốn tham chiếu'),
  referenceMarginAmount('referenceMarginAmount', 'Lãi tham chiếu');

  const ReferenceMarginOrderSort(this.code, this.label);
  final String code, label;
}
