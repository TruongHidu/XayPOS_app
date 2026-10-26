import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../data/data_sources/kitchen_remote_data_source.dart';
import '../../data/repositories/kitchen_repository_impl.dart';
import '../../domain/repositories/kitchen_repository.dart';
import '../../domain/use_cases/kitchen_use_cases.dart';
import '../controllers/kitchen_display_controller.dart';
import '../controllers/kitchen_order_action_controller.dart';

final kitchenScopeProvider = Provider<Object?>(
  (ref) => ref.watch(
    authControllerProvider.select(
      (auth) => AccessPolicy.kitchenScope(auth.state.session),
    ),
  ),
);
final kitchenRouteObserverProvider = Provider(
  (ref) => RouteObserver<ModalRoute<void>>(),
);
final kitchenRepositoryProvider = Provider<KitchenRepository>(
  (ref) => KitchenRepositoryImpl(
    KitchenRemoteDataSource(ref.watch(apiClientsProvider).authenticated),
  ),
);

final kitchenDisplayProvider =
    ChangeNotifierProvider.autoDispose<KitchenDisplayController>((ref) {
      ref.watch(kitchenScopeProvider);
      final auth = ref.read(authControllerProvider);
      final orders = ref.read(orderEventsProvider);
      final controller = KitchenDisplayController(
        session: () => auth.state.session,
        onAccessDenied: ref.read(orderRecoveryProvider).handle,
        getQueue: GetKitchenQueue(ref.watch(kitchenRepositoryProvider)),
        readBlocked: () => orders.hasPending,
      );
      var orderRevision = ref.read(orderEventsProvider).revision;
      var tableRevision = ref.read(tableEventsProvider).revision;
      ref.listen(orderEventsProvider, (_, events) {
        controller.resumeQueuedRefresh();
        if (orderRevision == events.revision) return;
        orderRevision = events.revision;
        if (events.remote != null) {
          return; // Kitchen has its own fan-out consumer.
        }
        if (events.source is KitchenOrderActionController) return;
        controller.eventRefresh();
      });
      ref.listen(kitchenEventsProvider, (_, _) => controller.eventRefresh());
      controller.setRealtimeConnected(
        ref.read(realtimeChannelConnectedProvider('kitchen-orders')),
      );
      ref.listen(
        realtimeChannelConnectedProvider('kitchen-orders'),
        (_, value) => controller.setRealtimeConnected(value),
      );
      ref.listen(tableEventsProvider, (_, events) {
        if (tableRevision == events.revision) return;
        tableRevision = events.revision;
        if (events.change?.remoteOrder == true) return;
        controller.eventRefresh();
      });
      return controller;
    });

final kitchenActionsProvider =
    ChangeNotifierProvider.autoDispose<KitchenOrderActionController>((ref) {
      ref.watch(kitchenScopeProvider);
      // Watch the identity, not each display notification, so a mutation keeps its intent.
      final display = ref.watch(kitchenDisplayProvider.notifier);
      final orders = ref.read(orderEventsProvider);
      final tables = ref.read(tableEventsProvider);
      final auth = ref.read(authControllerProvider);
      final controller = KitchenOrderActionController(
        session: () => auth.state.session,
        onAccessDenied: ref.read(orderRecoveryProvider).handle,
        transition: TransitionKitchenItem(ref.watch(kitchenRepositoryProvider)),
        display: display,
        events: orders,
        externalBlocked: (sessionId, owner) =>
            tables.sessionTransferBlocked(sessionId) ||
            sessionId != null &&
                tables.externalSessionBlocked(sessionId, except: owner),
        onSessionBlocked: tables.markExternalSessionBlocked,
      );
      ref.listen(orderEventsProvider, (_, _) => controller.signalsChanged());
      ref.listen(tableEventsProvider, (_, _) => controller.signalsChanged());
      void Function()? release;
      void retain() {
        if (controller.retained) {
          release ??= ref.keepAlive().close;
        } else {
          release?.call();
          release = null;
        }
      }

      controller.addListener(retain);
      ref.onDispose(() => controller.removeListener(retain));
      return controller;
    });
