abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const appHome = '/app/home';
  static const menu = '/app/menu';
  static const recipe = '/app/menu/items/:menuItemId/recipes';
  static String recipeFor(String menuItemId) =>
      '/app/menu/items/${Uri.encodeComponent(menuItemId)}/recipes';
  static const kitchen = '/app/kitchen';
  static const tables = '/app/tables';
  static const orders = '/app/orders';
  static const orderCreate = '/app/order-create';
  static const orderCreateBill = '/app/order-create/bill';
  static const dailyRevenue = '/app/daily-revenue';
  static const reports = '/app/reports';
  static const inventory = '/app/inventory';
  static const stockCreate = '/app/inventory/stock-documents/new';
  static const stockDocument = '/app/inventory/stock-documents/:documentId';
  static const inventoryTransactions = '/app/inventory/transactions';
  static const inventoryAlert = '/app/inventory/alerts/:alertId';
  static const stockAuditCreate = '/app/inventory/audits/new';
  static const stockAudit = '/app/inventory/audits/:auditId';
  static String stockAuditFor(String id) =>
      '/app/inventory/audits/${Uri.encodeComponent(id)}';
  static const subscriptionRequired = '/subscription-required';
  static const subscriptionUnavailable = '/subscription-unavailable';
  static const featureUnavailable = '/feature-unavailable';
  static const noAccessibleFeature = '/no-accessible-feature';
  static const cashierWebOnly = '/cashier-web-only';
  static const adminWebOnly = '/admin-web-only';
  static const unsupportedRole = '/unsupported-role';
  static const sessionError = '/session-error';
}
