/// Vietnamese names for package feature codes; unknown codes show as sent.
const packageFeatureLabels = {
  'MENU_MANAGEMENT': 'Quản lý thực đơn',
  'POS_QUICK_ORDER': 'Gọi món nhanh',
  'ORDER_MANAGEMENT': 'Quản lý đơn hàng',
  'PAYMENT_MANAGEMENT': 'Thanh toán',
  'DAILY_REVENUE': 'Doanh thu ngày',
  'DETAIL_REPORT': 'Báo cáo chi tiết',
  'QR_MENU_VIEW': 'Thực đơn QR',
  'QR_STATIC_ORDER': 'Gọi món qua QR chung',
  'QR_TABLE_ORDER': 'Gọi món qua QR tại bàn',
  'RECEIPT_PRINT': 'In hóa đơn',
  'RECEIPT_REPRINT': 'In lại hóa đơn',
  'TABLE_MANAGEMENT': 'Quản lý bàn',
  'STAFF_MANAGEMENT': 'Quản lý nhân viên',
  'STAFF_PERMISSION': 'Phân quyền nhân viên',
  'KITCHEN_DISPLAY': 'Màn hình bếp',
  'KITCHEN_TICKET_PRINT': 'In phiếu bếp',
  'KITCHEN_TICKET_REPRINT': 'In lại phiếu bếp',
  'INVENTORY_MANAGEMENT': 'Quản lý kho',
  'RECIPE_MANAGEMENT': 'Công thức món',
  'LOW_STOCK_ALERT': 'Cảnh báo tồn thấp',
  'STOCK_AUDIT': 'Kiểm kê',
  'ADVANCED_ANALYTICS': 'Phân tích nâng cao',
  'AI_DEMAND_FORECAST': 'Dự báo nhu cầu (AI)',
  'AI_MENU_RECOMMENDATION': 'Gợi ý thực đơn (AI)',
};

String packageFeatureLabel(String code) => packageFeatureLabels[code] ?? code;
