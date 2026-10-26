import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../../tables/presentation/controllers/table_events.dart';
import '../../data/data_sources/qr_request_remote_data_source.dart';
import '../../data/repositories/qr_request_repository_impl.dart';
import '../../domain/repositories/qr_request_repository.dart';
import '../../domain/use_cases/qr_request_use_cases.dart';
import '../controllers/qr_inbox_controller.dart';
import '../controllers/qr_review_controller.dart';

final qrRequestsRouteObserverProvider = Provider(
  (ref) => RouteObserver<ModalRoute<void>>(),
);
final qrRequestRepositoryProvider = Provider<QrRequestRepository>(
  (ref) => QrRequestRepositoryImpl(
    QrRequestRemoteDataSource(ref.watch(apiClientsProvider).authenticated),
  ),
);
final qrInboxProvider = ChangeNotifierProvider.autoDispose((ref) {
  ref.watch(orderScopeProvider);
  final auth = ref.read(authControllerProvider);
  final controller = QrInboxController(
    session: () => auth.state.session,
    events: ref.read(orderEventsProvider),
    onAccessDenied: ref.read(orderRecoveryProvider).handle,
    getPending: GetPendingTableQrRequests(
      ref.watch(qrRequestRepositoryProvider),
    ),
  );
  final tableEvents = ref.read(tableEventsProvider);
  var revision = tableEvents.revision;
  void changed() {
    if (revision == tableEvents.revision) return;
    revision = tableEvents.revision;
    if (tableEvents.change?.remoteOrder == true) return;
    controller.invalidate();
  }

  tableEvents.addListener(changed);
  ref.onDispose(() => tableEvents.removeListener(changed));
  ref.listen(qrEventsProvider, (_, _) => controller.invalidate());
  controller.setRealtimeConnected(
    ref.read(realtimeChannelConnectedProvider('qr-order-requests')),
  );
  ref.listen(
    realtimeChannelConnectedProvider('qr-order-requests'),
    (_, value) => controller.setRealtimeConnected(value),
  );
  return controller;
});
final qrReviewProvider = ChangeNotifierProvider.autoDispose
    .family<QrReviewController, String>((ref, id) {
      ref.watch(orderScopeProvider);
      final auth = ref.read(authControllerProvider);
      final repository = ref.watch(qrRequestRepositoryProvider);
      final controller = QrReviewController(
        id: id,
        session: () => auth.state.session,
        events: ref.read(orderEventsProvider),
        tableEvents: ref.read(tableEventsProvider),
        onAccessDenied: ref.read(orderRecoveryProvider).handle,
        getReview: GetQrRequestReview(repository),
        approveRequest: ApproveQrRequest(repository),
        rejectRequest: RejectQrRequest(repository),
        beforeApprove: (id) {
          if (ref.exists(orderDetailProvider(id))) {
            ref.read(orderDetailProvider(id)).beginSubmission();
          }
        },
        onApproved: (result) {
          if (ref.exists(orderDetailProvider(result.order.id))) {
            ref
                .read(orderDetailProvider(result.order.id))
                .applySubmission(result.order);
          }
          ref.read(qrInboxProvider).resolve(result.requestId);
        },
        onResolved: (request) {
          final orderId = request.approvedOrderId;
          if (orderId != null) {
            ref
                .read(orderEventsProvider)
                .emit(orderId, request.approvedSessionId);
          }
          ref.read(qrInboxProvider).resolve(request.id);
          ref
              .read(tableEventsProvider)
              .emit(
                TableChange(
                  TableChangeKind.refresh,
                  request.tableId ?? '',
                  sessionId: request.approvedSessionId,
                ),
              );
        },
      );
      void Function()? release;
      void retain() {
        if (controller.busy || controller.uncertain || controller.coolingDown) {
          release ??= ref.keepAlive().close;
        } else {
          release?.call();
          release = null;
        }
      }

      controller.addListener(retain);
      ref.listen(orderEventsProvider, (_, _) => controller.changed());
      ref.listen(tableEventsProvider, (_, _) => controller.changed());
      final orders = ref.read(orderEventsProvider),
          tables = ref.read(tableEventsProvider);
      var orderRevision = orders.revision, tableRevision = tables.revision;
      ref.listen(qrEventsProvider, (_, events) {
        final hint = events.hint;
        if (hint == null) return;
        final review = controller.review;
        if (hint.all ||
            hint.requestIds.contains(id) ||
            review != null &&
                (hint.tableIds.contains(review.request.tableId) ||
                    hint.sessionIds.contains(review.context?.sessionId))) {
          controller.invalidate();
        }
      });
      ref.listen(orderEventsProvider, (_, events) {
        if (orderRevision == events.revision) return;
        orderRevision = events.revision;
        final context = controller.review?.context;
        if (!controller.resolved &&
            context != null &&
            (events.affectsOrder(context.order?.id ?? '') ||
                events.affectsSession(context.sessionId))) {
          controller.invalidate();
        }
      });
      ref.listen(tableEventsProvider, (_, events) {
        if (tableRevision == events.revision) return;
        tableRevision = events.revision;
        if (events.change?.remoteOrder == true) return;
        final request = controller.review?.request;
        if (!controller.resolved &&
            request != null &&
            (events.change?.kind == TableChangeKind.refresh ||
                events.change?.id == request.tableId)) {
          controller.invalidate();
        }
      });
      ref.onDispose(() => controller.removeListener(retain));
      Future.microtask(controller.load);
      return controller;
    });
