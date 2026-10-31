import 'package:flutter/material.dart';
import '../../domain/entities/permission_catalog_item.dart';

/// Plain Vietnamese wording for owners; unknown codes keep the server's name.
const _permissionNames = {
  'DASHBOARD_VIEW': 'Xem trang tổng quan',
  'MENU_VIEW': 'Xem thực đơn',
  'MENU_CREATE': 'Thêm món và nhóm món',
  'MENU_UPDATE': 'Sửa món và nhóm món',
  'MENU_DELETE': 'Xóa món và nhóm món',
  'INGREDIENT_VIEW': 'Xem nguyên liệu',
  'INGREDIENT_CREATE': 'Thêm nguyên liệu',
  'INGREDIENT_UPDATE': 'Sửa nguyên liệu',
  'INGREDIENT_DELETE': 'Xóa nguyên liệu',
  'RECIPE_VIEW': 'Xem công thức',
  'RECIPE_CREATE': 'Thêm công thức',
  'RECIPE_UPDATE': 'Sửa công thức',
  'RECIPE_DELETE': 'Xóa công thức',
  'ORDER_VIEW': 'Xem đơn hàng',
  'ORDER_CREATE': 'Tạo đơn và gọi món',
  'ORDER_UPDATE': 'Sửa đơn hàng',
  'ORDER_CANCEL': 'Hủy đơn hàng',
  'ORDER_COMPLETE': 'Hoàn tất đơn hàng',
  'PAYMENT_VIEW': 'Xem thanh toán',
  'PAYMENT_CREATE': 'Thu tiền',
  'PAYMENT_CONFIRM': 'Xác nhận thanh toán',
  'TABLE_VIEW': 'Xem bàn và khu vực',
  'TABLE_CREATE': 'Thêm bàn và khu vực',
  'TABLE_UPDATE': 'Sửa bàn và khu vực',
  'TABLE_OPEN': 'Mở bàn',
  'TABLE_CLOSE': 'Đóng bàn',
  'TABLE_TRANSFER': 'Chuyển và gộp bàn',
  'KITCHEN_VIEW': 'Xem màn hình bếp',
  'KITCHEN_START_COOKING': 'Bắt đầu chế biến món',
  'KITCHEN_MARK_READY': 'Báo món đã xong',
  'QR_MENU_VIEW': 'Xem thực đơn QR',
  'INVENTORY_VIEW': 'Xem tồn kho',
  'INVENTORY_RECEIVE': 'Nhập kho',
  'INVENTORY_ISSUE': 'Xuất kho',
  'INVENTORY_ADJUST': 'Điều chỉnh tồn kho',
  'INVENTORY_THRESHOLD_UPDATE': 'Đặt ngưỡng tồn thấp',
  'INVENTORY_ALERT_ACKNOWLEDGE': 'Xác nhận cảnh báo tồn thấp',
  'STOCK_AUDIT_MANAGE': 'Tạo và đếm phiếu kiểm kê',
  'STOCK_AUDIT_CONFIRM': 'Chốt phiếu kiểm kê',
  'WAREHOUSE_CREATE': 'Thêm kho',
  'WAREHOUSE_UPDATE': 'Sửa kho',
  'WAREHOUSE_DELETE': 'Xóa kho',
  'CASHBOOK_VIEW': 'Xem sổ quỹ',
  'CASHBOOK_CREATE': 'Ghi nhận phiếu chi',
  'CASHBOOK_VOID': 'Hủy phiếu chi',
  'REPORT_DAILY_VIEW': 'Xem báo cáo theo ngày',
  'REPORT_DETAIL_VIEW': 'Xem báo cáo chi tiết',
  'STAFF_VIEW': 'Xem nhân viên',
  'STAFF_CREATE': 'Thêm nhân viên',
  'STAFF_UPDATE': 'Sửa thông tin nhân viên',
  'STAFF_DISABLE': 'Khóa và mở khóa nhân viên',
  'STAFF_PERMISSION_MANAGE': 'Phân quyền nhân viên',
  'RESTAURANT_SETTINGS_VIEW': 'Xem cài đặt nhà hàng',
};

/// Display group per catalog module, in the order owners think about the shop.
const _groups = <String, (String, IconData)>{
  'DASHBOARD': ('Tổng quan', Icons.dashboard_outlined),
  'ORDER': ('Đơn hàng', Icons.receipt_long_outlined),
  'PAYMENT': ('Thanh toán', Icons.payments_outlined),
  'TABLE': ('Bàn', Icons.table_restaurant_outlined),
  'KITCHEN': ('Bếp', Icons.soup_kitchen_outlined),
  'QR': ('Gọi món QR', Icons.qr_code_2),
  'MENU': ('Thực đơn', Icons.restaurant_menu),
  'INGREDIENT': ('Nguyên liệu', Icons.kitchen_outlined),
  'RECIPE': ('Công thức', Icons.menu_book_outlined),
  'INVENTORY': ('Kho', Icons.inventory_2_outlined),
  'STOCK': ('Kho', Icons.inventory_2_outlined),
  'WAREHOUSE': ('Kho', Icons.inventory_2_outlined),
  'CASHBOOK': ('Sổ quỹ', Icons.account_balance_wallet_outlined),
  'REPORT': ('Báo cáo', Icons.bar_chart),
  'STAFF': ('Nhân viên', Icons.badge_outlined),
  'RESTAURANT': ('Nhà hàng', Icons.storefront_outlined),
};

String staffPermissionName(PermissionCatalogItem item) =>
    _permissionNames[item.code] ?? item.name;

class StaffPermissionGroup {
  StaffPermissionGroup(this.label, this.icon);
  final String label;
  final IconData icon;
  final items = <PermissionCatalogItem>[];
}

/// The module is the server's; its code prefix covers unlisted spellings.
List<StaffPermissionGroup> groupStaffPermissions(
  Iterable<PermissionCatalogItem> items,
) {
  final groups = <String, StaffPermissionGroup>{};
  for (final item in items) {
    final known =
        _groups[item.module.toUpperCase()] ?? _groups[item.code.split('_')[0]];
    final label = known?.$1 ?? item.module;
    groups
        .putIfAbsent(
          label,
          () => StaffPermissionGroup(label, known?.$2 ?? Icons.tune),
        )
        .items
        .add(item);
  }
  final order = _groups.values.map((group) => group.$1).toList();
  int rank(StaffPermissionGroup group) {
    final index = order.indexOf(group.label);
    return index < 0 ? order.length : index;
  }

  return groups.values.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
}
