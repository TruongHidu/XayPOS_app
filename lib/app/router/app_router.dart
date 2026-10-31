import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/shell/app_shell.dart';
import '../../features/kitchen/presentation/providers/kitchen_providers.dart';
import '../../features/kitchen/presentation/screens/kitchen_display_screen.dart';
import '../../features/menu/presentation/screens/recipe_management_screen.dart';
import '../../features/order/presentation/screens/order_append_screen.dart';
import '../../features/order/presentation/screens/order_create_screen.dart';
import '../../features/order/presentation/screens/order_detail_screen.dart';
import '../../features/order/presentation/screens/order_list_screen.dart';
import '../../features/order/presentation/screens/order_service_context_screen.dart';
import '../../features/order/presentation/screens/takeaway_orders_screen.dart';
import '../../features/order/domain/entities/order_entities.dart';
import '../../features/access/presentation/access_message_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/session_bootstrap_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/reports/presentation/screens/daily_revenue_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/reports/presentation/widgets/report_filter_panel.dart';
import '../../features/reference_margin_reports/presentation/screens/reference_margin_reports_screen.dart';
import '../../features/cashbook/presentation/screens/cashbook_screen.dart';
import '../../features/cashbook/presentation/widgets/cashbook_filter_panel.dart';
import '../../features/inventory/presentation/screens/inventory_balances_screen.dart';
import '../../features/inventory/presentation/screens/inventory_warehouses_screen.dart';
import '../../features/inventory/presentation/screens/inventory_documents_screen.dart';
import '../../features/inventory/presentation/screens/inventory_transactions_screen.dart';
import '../../features/inventory/presentation/screens/inventory_low_stock_screen.dart';
import '../../features/inventory/presentation/screens/inventory_alerts_screen.dart';
import '../../features/inventory/presentation/screens/inventory_audits_screen.dart';
import '../../features/inventory/presentation/screens/stock_document_create_screen.dart';
import '../../features/inventory/presentation/screens/stock_document_detail_screen.dart';
import '../../features/inventory/presentation/screens/inventory_transaction_screen.dart';
import '../../features/inventory/presentation/screens/inventory_alert_detail_screen.dart';
import '../../features/inventory/presentation/screens/stock_audit_create_screen.dart';
import '../../features/inventory/presentation/screens/stock_audit_detail_screen.dart';
import '../../features/inventory/presentation/widgets/stock_audit_exit_guard.dart';
import '../providers.dart';
import 'app_routes.dart';
import 'route_guard.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authController = ref.read(authControllerProvider);
  final guard = RouteGuard(authController);
  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: authController,
    observers: [
      ref.read(kitchenRouteObserverProvider),
      ref.read(qrRequestsRouteObserverProvider),
      ref.read(referenceMarginRouteObserverProvider),
    ],
    redirect: (context, state) => guard.redirect(state),
    routes: [
      GoRoute(
        path: AppRoutes.kitchen,
        builder: (context, state) => const AppShell(
          initialSection: 'kitchen-display',
          child: KitchenDisplayScreen(),
        ),
      ),
      GoRoute(
        path: '/app/dish-status',
        redirect: (context, state) => AppRoutes.kitchen,
      ),
      GoRoute(
        path: AppRoutes.orders,
        builder: (context, state) => AppShell(
          initialSection: 'orders',
          child: OrderListScreen(
            sessionId: state.uri.queryParameters['tableSessionId'],
            initialServiceType: ServiceType.values
                .where(
                  (t) => t.code == state.uri.queryParameters['serviceType'],
                )
                .firstOrNull,
          ),
        ),
        routes: [
          GoRoute(
            path: ':orderId',
            onExit: (context, state) =>
                ref.read(orderExitGuardProvider).allow(context),
            builder: (context, state) => AppShell.inner(
              title: 'Chi tiết đơn hàng',
              backFallback: AppRoutes.orders,
              child: OrderDetailScreen(
                id: state.pathParameters['orderId']!,
                showBackButton: false,
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.takeaway,
        builder: (context, state) => const AppShell(
          initialSection: 'takeaway-orders',
          child: TakeawayOrdersScreen(),
        ),
        routes: [
          GoRoute(
            path: ':orderId',
            onExit: (context, state) =>
                ref.read(orderExitGuardProvider).allow(context),
            builder: (context, state) => AppShell.inner(
              title: 'Chi tiết đơn hàng',
              backFallback: AppRoutes.takeaway,
              child: OrderDetailScreen(
                id: state.pathParameters['orderId']!,
                showBackButton: false,
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.orderCreate,
        onExit: (context, state) =>
            ref.read(orderExitGuardProvider).allow(context),
        builder: (context, state) {
          final params = state.uri.queryParameters;
          final isComposing =
              params.containsKey('serviceType') ||
              params.containsKey('tableId') ||
              params.containsKey('tableSessionId');
          return AppShell(
            initialSection: 'order-create',
            showAppBar: !isComposing,
            child: isComposing
                ? OrderCreateScreen(
                    tableId: params['tableId'],
                    sessionId: params['tableSessionId'],
                    takeaway: params['serviceType'] == 'TAKEAWAY',
                  )
                : const OrderServiceContextScreen(),
          );
        },
        routes: [
          GoRoute(
            path: 'bill/:orderId',
            onExit: (context, state) =>
                ref.read(orderExitGuardProvider).allow(context),
            builder: (context, state) {
              final orderId = state.pathParameters['orderId']!;
              final tableName = state.uri.queryParameters['tableName'];
              return AppShell(
                initialSection: 'order-create',
                showAppBar: false,
                child: OrderDetailScreen(
                  id: orderId,
                  tableName: tableName,
                  isOrderCreateFlow: true,
                ),
              );
            },
            routes: [
              GoRoute(
                path: 'add-items',
                onExit: (context, state) =>
                    ref.read(orderExitGuardProvider).allow(context),
                builder: (context, state) {
                  final orderId = state.pathParameters['orderId']!;
                  final tableName = state.uri.queryParameters['tableName'];
                  return AppShell(
                    initialSection: 'order-create',
                    showAppBar: false,
                    child: OrderAppendScreen(
                      orderId: orderId,
                      tableName: tableName,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.tables,
        builder: (context, state) => const AppShell(initialSection: 'tables'),
      ),
      GoRoute(
        path: AppRoutes.menu,
        builder: (context, state) => const AppShell(initialSection: 'menu'),
      ),
      GoRoute(
        path: AppRoutes.recipe,
        builder: (context, state) => AppShell.inner(
          title: 'Công thức',
          backFallback: AppRoutes.menu,
          child: RecipeManagementScreen(
            menuItemId: state.pathParameters['menuItemId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/app/staff',
        builder: (context, state) => const AppShell(initialSection: 'staff'),
      ),
      GoRoute(
        path: AppRoutes.dailyRevenue,
        builder: (context, state) => const AppShell(
          initialSection: 'daily-revenue',
          child: DailyRevenueScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.reports,
        builder: (context, state) => const AppShell(
          initialSection: 'reports',
          actions: [ReportFilterAction()],
          child: ReportsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.referenceMargin,
        builder: (context, state) => const AppShell(
          initialSection: 'reference-margin-reports',
          child: ReferenceMarginReportsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.cashbook,
        builder: (context, state) => const AppShell(
          initialSection: 'cashbook',
          actions: [CashbookFilterAction()],
          child: CashbookScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.inventory,
        redirect: (context, state) {
          final target = switch (state.uri.queryParameters['tab']) {
            'warehouses' => AppRoutes.inventoryWarehouses,
            'documents' => AppRoutes.inventoryDocuments,
            'transactions' => AppRoutes.inventoryTransactions,
            'lowStock' || 'low-stock' => AppRoutes.inventoryLowStock,
            'alerts' => AppRoutes.inventoryAlerts,
            'audits' => AppRoutes.inventoryAudits,
            _ => AppRoutes.inventoryBalances,
          };
          final query = Map<String, String>.of(state.uri.queryParameters)
            ..remove('tab');
          return Uri(
            path: target,
            queryParameters: query.isEmpty ? null : query,
            fragment: state.uri.hasFragment ? state.uri.fragment : null,
          ).toString();
        },
      ),
      GoRoute(
        path: AppRoutes.inventoryBalances,
        builder: (context, state) => const AppShell(
          initialSection: 'inventory',
          child: InventoryBalancesScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.inventoryWarehouses,
        builder: (context, state) => const AppShell(
          initialSection: 'inventory-warehouses',
          child: InventoryWarehousesScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.inventoryDocuments,
        builder: (context, state) => const AppShell(
          initialSection: 'inventory-documents',
          child: InventoryDocumentsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.inventoryLowStock,
        builder: (context, state) => const AppShell(
          initialSection: 'inventory-low-stock',
          child: InventoryLowStockScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.inventoryAlerts,
        builder: (context, state) => const AppShell(
          initialSection: 'inventory-alerts',
          child: InventoryAlertsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.inventoryAudits,
        builder: (context, state) => const AppShell(
          initialSection: 'inventory-audits',
          child: InventoryAuditsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.inventoryAlert,
        builder: (context, state) => AppShell.inner(
          title: 'Chi tiết cảnh báo',
          backFallback: AppRoutes.inventoryAlerts,
          child: InventoryAlertDetailScreen(
            id: state.pathParameters['alertId']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.stockAuditCreate,
        onExit: (context, state) => confirmStockAuditExit(context, ref, null),
        builder: (context, state) => const AppShell.inner(
          title: 'Tạo kiểm kê',
          backFallback: AppRoutes.inventoryAudits,
          child: StockAuditCreateScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.stockAudit,
        onExit: (context, state) => confirmStockAuditExit(
          context,
          ref,
          state.pathParameters['auditId']!,
        ),
        builder: (context, state) => AppShell.inner(
          title: 'Chi tiết kiểm kê',
          backFallback: AppRoutes.inventoryAudits,
          child: StockAuditDetailScreen(id: state.pathParameters['auditId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.stockCreate,
        builder: (context, state) => const AppShell.inner(
          title: 'Tạo chứng từ',
          backFallback: AppRoutes.inventoryDocuments,
          child: StockDocumentCreateScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.stockDocument,
        builder: (context, state) => AppShell.inner(
          title: 'Chi tiết chứng từ',
          backFallback: AppRoutes.inventoryDocuments,
          child: StockDocumentDetailScreen(
            id: state.pathParameters['documentId']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.inventoryTransactions,
        builder: (context, state) => state.uri.queryParameters.isEmpty
            ? const AppShell(
                initialSection: 'inventory-transactions',
                child: InventoryTransactionsScreen(),
              )
            : AppShell.inner(
                title: 'Lịch sử biến động kho',
                backFallback: AppRoutes.inventoryTransactions,
                child: InventoryTransactionRoute(
                  query: state.uri.queryParameters,
                ),
              ),
      ),
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.sessionError,
        builder: (context, state) => const SessionBootstrapScreen(),
      ),

      // ── Unified application shell ─────────────────────────
      GoRoute(
        path: AppRoutes.appHome,
        builder: (context, state) => const AppShell(),
      ),

      // ── Access message screens ─────────────────────────────
      GoRoute(
        path: AppRoutes.subscriptionRequired,
        builder: (context, state) => const AccessMessageScreen(
          title: 'Nhà hàng chưa có gói hoạt động',
          ownerMessage: 'Vui lòng chọn hoặc mua gói để tiếp tục.',
          staffMessage:
              'Nhà hàng chưa có gói hoạt động. Vui lòng liên hệ chủ nhà hàng.',
        ),
      ),
      GoRoute(
        path: AppRoutes.subscriptionUnavailable,
        builder: (context, state) => const AccessMessageScreen(
          title: 'Gói dịch vụ chưa hoạt động',
          ownerMessage: 'Vui lòng liên hệ chủ nhà hàng hoặc quản lý.',
        ),
      ),
      GoRoute(
        path: AppRoutes.featureUnavailable,
        builder: (context, state) => const AccessMessageScreen(
          title: 'Tính năng chưa khả dụng',
          ownerMessage: 'Gói hiện tại không hỗ trợ chức năng này.',
        ),
      ),
      GoRoute(
        path: AppRoutes.noAccessibleFeature,
        builder: (context, state) => const AccessMessageScreen(
          title: 'Không có chức năng khả dụng',
          ownerMessage: 'Tài khoản chưa được cấp quyền truy cập chức năng.',
        ),
      ),
      GoRoute(
        path: AppRoutes.cashierWebOnly,
        builder: (context, state) => const AccessMessageScreen(
          title: 'Dùng trên bản web',
          ownerMessage:
              'Tài khoản thu ngân hiện dùng trên hệ thống web dành cho thu ngân.',
        ),
      ),
      GoRoute(
        path: AppRoutes.adminWebOnly,
        builder: (context, state) => const AccessMessageScreen(
          title: 'Quản trị hệ thống',
          ownerMessage:
              'Tài khoản quản trị hệ thống dùng trên trang quản trị web.',
        ),
      ),
      GoRoute(
        path: AppRoutes.unsupportedRole,
        builder: (context, state) => const AccessMessageScreen(
          title: 'Vai trò chưa được hỗ trợ',
          ownerMessage: 'Ứng dụng chưa hỗ trợ vai trò của tài khoản này.',
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
