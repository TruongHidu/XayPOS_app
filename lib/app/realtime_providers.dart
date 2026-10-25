import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../core/auth/access_policy.dart';
import '../core/network/api_error_mapper.dart';
import '../core/errors/failure.dart';
import '../core/realtime/realtime_config.dart';
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
  if (!AccessPolicy.canViewInventoryAlerts(session)) return null;
  final coordinator = InventoryAlertRealtimeCoordinator(
    ref.read(inventoryEventsProvider),
    debounce: ref.read(realtimeConfigProvider).debounce,
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
  RealtimeConfig config,
});

final realtimeBindingProvider = Provider<RealtimeBinding>((ref) {
  final auth = ref.watch(authControllerProvider).state;
  final coordinator = ref.watch(inventoryAlertRealtimeCoordinatorProvider);
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
      channels: binding.session != null && coordinator != null
          ? [coordinator.channel]
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
    connection.stop(notify: false);
  });
}, name: 'realtimeBootstrap');
