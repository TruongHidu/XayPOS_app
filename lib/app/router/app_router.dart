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
import '../../features/access/presentation/access_message_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/session_bootstrap_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/reports/presentation/screens/daily_revenue_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/inventory/presentation/screens/inventory_management_screen.dart';
import '../../features/inventory/presentation/screens/stock_document_create_screen.dart';
import '../../features/inventory/presentation/screens/stock_document_detail_screen.dart';
import '../../features/inventory/presentation/screens/inventory_transaction_screen.dart';
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
          ),
        ),
        routes: [
          GoRoute(
            path: ':orderId',
            onExit: (context, state) =>
                ref.read(orderExitGuardProvider).allow(context),
            builder: (context, state) => AppShell(
              initialSection: 'orders',
              child: OrderDetailScreen(id: state.pathParameters['orderId']!),
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
        builder: (context, state) => AppShell(
          initialSection: 'menu',
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
        builder: (context, state) =>
            const AppShell(initialSection: 'reports', child: ReportsScreen()),
      ),
      GoRoute(
        path: AppRoutes.inventory,
        builder: (context, state) => AppShell(
          initialSection: 'inventory',
          child: InventoryManagementScreen(
            initialTab: state.uri.queryParameters['tab'],
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.stockCreate,
        builder: (context, state) => const AppShell(
          initialSection: 'inventory',
          child: StockDocumentCreateScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.stockDocument,
        builder: (context, state) => AppShell(
          initialSection: 'inventory',
          child: StockDocumentDetailScreen(
            id: state.pathParameters['documentId']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.inventoryTransactions,
        builder: (context, state) => AppShell(
          initialSection: 'inventory',
          child: InventoryTransactionScreen(
            target: (
              warehouseId: state.uri.queryParameters['warehouseId'],
              ingredientId: state.uri.queryParameters['ingredientId'],
              documentId: state.uri.queryParameters['documentId'],
            ),
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
          ownerMessage: 'Vui lòng liên hệ OWNER hoặc MANAGER.',
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
          title: 'Cashier Web',
          ownerMessage:
              'Tài khoản thu ngân hiện được sử dụng trên hệ thống Cashier Web.',
        ),
      ),
      GoRoute(
        path: AppRoutes.adminWebOnly,
        builder: (context, state) => const AccessMessageScreen(
          title: 'Quản trị hệ thống',
          ownerMessage: 'SUPER_ADMIN sử dụng trang quản trị web.',
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
