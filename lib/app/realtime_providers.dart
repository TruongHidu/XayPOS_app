import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../core/auth/access_policy.dart';
import '../core/network/api_error_mapper.dart';
import '../core/errors/failure.dart';
import '../core/realtime/realtime_config.dart';
import '../core/realtime/realtime_access_policy.dart';
import '../core/realtime/realtime_connection_service.dart';
import '../core/realtime/realtime_transport.dart';
import '../core/realtime/realtime_preference_storage.dart';
import '../core/realtime/realtime_settings_controller.dart';
import '../core/realtime/stomp_websocket_transport.dart';
import '../features/auth/domain/entities/user_role.dart';
import '../features/auth/presentation/controllers/auth_state.dart';
import '../features/inventory/presentation/controllers/inventory_alert_realtime_coordinator.dart';
import '../features/inventory/presentation/controllers/inventory_alert_notice.dart';
import '../features/inventory/presentation/controllers/inventory_alert_polling_controller.dart';
import '../features/order/presentation/controllers/order_realtime_coordinator.dart';
import '../features/order/presentation/controllers/order_invalidation.dart';
import '../features/tables/presentation/controllers/table_events.dart';
import '../features/qr_order/presentation/controllers/qr_realtime_coordinator.dart';
import '../features/qr_order/presentation/controllers/qr_events.dart';
import '../features/kitchen/presentation/controllers/kitchen_realtime_coordinator.dart';
import '../features/kitchen/presentation/controllers/kitchen_events.dart';
import 'realtime_notice.dart';
import 'providers.dart';

final realtimeConfigProvider = Provider((ref) => RealtimeConfig.environment);
final realtimePreferenceStorageProvider = Provider<RealtimePreferenceStorage>(
  (ref) => SecureRealtimePreferenceStorage(),
);
final realtimeSettingsProvider = ChangeNotifierProvider((ref) {
  final controller = RealtimeSettingsController(
    storage: ref.watch(realtimePreferenceStorageProvider),
    defaultEnabled: ref.watch(
      realtimeConfigProvider.select((config) => config.enabled),
    ),
  );
  Future.microtask(controller.load);
  return controller;
});
final realtimeForegroundProvider = StateProvider<bool>((ref) => true);
final realtimeTransportFactoryProvider = Provider<RealtimeTransportFactory>(
  (ref) =>
      () => StompWebSocketTransport(),
);

/// Downstream UI reconciliation hint. Does not read binding/bootstrap, avoiding
/// a dependency cycle with scope-owned feature controllers.
final realtimeChannelConnectedProvider = Provider.family<bool, String>((
  ref,
  id,
) {
  final allowed = ref.watch(
    authControllerProvider.select((auth) {
      final session = auth.state.session;
      return switch (id) {
        'orders' || 'qr-order-requests' => RealtimeAccessPolicy.orders(session),
        'kitchen-orders' => RealtimeAccessPolicy.kitchen(session),
        'inventory-alerts' => RealtimeAccessPolicy.inventory(session),
        _ => false,
      };
    }),
  );
  final connected = ref.watch(
    realtimeConnectionProvider.select(
      (connection) =>
          connection.state == RealtimeConnectionState.connected &&
          !connection.blockedChannels.contains(id),
    ),
  );
  final foreground = ref.watch(realtimeForegroundProvider);
  final enabled = ref.watch(
    realtimeSettingsProvider.select((s) => s.effectiveEnabled),
  );
  final websocket = ref.watch(
    realtimeConfigProvider.select(
      (c) => c.mode == RealtimeTransportMode.websocket,
    ),
  );
  return allowed && connected && foreground && enabled && websocket;
});

final realtimeConnectionProvider = ChangeNotifierProvider(
  (ref) => RealtimeConnectionService(
    factory: ref.read(realtimeTransportFactoryProvider),
    endpoint: () => ref.read(realtimeConfigProvider).endpoint,
    refresh: (token) async {
      try {
        await ref
            .read(apiClientsProvider)
            .refreshCoordinator
            .refresh(rejectedAccessToken: token);
      } catch (error) {
        final failure = ApiErrorMapper.fromException(error);
        if (failure.isNetwork || failure.type == FailureType.internal) {
          throw const RealtimeRefreshUnavailable();
        }
        rethrow;
      }
    },
    recoverAccess: (_) => ref.read(authControllerProvider).revalidateAccess(),
  ),
);

final Provider<InventoryAlertRealtimeCoordinator?>
inventoryAlertRealtimeCoordinatorProvider = Provider((ref) {
  ref.watch(inventoryScopeProvider);
  final session = ref.read(authControllerProvider).state.session;
  if (!RealtimeAccessPolicy.inventory(session)) return null;
  final coordinator = InventoryAlertRealtimeCoordinator(
    ref.read(inventoryEventsProvider),
    debounce: ref.read(realtimeConfigProvider).debounce,
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final qrEventsProvider = ChangeNotifierProvider((ref) {
  ref.watch(orderScopeProvider);
  return QrEvents();
});
final kitchenEventsProvider = ChangeNotifierProvider((ref) {
  ref.watch(orderScopeProvider);
  return KitchenEvents();
});
final orderRealtimeCoordinatorProvider = Provider<OrderRealtimeCoordinator?>((
  ref,
) {
  ref.watch(orderScopeProvider);
  if (!RealtimeAccessPolicy.orders(
    ref.read(authControllerProvider).state.session,
  )) {
    return null;
  }
  final events = ref.read(orderEventsProvider);
  final tables = ref.read(tableEventsProvider);
  final auth = ref.read(authControllerProvider);
  final scope = AccessPolicy.orderScope(auth.state.session);
  final coordinator = OrderRealtimeCoordinator(
    isCurrent: () => scope == AccessPolicy.orderScope(auth.state.session),
    debounce: ref.read(realtimeConfigProvider).debounce,
    invalidate: (hint) {
      events.invalidateRemote(hint);
      // The wire has session IDs, not a trustworthy current table snapshot.
      // Only mounted table readers react; no background detail controllers.
      tables.emit(
        const TableChange(TableChangeKind.refresh, '', remoteOrder: true),
      );
    },
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
final qrRealtimeCoordinatorProvider = Provider<QrRealtimeCoordinator?>((ref) {
  ref.watch(orderScopeProvider);
  if (!RealtimeAccessPolicy.orders(
    ref.read(authControllerProvider).state.session,
  )) {
    return null;
  }
  final auth = ref.read(authControllerProvider);
  final scope = AccessPolicy.orderScope(auth.state.session);
  final coordinator = QrRealtimeCoordinator(
    ref.read(qrEventsProvider),
    isCurrent: () => scope == AccessPolicy.orderScope(auth.state.session),
    debounce: ref.read(realtimeConfigProvider).debounce,
    onCreated: (tables, takeaway) {
      ref
          .read(staffRealtimeNoticeProvider)
          .show(
            takeaway > 0
                ? 'Có ${tables + takeaway} yêu cầu QR mới chờ duyệt ($takeaway mang đi).'
                : 'Có $tables yêu cầu QR tại bàn mới chờ duyệt.',
          );
    },
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
final kitchenRealtimeCoordinatorProvider =
    Provider<KitchenRealtimeCoordinator?>((ref) {
      ref.watch(orderScopeProvider);
      if (!RealtimeAccessPolicy.kitchen(
        ref.read(authControllerProvider).state.session,
      )) {
        return null;
      }
      final auth = ref.read(authControllerProvider);
      final scope = AccessPolicy.kitchenScope(auth.state.session);
      final coordinator = KitchenRealtimeCoordinator(
        ref.read(kitchenEventsProvider),
        isCurrent: () => scope == AccessPolicy.kitchenScope(auth.state.session),
        debounce: ref.read(realtimeConfigProvider).debounce,
        onNewItems: (count) => ref
            .read(staffRealtimeNoticeProvider)
            .show('Bếp có $count lượt món mới cần chế biến.'),
      );
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });

/// One resolved snapshot prevents listeners from reading partially rebuilt auth,
/// scope and coordinator providers while configuring the connection.
typedef RealtimeBinding = ({
  bool enabled,
  bool foreground,
  RealtimeSession? session,
  InventoryAlertRealtimeCoordinator? coordinator,
  InventoryAlertPollingController? polling,
  OrderRealtimeCoordinator? orders,
  QrRealtimeCoordinator? qr,
  KitchenRealtimeCoordinator? kitchen,
  RealtimeConfig config,
});

final realtimeBindingProvider = Provider<RealtimeBinding>((ref) {
  final auth = ref.watch(authControllerProvider).state;
  final coordinator = ref.watch(inventoryAlertRealtimeCoordinatorProvider);
  final orders = ref.watch(orderRealtimeCoordinatorProvider);
  final qr = ref.watch(qrRealtimeCoordinatorProvider);
  final kitchen = ref.watch(kitchenRealtimeCoordinatorProvider);
  final polling = ref.watch(inventoryAlertPollingProvider.notifier);
  final enabled = ref.watch(
    realtimeSettingsProvider.select((settings) => settings.effectiveEnabled),
  );
  final foreground = ref.watch(realtimeForegroundProvider);
  final config = ref.watch(realtimeConfigProvider);
  final session = auth.status == AuthStatus.authenticated ? auth.session : null;
  final tenant = session?.authenticatedUser.restaurantId;
  final ready =
      session != null &&
      tenant?.trim().isNotEmpty == true &&
      session.authenticatedUser.role != UserRole.superAdmin &&
      session.authenticatedUser.role != UserRole.unsupported;
  return (
    enabled: enabled,
    foreground: foreground,
    session: ready
        ? RealtimeSession(
            (session.authenticatedUser.id, tenant),
            AccessPolicy.inventoryScope(session)!,
            session.tokens.accessToken,
          )
        : null,
    coordinator: session != null ? coordinator : null,
    polling: session != null ? polling : null,
    orders: session != null ? orders : null,
    qr: session != null ? qr : null,
    kitchen: session != null ? kitchen : null,
    config: config,
  );
}, name: 'realtimeBinding');

/// Mounted once by App. Listeners react even while no Flutter frame is rendered.
/// Screens only observe connection/REST state; they never acquire transports.
final realtimeBootstrapProvider = Provider.autoDispose<void>((ref) {
  final connection = ref.read(realtimeConnectionProvider);
  InventoryAlertRealtimeCoordinator? observedCoordinator;
  InventoryAlertPollingController? observedPolling;
  void Function(InventoryAlertNotice)? noticeListener;
  void Function(InventoryAlertNotice)? pollingNoticeListener;
  bool previouslyEnabled = false;
  RealtimeBinding? previousBinding;
  void synchronize(RealtimeBinding binding) {
    if (!ref.mounted) return;
    final coordinator = binding.coordinator;
    if (!identical(observedCoordinator, coordinator)) {
      final previousListener = noticeListener;
      if (previousListener != null) {
        observedCoordinator?.removeNoticeListener(previousListener);
      }
      observedCoordinator = coordinator;
      noticeListener = null;
      if (coordinator != null) {
        void publish(InventoryAlertNotice notice) {
          if (!ref.mounted ||
              !ref.read(inventoryAlertNoticeAvailableProvider) ||
              !identical(observedCoordinator, coordinator)) {
            return;
          }
          ref.read(inventoryAlertNoticeControllerProvider).show(notice);
        }

        noticeListener = publish;
        coordinator.addNoticeListener(publish);
      }
    }
    final polling = binding.polling;
    if (!identical(observedPolling, polling)) {
      final previousListener = pollingNoticeListener;
      if (previousListener != null) {
        observedPolling?.removeNoticeListener(previousListener);
      }
      observedPolling = polling;
      pollingNoticeListener = null;
      if (polling != null) {
        void publish(InventoryAlertNotice notice) {
          if (!ref.mounted ||
              !ref.read(inventoryAlertNoticeAvailableProvider) ||
              !identical(observedPolling, polling)) {
            return;
          }
          ref.read(inventoryAlertNoticeControllerProvider).show(notice);
        }

        pollingNoticeListener = publish;
        polling.addNoticeListener(publish);
      }
    }
    if (previouslyEnabled && !binding.enabled) coordinator?.cancelPending();
    previouslyEnabled = binding.enabled;
    final socketActive =
        binding.enabled &&
        binding.foreground &&
        binding.session != null &&
        binding.config.mode == RealtimeTransportMode.websocket;
    binding.orders?.setActive(socketActive);
    binding.qr?.setActive(socketActive);
    binding.kitchen?.setActive(socketActive);
    final previous = previousBinding;
    previousBinding = binding;
    if (previous != null && !previous.foreground && binding.foreground) {
      // Access can be fenced silently by the server while the app is away.
      if (binding.orders != null || binding.kitchen != null) {
        unawaited(ref.read(authControllerProvider).revalidateAccess());
      }
      // QR/KDS already refresh through their route lifecycle observers.
      // Order lists/details have no polling or lifecycle owner of their own.
      if (!socketActive && binding.orders != null) {
        ref
            .read(orderEventsProvider)
            .invalidateRemote(OrderInvalidation(all: true));
      }
    }
    coordinator?.setForeground(binding.foreground);
    polling?.configure(
      enabled: binding.enabled && binding.session != null,
      foreground: binding.foreground,
    );
    connection.configure(
      enabled:
          binding.enabled &&
          binding.config.mode == RealtimeTransportMode.websocket,
      foreground: binding.foreground,
      session: binding.session,
      channels: binding.session != null
          ? [
              if (coordinator != null) coordinator.channel,
              if (binding.orders != null) binding.orders!.channel,
              if (binding.qr != null) binding.qr!.channel,
              if (binding.kitchen != null) binding.kitchen!.channel,
            ]
          : const [],
    );
  }

  ref.listen(realtimeBindingProvider, (_, binding) => synchronize(binding));
  Future.microtask(() {
    if (ref.mounted) synchronize(ref.read(realtimeBindingProvider));
  });
  ref.onDispose(() {
    final listener = noticeListener;
    if (listener != null) observedCoordinator?.removeNoticeListener(listener);
    final pollingListener = pollingNoticeListener;
    if (pollingListener != null) {
      observedPolling?.removeNoticeListener(pollingListener);
    }
    observedPolling?.configure(
      enabled: false,
      foreground: false,
      notify: false,
    );
    observedCoordinator?.setForeground(false);
    previousBinding?.orders?.setActive(false);
    previousBinding?.qr?.setActive(false);
    previousBinding?.kitchen?.setActive(false);
    connection.stop(notify: false);
  });
}, name: 'realtimeBootstrap');
