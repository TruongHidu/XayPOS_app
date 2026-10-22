import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/controllers/scoped_read_controller.dart';
import '../../data/repositories/order_item_allocation_repository_impl.dart';
import '../../data/data_sources/order_item_allocation_remote_data_source.dart';
import '../../domain/use_cases/get_order_item_allocation.dart';
import '../../domain/entities/order_item_allocation.dart';
import '../../domain/repositories/order_item_allocation_repository.dart';

final orderItemAllocationRepositoryProvider =
    Provider<OrderItemAllocationRepository>(
      (ref) => OrderItemAllocationRepositoryImpl(
        OrderItemAllocationRemoteDataSource(
          ref.watch(apiClientsProvider).authenticated,
        ),
      ),
    );
final orderItemAllocationProvider = ChangeNotifierProvider.autoDispose
    .family<
      ScopedReadController<OrderItemAllocation>,
      ({String orderId, String orderItemId})
    >((ref, target) {
      ref.watch(orderScopeProvider);
      final auth = ref.read(authControllerProvider);
      final get = GetOrderItemAllocation(
        ref.watch(orderItemAllocationRepositoryProvider),
      );
      final controller = ScopedReadController<OrderItemAllocation>(
        scope: () => AccessPolicy.orderScope(auth.state.session),
        allowed: () =>
            AccessPolicy.canViewOrderItemAllocation(auth.state.session),
        read: () => get(target.orderId, target.orderItemId),
      );
      var revision = ref.read(orderEventsProvider).revision;
      ref.listen(orderEventsProvider, (_, events) {
        if (revision == events.revision) return;
        revision = events.revision;
        if (events.changedId == target.orderId) controller.markStale();
      });
      Future.microtask(controller.load);
      return controller;
    });
