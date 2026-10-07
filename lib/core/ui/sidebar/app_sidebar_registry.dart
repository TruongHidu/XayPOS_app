import 'package:flutter/material.dart';

import 'sidebar_category.dart';
import 'sidebar_menu_item.dart';

/// Single source of truth for every sidebar menu item in the app.
///
/// Items are organised into functional categories rather than by role.
/// At runtime the sidebar filters this list based on the user's
/// effective permissions and subscription features, so each user
/// sees exactly the items they are allowed to access.
abstract final class AppSidebarRegistry {
  static const List<SidebarCategory> categories = [
    // ── Bán hàng & Vận hành ──────────────────────────────────
    SidebarCategory(
      title: 'BÁN HÀNG & VẬN HÀNH',
      items: [
        SidebarMenuItem(
          id: 'orders',
          label: 'Đơn hàng',
          icon: Icons.receipt_long_outlined,
          routePath: '/app/orders',
          requiredPermissions: ['ORDER_VIEW'],
          requiredFeatures: ['ORDER_MANAGEMENT'],
        ),
        SidebarMenuItem(
          id: 'order-create',
          label: 'Gọi món',
          icon: Icons.add_shopping_cart_outlined,
          routePath: '/app/order-create',
          requiredPermissions: ['ORDER_CREATE'],
          requiredFeatures: ['ORDER_MANAGEMENT'],
        ),
        SidebarMenuItem(
          id: 'payment',
          label: 'Thanh toán',
          icon: Icons.payments_outlined,
          routePath: '/app/payment',
          requiredPermissions: ['PAYMENT_VIEW'],
          requiredFeatures: ['PAYMENT_MANAGEMENT'],
        ),
      ],
    ),

    // ── Bếp ──────────────────────────────────────────────────
    SidebarCategory(
      title: 'BẾP',
      items: [
        SidebarMenuItem(
          id: 'kitchen-display',
          label: 'Màn hình bếp',
          icon: Icons.monitor_outlined,
          routePath: '/app/kitchen',
          requiredPermissions: ['KITCHEN_VIEW'],
          requiredFeatures: ['KITCHEN_DISPLAY'],
        ),
        SidebarMenuItem(
          id: 'dish-status',
          label: 'Cập nhật trạng thái món',
          icon: Icons.check_circle_outlined,
          routePath: '/app/dish-status',
          requiredPermissions: ['KITCHEN_UPDATE'],
          requiredFeatures: ['KITCHEN_DISPLAY'],
        ),
      ],
    ),

    // ── Quản lý ──────────────────────────────────────────────
    SidebarCategory(
      title: 'QUẢN LÝ',
      items: [
        SidebarMenuItem(
          id: 'dashboard',
          label: 'Tổng quan',
          icon: Icons.dashboard_outlined,
          routePath: '/app/dashboard',
          requiredPermissions: ['DASHBOARD_VIEW'],
          requiredFeatures: ['REPORTING'],
        ),
        SidebarMenuItem(
          id: 'staff',
          label: 'Nhân viên',
          icon: Icons.people_outlined,
          routePath: '/app/staff',
          requiredPermissions: ['STAFF_VIEW'],
          requiredFeatures: ['STAFF_MANAGEMENT'],
        ),
        SidebarMenuItem(
          id: 'menu',
          label: 'Thực đơn',
          icon: Icons.restaurant_menu_outlined,
          routePath: '/app/menu',
          requiredPermissions: ['MENU_VIEW'],
          requiredFeatures: ['MENU_MANAGEMENT'],
        ),
        SidebarMenuItem(
          id: 'tables',
          label: 'Sơ đồ bàn',
          icon: Icons.table_restaurant_outlined,
          routePath: '/app/tables',
          requiredPermissions: ['TABLE_VIEW'],
          requiredFeatures: ['TABLE_MANAGEMENT'],
        ),
        SidebarMenuItem(
          id: 'settings',
          label: 'Cài đặt nhà hàng',
          icon: Icons.settings_outlined,
          routePath: '/app/settings',
          requiredPermissions: ['RESTAURANT_SETTINGS_VIEW'],
          requiredFeatures: ['RESTAURANT_SETTINGS'],
        ),
      ],
    ),

    // ── Báo cáo & Kho ───────────────────────────────────────
    SidebarCategory(
      title: 'BÁO CÁO & KHO',
      items: [
        SidebarMenuItem(
          id: 'daily-revenue',
          label: 'Doanh thu ngày',
          icon: Icons.bar_chart_outlined,
          routePath: '/app/daily-revenue',
          requiredPermissions: ['REPORT_DAILY_VIEW'],
          requiredFeatures: ['DAILY_REVENUE'],
        ),
        SidebarMenuItem(
          id: 'reports',
          label: 'Báo cáo',
          icon: Icons.assessment_outlined,
          routePath: '/app/reports',
          requiredPermissions: ['REPORT_VIEW'],
          requiredFeatures: ['REPORTING'],
        ),
        SidebarMenuItem(
          id: 'inventory',
          label: 'Kho',
          icon: Icons.inventory_2_outlined,
          routePath: '/app/inventory',
          requiredPermissions: ['INVENTORY_VIEW'],
          requiredFeatures: ['INVENTORY_MANAGEMENT'],
        ),
      ],
    ),
  ];
}
