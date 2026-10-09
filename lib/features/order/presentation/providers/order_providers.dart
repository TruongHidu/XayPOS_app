import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../menu/domain/use_cases/menu_item_use_cases.dart';
import '../../../menu/domain/use_cases/menu_group_use_cases.dart';
import '../../../tables/domain/use_cases/restaurant_table_use_cases.dart';
import '../../../tables/domain/use_cases/table_area_use_cases.dart';
import '../../../tables/domain/use_cases/table_session_use_cases.dart';
import '../../domain/entities/order_inputs.dart';
import '../../domain/repositories/order_repository.dart';
import '../../domain/use_cases/order_use_cases.dart';
import '../../domain/use_cases/order_workspace_use_cases.dart';
import '../../data/data_sources/order_remote_data_source.dart';
import '../../data/repositories/order_repository_impl.dart';
import '../../data/order_key_generator.dart';
import '../controllers/order_events.dart';
import '../controllers/order_list_controller.dart';
import '../controllers/order_detail_controller.dart';
import '../controllers/order_append_controller.dart';
import '../controllers/order_draft_controller.dart';
import '../controllers/order_menu_picker_controller.dart';
import '../controllers/order_service_context_controller.dart';
import '../widgets/order_exit_guard.dart';

final orderExitGuardProvider = Provider((ref) {
  ref.watch(orderScopeProvider);
  return OrderExitGuard();
});

final orderScopeProvider = Provider<Object?>(
  (ref) => ref.watch(
    authControllerProvider.select(
      (auth) => AccessPolicy.orderScope(auth.state.session),
    ),
  ),
);
final orderNoticeProvider = StateProvider<String?>((ref) => null);
final orderEventsProvider = ChangeNotifierProvider((ref) {
  ref.watch(orderScopeProvider);
  return OrderEvents();
});
final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepositoryImpl(
    OrderRemoteDataSource(ref.watch(apiClientsProvider).authenticated),
  ),
);
final orderKeyGeneratorProvider = Provider<OrderKeyGenerator>(
  (ref) => SecureOrderKeyGenerator(),
);

class OrderAccessRecovery {
  OrderAccessRecovery(this.auth, this.notice);
  final AuthController auth;
  final void Function(String) notice;
  final Set<Object?> _handled = {};
  Future<void>? _pending;
  Future<void> handle(Failure failure) async {
    notice(failure.message);
    if (!_handled.add(AccessPolicy.orderScope(auth.state.session))) return;
    if (_pending != null) {
      await _pending;
      return;
    }
    final future = auth.restore();
    _pending = future;
    try {
      await future;
    } finally {
      _pending = null;
    }
  }
}

final orderRecoveryProvider = Provider(
  (ref) => OrderAccessRecovery(
    ref.read(authControllerProvider),
    (message) => ref.read(orderNoticeProvider.notifier).state = message,
  ),
);
final orderListProvider = ChangeNotifierProvider.autoDispose
    .family<OrderListController, String?>((ref, sessionId) {
      ref.watch(orderScopeProvider);
      final auth = ref.read(authControllerProvider);
      final controller = OrderListController(
        session: () => auth.state.session,
        events: ref.read(orderEventsProvider),
        onAccessDenied: ref.read(orderRecoveryProvider).handle,
        get: GetOrders(ref.watch(orderRepositoryProvider)),
        query: OrderQuery(tableSessionId: sessionId),
      );
      Future.microtask(controller.load);
      return controller;
    });
final orderDetailProvider = ChangeNotifierProvider.autoDispose
    .family<OrderDetailController, String>((ref, id) {
      ref.watch(orderScopeProvider);
      final auth = ref.read(authControllerProvider);
      final repo = ref.watch(orderRepositoryProvider);
      final controller = OrderDetailController(
        session: () => auth.state.session,
        events: ref.read(orderEventsProvider),
        onAccessDenied: ref.read(orderRecoveryProvider).handle,
        id: id,
        get: GetOrderDetail(repo),
        updateOrder: UpdateOrder(repo),
        add: AddOrderItems(repo),
        updateLine: UpdateOrderItem(repo),
        confirmOrder: ConfirmOrder(repo),
        cancelLine: CancelOrderItem(repo),
        cancelOrder: CancelOrder(repo),
      );
      Future.microtask(controller.load);
      return controller;
    });
final orderDraftProvider = ChangeNotifierProvider.autoDispose
    .family<OrderDraftController, OrderCreationContext>((ref, context) {
      ref.watch(orderScopeProvider);
      final auth = ref.read(authControllerProvider);
      final controller = OrderDraftController(
        session: () => auth.state.session,
        events: ref.read(orderEventsProvider),
        onAccessDenied: ref.read(orderRecoveryProvider).handle,
        context: context,
        createOrder: CreateOrder(ref.watch(orderRepositoryProvider)),
        keys: ref.watch(orderKeyGeneratorProvider),
      );
      void Function()? release;
      void retainIntent() {
        if (controller.busy || controller.uncertain) {
          release ??= ref.keepAlive().close;
        } else {
          release?.call();
          release = null;
        }
      }

      controller.addListener(retainIntent);
      ref.onDispose(() => controller.removeListener(retainIntent));
      return controller;
    });
final orderAppendProvider = ChangeNotifierProvider.autoDispose
    .family<OrderAppendController, String>((ref, id) {
      ref.watch(orderScopeProvider);
      final auth = ref.read(authControllerProvider);
      final controller = OrderAppendController(
        session: () => auth.state.session,
        events: ref.read(orderEventsProvider),
        onAccessDenied: ref.read(orderRecoveryProvider).handle,
        id: id,
        root: () => ref.read(orderDetailProvider(id)).order,
        blocked: () => ref.read(orderDetailProvider(id)).requiresVerification,
        beforeSend: () => ref.read(orderDetailProvider(id)).beginSubmission(),
        onApplied: (value) =>
            ref.read(orderDetailProvider(id)).applySubmission(value),
        appliedSource: () => ref.read(orderDetailProvider(id)),
        submitItems: SubmitOrderItems(ref.watch(orderRepositoryProvider)),
        keys: ref.watch(orderKeyGeneratorProvider),
      );
      // Keep the selected read-side alive without rebuilding the append controller.
      ref.listen(orderDetailProvider(id), (_, _) => controller.changed());
      void Function()? release;
      void retainIntent() {
        if (controller.busy || controller.uncertain) {
          release ??= ref.keepAlive().close;
        } else {
          release?.call();
          release = null;
        }
      }

      controller.addListener(retainIntent);
      final exit = ref.read(orderExitGuardProvider);
      exit.registerAppend(controller);
      ref.onDispose(() {
        controller.removeListener(retainIntent);
        exit.unregisterAppend(controller);
      });
      return controller;
    });
final orderMenuPickerProvider = ChangeNotifierProvider.autoDispose
    .family<OrderMenuPickerController, String>((ref, permission) {
      ref.watch(orderScopeProvider);
      final auth = ref.read(authControllerProvider);
      final controller = OrderMenuPickerController(
        session: () => auth.state.session,
        events: ref.read(orderEventsProvider),
        onAccessDenied: ref.read(orderRecoveryProvider).handle,
        permission: permission,
        itemsUseCase: GetMenuItems(ref.watch(menuItemRepositoryProvider)),
        groupsUseCase: GetMenuGroups(ref.watch(menuGroupRepositoryProvider)),
        catalog: ref.read(menuCatalogEventsProvider),
      );
      Future.microtask(
        () => Future.wait([controller.load(), controller.loadGroups()]),
      );
      return controller;
    });
final orderServiceContextProvider = ChangeNotifierProvider.autoDispose((ref) {
  ref.watch(orderScopeProvider);
  final auth = ref.read(authControllerProvider);
  final tables = ref.watch(restaurantTableRepositoryProvider);
  final sessions = ref.watch(tableSessionRepositoryProvider);
  final controller = OrderServiceContextController(
    session: () => auth.state.session,
    events: ref.read(orderEventsProvider),
    onAccessDenied: ref.read(orderRecoveryProvider).handle,
    getTables: GetAvailableOrderTables(ListRestaurantTable(tables)),
    getAreas: GetActiveOrderAreas(
      ListTableArea(ref.watch(tableAreaRepositoryProvider)),
    ),
    getServing: GetServingOrderSummaries(
      GetOrders(ref.watch(orderRepositoryProvider)),
    ),
    detailTable: DetailRestaurantTable(tables),
    getSession: DetailTableSession(sessions),
    getActive: GetActiveOrderForSession(ref.watch(orderRepositoryProvider)),
    tableEvents: ref.read(tableEventsProvider),
  );
  Future.microtask(controller.refresh);
  return controller;
});
