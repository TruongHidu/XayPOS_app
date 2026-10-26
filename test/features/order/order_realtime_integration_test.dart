import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/realtime_notice.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/realtime/realtime_config.dart';
import 'package:pos_saas_app/core/realtime/realtime_transport.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/kitchen/data/dto/kitchen_dto.dart';
import 'package:pos_saas_app/features/kitchen/presentation/providers/kitchen_providers.dart';
import 'package:pos_saas_app/features/kitchen/presentation/controllers/kitchen_display_controller.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_inputs.dart';
import 'package:pos_saas_app/features/order/domain/use_cases/order_use_cases.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_events.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_invalidation.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_list_controller.dart';
import 'package:pos_saas_app/features/qr_order/data/dto/qr_request_dto.dart';
import 'package:pos_saas_app/features/qr_order/domain/entities/qr_request.dart';
import 'package:pos_saas_app/features/qr_order/presentation/controllers/qr_events.dart';
import '../../helpers/auth_fakes.dart';
import '../../helpers/order_realtime_fakes.dart';
import '../../helpers/realtime_fakes.dart';
import '../kitchen/kitchen_fakes.dart';
import '../menu/menu_fakes.dart';
import '../qr_order/qr_fakes.dart';
import 'order_fakes.dart';

const _credentials = LoginCredentials(
  email: 'test@example.com',
  password: 'password',
);
const _permissions = {
  'ORDER_VIEW',
  'ORDER_CREATE',
  'ORDER_UPDATE',
  'KITCHEN_VIEW',
  'INVENTORY_VIEW',
};
const _features = {
  'ORDER_MANAGEMENT',
  'POS_QUICK_ORDER',
  'KITCHEN_DISPLAY',
  'INVENTORY_MANAGEMENT',
  'LOW_STOCK_ALERT',
  'QR_MENU_VIEW',
  'QR_TABLE_ORDER',
  'TABLE_MANAGEMENT',
};

class _Rig {
  _Rig({
    UserRole role = UserRole.owner,
    Set<String> permissions = _permissions,
    Set<String> features = _features,
    bool enabled = true,
    RealtimeTransportMode mode = RealtimeTransportMode.websocket,
  }) {
    authRepo = FakeAuthRepository()
      ..loginResult = Success(
        makeAuthSession(role: role, permissions: permissions),
      )
      ..restoreResult = Success(
        makeAuthSession(role: role, permissions: permissions),
      );
    entitlement = FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: features));
    auth = makeController(
      authRepository: authRepo,
      entitlementRepository: entitlement,
      sessionEvents: sessionEvents,
    );
    orders.current = OrderDto.detail(
      orderJson(status: 'CONFIRMED', confirmed: true)..['id'] = realtimeOrderId,
    );
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((_) => auth),
        realtimeConfigProvider.overrideWithValue(
          RealtimeConfig(enabled: enabled, mode: mode),
        ),
        realtimePreferenceStorageProvider.overrideWithValue(
          MemoryRealtimePreferenceStorage(),
        ),
        realtimeTransportFactoryProvider.overrideWithValue(factory.call),
        orderRepositoryProvider.overrideWithValue(orders),
        qrRequestRepositoryProvider.overrideWithValue(qr),
        kitchenRepositoryProvider.overrideWithValue(kitchen),
      ],
    );
    mount = container.listen(realtimeBootstrapProvider, (_, _) {});
    auth.login(_credentials);
  }
  final factory = FakeRealtimeFactory(), sessionEvents = SessionEvents();
  final orders = FakeOrders(), qr = FakeQrRequests(), kitchen = FakeKitchen();
  late final FakeAuthRepository authRepo;
  late final FakeEntitlementRepository entitlement;
  late final AuthController auth;
  late final ProviderContainer container;
  late final ProviderSubscription<void> mount;
  void dispose() {
    mount.close();
    container.dispose();
    sessionEvents.dispose();
  }
}

void main() {
  test(
    'QR invalidation during approve preserves command generation and unknown-outcome locks',
    () {
      fakeAsync((clock) {
        final r = _Rig();
        clock.elapse(Duration.zero);
        r.qr.reviewData = QrRequestDto.review(qrReviewJson());
        final keep = r.container.listen(qrReviewProvider('qr-1'), (_, _) {});
        clock.elapse(Duration.zero);
        final review = r.container.read(qrReviewProvider('qr-1'));
        expect(review.canApprove, true);
        final result = Completer<Result<QrApproval>>();
        r.qr.onApprove = () => result.future;
        review.approve(review.review!, confirmed: true);
        clock.flushMicrotasks();
        r.container
            .read(qrEventsProvider)
            .emit(QrInvalidation(requestIds: ['qr-1']));
        clock.elapse(Duration.zero);
        expect(review.busy, true);
        expect(r.container.read(orderEventsProvider).pending('o1'), true);
        expect(r.qr.approvals, hasLength(1));
        expect(r.qr.reviews, hasLength(1));
        result.complete(const Error(networkFailure));
        clock.flushMicrotasks();
        expect(review.uncertain, true);
        expect(r.container.read(orderEventsProvider).unresolved('o1'), true);
        expect(r.qr.reviews, hasLength(1));
        expect(r.qr.approvals, hasLength(1));
        keep.close();
        r.dispose();
        clock.elapse(Duration.zero);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  test(
    'remote completion preserves append selection and blocks sending to terminal order',
    () {
      fakeAsync((clock) {
        final r = _Rig(
          permissions: {..._permissions, 'MENU_VIEW'},
          features: {..._features, 'MENU_MANAGEMENT'},
        );
        clock.elapse(Duration.zero);
        r.factory.last.connected();
        clock.elapse(const Duration(milliseconds: 400));
        final keep = r.container.listen(
          orderAppendProvider(realtimeOrderId),
          (_, _) {},
        );
        clock.elapse(Duration.zero);
        final cart = r.container.read(orderAppendProvider(realtimeOrderId));
        cart.begin(r.orders.current);
        cart.add(MenuItemDto.fromJson(itemJson()..['id'] = itemId).toEntity());
        expect(cart.lines, hasLength(1));
        r.orders.current = OrderDto.detail(
          orderJson(status: 'CANCELLED', version: 8)..['id'] = realtimeOrderId,
        );
        r.factory.last.handlers['orders']!(orderEvent(n: 10, version: 8));
        clock.elapse(const Duration(milliseconds: 400));
        expect(cart.lines, hasLength(1));
        expect(cart.canPick, false);
        expect(cart.failure?.code, 'ORDER_NO_LONGER_SERVING');
        cart.send();
        clock.flushMicrotasks();
        expect(r.orders.submissions, isEmpty);
        expect(r.orders.creates, isEmpty);
        keep.close();
        r.dispose();
        clock.elapse(Duration.zero);
      });
    },
  );
  test(
    'background fences late frames, resume resyncs silently and preserves one physical connection',
    () {
      fakeAsync((clock) {
        final r = _Rig();
        clock.elapse(Duration.zero);
        r.factory.last.connected();
        clock.elapse(const Duration(milliseconds: 400));
        final old = r.factory.last,
            lateFrame = r.factory.last.handlers['orders']!;
        final events = r.container.read(orderEventsProvider),
            revision = r.container.read(orderEventsProvider).revision;
        r.container.read(realtimeForegroundProvider.notifier).state = false;
        clock.elapse(Duration.zero);
        expect(old.closed, true);
        lateFrame(orderEvent(fresh: true));
        clock.elapse(const Duration(minutes: 1));
        expect(events.revision, revision);
        expect(r.factory.transports, hasLength(1));
        r.container.read(realtimeForegroundProvider.notifier).state = true;
        clock.elapse(Duration.zero);
        expect(r.factory.transports, hasLength(2));
        r.factory.last.connected();
        clock.elapse(const Duration(milliseconds: 400));
        expect(r.container.read(staffRealtimeNoticeProvider).message, null);
        expect(events.revision, revision + 1);
        r.dispose();
        clock.elapse(Duration.zero);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  test(
    'unattributed forbidden error blocks all channels once and retains auth',
    () {
      fakeAsync((clock) {
        final r = _Rig();
        clock.elapse(Duration.zero);
        r.factory.last.connected();
        r.factory.last.fail(
          const RealtimeProblem(RealtimeFailureKind.stomp, code: 'FORBIDDEN'),
        );
        clock.elapse(const Duration(minutes: 10));
        expect(r.factory.transports, hasLength(1));
        expect(r.authRepo.restoreCalls, 1);
        expect(r.auth.state.session, isNotNull);
        expect(
          r.container.read(realtimeConnectionProvider).blockedChannels,
          hasLength(4),
        );
        r.dispose();
        clock.elapse(Duration.zero);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  for (final entry in [
    (
      role: UserRole.cashier,
      permissions: {'ORDER_VIEW'},
      features: {'ORDER_MANAGEMENT'},
      ids: {'orders', 'qr-order-requests'},
    ),
    (
      role: UserRole.kitchen,
      permissions: {'KITCHEN_VIEW'},
      features: {'KITCHEN_DISPLAY'},
      ids: {'kitchen-orders'},
    ),
    (
      role: UserRole.owner,
      permissions: _permissions,
      features: _features,
      ids: {
        'orders',
        'qr-order-requests',
        'kitchen-orders',
        'inventory-alerts',
      },
    ),
  ]) {
    test(
      'bootstrap single socket for ${entry.role}, mounts no screen readers',
      () {
        fakeAsync((clock) {
          final r = _Rig(
            role: entry.role,
            permissions: entry.permissions,
            features: entry.features,
          );
          clock.elapse(Duration.zero);
          expect(r.factory.transports, hasLength(1));
          r.factory.last.connected();
          expect(r.factory.last.handlers.keys.toSet(), entry.ids);
          clock.elapse(const Duration(milliseconds: 400));
          expect(r.orders.queries, isEmpty);
          expect(r.orders.detailCalls, 0);
          expect(r.qr.pages, isEmpty);
          expect(r.kitchen.queries, isEmpty);
          r.dispose();
          clock.elapse(Duration.zero);
          expect(clock.pendingTimers, isEmpty);
        });
      },
    );
  }
  test(
    'QR CREATED refreshes visible inbox from REST; processed request leaves pending; no commands',
    () {
      fakeAsync((clock) {
        final r = _Rig();
        clock.elapse(Duration.zero);
        r.factory.last.connected();
        clock.elapse(const Duration(milliseconds: 400));
        final keep = r.container.listen(qrInboxProvider, (_, _) {});
        final inbox = r.container.read(qrInboxProvider);
        inbox.setVisible('screen', true);
        clock.elapse(Duration.zero);
        r.qr.rows = [
          QrRequestDto.request(
            qrJson(
              id: realtimeRequestId,
              table: realtimeTableId,
              session: null,
            ),
          ),
        ];
        r.factory.last.handlers['qr-order-requests']!(
          jsonEncode(qrEventJson()),
        );
        clock.elapse(const Duration(milliseconds: 400));
        expect(inbox.pending, hasLength(1));
        expect(inbox.forTable(realtimeTableId, null), hasLength(1));
        expect(inbox.arrivals, 0);
        expect(r.qr.approvals, isEmpty);
        expect(r.orders.creates, isEmpty);
        r.qr.rows = [];
        r.factory.last.handlers['qr-order-requests']!(
          jsonEncode(qrEventJson(n: 2, kind: 'CANCELLED')),
        );
        clock.elapse(const Duration(milliseconds: 400));
        expect(inbox.pending, isEmpty);
        keep.close();
        r.dispose();
        clock.elapse(Duration.zero);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  test(
    'kitchen-only refetches kitchen queue and removes departed rows without order/inventory reads',
    () {
      fakeAsync((clock) {
        final r = _Rig(
          role: UserRole.kitchen,
          permissions: {'KITCHEN_VIEW'},
          features: {'KITCHEN_DISPLAY'},
        );
        clock.elapse(Duration.zero);
        r.factory.last.connected();
        clock.elapse(const Duration(milliseconds: 400));
        r.kitchen.rows = [
          KitchenDto.item(
            kitchenJson(orderId: realtimeOrderId, itemId: realtimeItemId),
          ),
        ];
        final keep = r.container.listen(kitchenDisplayProvider, (_, _) {});
        final display = r.container.read(kitchenDisplayProvider);
        display.setVisible(true);
        clock.elapse(Duration.zero);
        expect(display.items, hasLength(1));
        display.setSearch('phở');
        display.setMode(KitchenViewMode.orders);
        clock.elapse(const Duration(milliseconds: 300));
        r.kitchen.rows = [];
        final before = r.kitchen.queries.length;
        r.factory.last.handlers['kitchen-orders']!(orderEvent());
        clock.elapse(const Duration(milliseconds: 400));
        expect(display.items, isEmpty);
        expect(display.search, 'phở');
        expect(display.mode, KitchenViewMode.orders);
        expect(r.kitchen.queries.length, before + 3);
        expect(r.orders.detailCalls, 0);
        expect(r.orders.queries, isEmpty);
        keep.close();
        r.dispose();
        clock.elapse(Duration.zero);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  test(
    'fan-out refreshes both mounted consumers once and only newKitchenItemIds notify',
    () {
      fakeAsync((clock) {
        final r = _Rig();
        clock.elapse(Duration.zero);
        r.factory.last.connected();
        clock.elapse(const Duration(milliseconds: 400));
        final orderKeep = r.container.listen(
          orderDetailProvider(realtimeOrderId),
          (_, _) {},
        );
        final kitchenKeep = r.container.listen(
          kitchenDisplayProvider,
          (_, _) {},
        );
        final display = r.container.read(kitchenDisplayProvider);
        display.setVisible(true);
        clock.elapse(Duration.zero);
        final before = r.orders.detailCalls,
            beforeKitchen = r.kitchen.queries.length;
        final body = orderEvent(fresh: true);
        for (final id in ['orders', 'kitchen-orders']) {
          r.factory.last.handlers[id]!(body);
          r.factory.last.handlers[id]!(body);
        }
        clock.elapse(const Duration(milliseconds: 400));
        expect(r.orders.detailCalls, before + 1);
        expect(r.kitchen.queries.length, beforeKitchen + 3);
        expect(
          r.container.read(staffRealtimeNoticeProvider).message,
          contains('lượt món mới'),
        );
        r.container.read(staffRealtimeNoticeProvider).dismiss();
        r.factory.last.handlers['kitchen-orders']!(
          orderEvent(n: 2, version: 8),
        );
        clock.elapse(const Duration(milliseconds: 400));
        expect(r.container.read(staffRealtimeNoticeProvider).message, null);
        orderKeep.close();
        kitchenKeep.close();
        r.dispose();
        clock.elapse(Duration.zero);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  test(
    'order burst during GET keeps old display, drains one trailing read and ignores stale version',
    () {
      fakeAsync((clock) {
        final repo = FakeOrders(), events = OrderEvents();
        final c = detail(repo, () => orderSession(), events: events);
        final pending = Completer<Result<OrderDetail>>();
        repo.onDetail = () => pending.future;
        c.load();
        for (var i = 0; i < 8; i++) {
          events.invalidateRemote(OrderInvalidation(orderIds: ['o1']));
        }
        expect(repo.detailCalls, 1);
        expect(c.order!.version, 5);
        repo.onDetail = () async =>
            Success(OrderDto.detail(orderJson(version: 7)));
        pending.complete(Success(OrderDto.detail(orderJson(version: 6))));
        clock.flushMicrotasks();
        expect(repo.detailCalls, 2);
        expect(c.order!.version, 7);
        expect(c.loading, false);
        repo.onDetail = () async =>
            Success(OrderDto.detail(orderJson(version: 4)));
        c.load();
        clock.flushMicrotasks();
        expect(c.order!.version, 7);
        c.dispose();
        events.dispose();
      });
    },
  );
  test(
    'remote invalidation cannot release pending/unresolved writes or clear verification',
    () {
      fakeAsync((clock) {
        final repo = FakeOrders(), events = OrderEvents();
        final c = detail(repo, () => orderSession(), events: events);
        events.lock('o1');
        events.markUnresolved('o1', true);
        events.invalidateRemote(OrderInvalidation(orderIds: ['o1']));
        clock.flushMicrotasks();
        expect(events.pending('o1'), true);
        expect(events.unresolved('o1'), true);
        expect(repo.detailCalls, 0);
        events.unlock('o1');
        clock.flushMicrotasks();
        expect(repo.detailCalls, 0);
        expect(c.requiresVerification, true);
        c.dispose();
        events.dispose();
      });
    },
  );
  test(
    'remote list refresh preserves query/page and gets a coherent replacement snapshot',
    () {
      fakeAsync((clock) {
        final repo = FakeOrders(), events = OrderEvents();
        final c = OrderListController(
          session: () => orderSession(),
          events: events,
          get: GetOrders(repo),
          query: const OrderQuery(
            q: 'phở',
            page: 2,
            size: 10,
            sortBy: 'updatedAt',
            direction: 'asc',
          ),
        );
        final pending = Completer<Result<OrderPage>>();
        repo.onList = (_) => pending.future;
        c.load();
        for (var i = 0; i < 12; i++) {
          events.invalidateRemote(OrderInvalidation(orderIds: ['o$i']));
        }
        repo.onList = (q) async => Success(
          OrderPage(
            content: [],
            page: q.page,
            size: q.size,
            totalElements: 30,
            totalPages: 3,
          ),
        );
        pending.complete(
          Success(
            OrderPage(
              content: [repo.current.summary],
              page: 2,
              size: 10,
              totalElements: 30,
              totalPages: 3,
            ),
          ),
        );
        clock.flushMicrotasks();
        expect(repo.queries, hasLength(2));
        expect(c.page!.content, isEmpty);
        expect(c.query.q, 'phở');
        expect(c.query.page, 2);
        expect(c.query.sortBy, 'updatedAt');
        c.dispose();
        events.dispose();
      });
    },
  );
  test(
    'review context changes refetch; old confirmation/hash cannot approve',
    () {
      fakeAsync((clock) {
        final r = _Rig();
        clock.elapse(Duration.zero);
        r.factory.last.connected();
        clock.elapse(const Duration(milliseconds: 400));
        r.qr.reviewData = QrRequestDto.review(qrReviewJson());
        final keep = r.container.listen(qrReviewProvider('qr-1'), (_, _) {});
        clock.elapse(Duration.zero);
        final review = r.container.read(qrReviewProvider('qr-1')),
            old = review.review!;
        final pending = Completer<Result<QrRequestReview>>();
        r.qr.onReview = (_) => pending.future;
        r.container
            .read(orderEventsProvider)
            .invalidateRemote(OrderInvalidation(orderIds: ['o1']));
        clock.elapse(Duration.zero);
        expect(review.canApprove, false);
        expect(review.needsReload, true);
        review.approve(old, confirmed: true);
        clock.flushMicrotasks();
        expect(r.qr.approvals, isEmpty);
        pending.complete(
          Success(QrRequestDto.review(qrReviewJson(hash: 'b' * 64))),
        );
        clock.flushMicrotasks();
        review.approve(old, confirmed: true);
        clock.flushMicrotasks();
        expect(r.qr.approvals, isEmpty);
        expect(review.review!.hash, 'b' * 64);
        keep.close();
        r.dispose();
        clock.elapse(Duration.zero);
      });
    },
  );
  test(
    'permission revocation closes old socket before reconnecting remaining channels; no stale frame',
    () {
      fakeAsync((clock) {
        final r = _Rig();
        clock.elapse(Duration.zero);
        r.factory.last.connected();
        clock.elapse(const Duration(milliseconds: 400));
        final old = r.factory.last,
            lateFrame = r.factory.last.handlers['orders']!;
        r.entitlement.result = Success(
          makeEntitlement(features: {'ORDER_MANAGEMENT', 'KITCHEN_DISPLAY'}),
        );
        r.auth.revalidateAccess();
        clock.elapse(Duration.zero);
        expect(old.closed, true);
        r.factory.last.connected();
        expect(r.factory.last.handlers.keys.toSet(), {
          'orders',
          'qr-order-requests',
          'kitchen-orders',
        });
        clock.elapse(const Duration(milliseconds: 400));
        final revision = r.container.read(orderEventsProvider).revision;
        lateFrame(orderEvent(n: 30));
        clock.elapse(const Duration(milliseconds: 400));
        expect(r.container.read(orderEventsProvider).revision, revision);
        r.auth.logout();
        clock.elapse(Duration.zero);
        expect(r.factory.last.closed, true);
        r.dispose();
        clock.elapse(Duration.zero);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  for (final mode in RealtimeTransportMode.values) {
    test(
      'disabled or polling configuration never opens an alternate socket ($mode)',
      () {
        fakeAsync((clock) {
          final r = _Rig(
            enabled: mode == RealtimeTransportMode.polling,
            mode: mode,
          );
          clock.elapse(const Duration(seconds: 1));
          expect(r.factory.transports, isEmpty);
          r.dispose();
          clock.elapse(Duration.zero);
          expect(clock.pendingTimers, isEmpty);
        });
      },
    );
  }
}
