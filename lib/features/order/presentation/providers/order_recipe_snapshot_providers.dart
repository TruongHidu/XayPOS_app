import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/controllers/scoped_read_controller.dart';
import '../../data/repositories/order_recipe_snapshot_repository_impl.dart';
import '../../data/data_sources/order_recipe_snapshot_remote_data_source.dart';
import '../../domain/use_cases/get_order_item_recipe_snapshot.dart';
import '../../domain/repositories/order_recipe_snapshot_repository.dart';
import '../../domain/entities/order_recipe_snapshot.dart';

typedef OrderIngredientTarget = ({String orderId, String orderItemId});
final orderRecipeSnapshotRepositoryProvider =
    Provider<OrderRecipeSnapshotRepository>(
      (ref) => OrderRecipeSnapshotRepositoryImpl(
        OrderRecipeSnapshotRemoteDataSource(
          ref.watch(apiClientsProvider).authenticated,
        ),
      ),
    );
final orderRecipeSnapshotProvider = ChangeNotifierProvider.autoDispose
    .family<ScopedReadController<OrderRecipeSnapshot>, OrderIngredientTarget>((
      ref,
      target,
    ) {
      ref.watch(orderScopeProvider);
      final auth = ref.read(authControllerProvider);
      final get = GetOrderItemRecipeSnapshot(
        ref.watch(orderRecipeSnapshotRepositoryProvider),
      );
      final controller = ScopedReadController<OrderRecipeSnapshot>(
        scope: () => AccessPolicy.orderScope(auth.state.session),
        allowed: () =>
            AccessPolicy.canViewOrderRecipeSnapshot(auth.state.session),
        read: () => get(target.orderId, target.orderItemId),
      );
      var revision = ref.read(orderEventsProvider).revision;
      ref.listen(orderEventsProvider, (_, events) {
        if (revision == events.revision) return;
        revision = events.revision;
        if (events.affectsOrder(target.orderId)) controller.markStale();
      });
      Future.microtask(controller.load);
      return controller;
    });
