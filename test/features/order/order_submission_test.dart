import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/network/auth_interceptor.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/order/data/data_sources/order_remote_data_source.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/data/dto/order_requests.dart';
import 'package:pos_saas_app/features/order/data/repositories/order_repository_impl.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_inputs.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_quantity.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_submission.dart';
import 'package:pos_saas_app/features/order/domain/policies/order_access_policy.dart';
import 'package:pos_saas_app/features/order/domain/use_cases/order_use_cases.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_append_controller.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_detail_controller.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_events.dart';
import '../../helpers/auth_fakes.dart';
import '../menu/menu_fakes.dart';
import 'order_fakes.dart';
import 'order_data_test.dart' show CreateRetryAdapter;
import '../../core/network/auth_interceptor_test.dart' show RefreshAdapter;

final dish = MenuItemDto.fromJson(itemJson()..['id'] = itemId).toEntity();
const concurrent = Failure(
  type: FailureType.conflict,
  code: 'CONCURRENT_ORDER_UPDATE',
  message: 'Conflict',
);

class AppendHarness {
  AppendHarness({AppSession? Function()? session, OrderDetail? initial}) {
    who = session ?? () => orderSession();
    if (initial != null) repo.current = initial;
    read = detail(repo, who, events: events);
    cart = OrderAppendController(
      session: who,
      events: events,
      id: 'o1',
      root: () => read.order,
      blocked: () => read.requiresVerification,
      beforeSend: read.beginSubmission,
      onApplied: read.applySubmission,
      appliedSource: () => read,
      submitItems: SubmitOrderItems(repo),
      keys: keys,
    )..begin(repo.current);
  }
  final repo = FakeOrders();
  final events = OrderEvents();
  final keys = TestKeys();
  late final AppSession? Function() who;
  late final OrderDetailController read;
  late final OrderAppendController cart;
  void close() {
    cart.dispose();
    read.dispose();
    events.dispose();
  }
}

void main() {
  test(
    '401 refresh retry preserves append key, baseline version, mode and ordered payload',
    () async {
      final adapter = CreateRetryAdapter();
      final client = Dio()..httpClientAdapter = adapter;
      final refresh = Dio()..httpClientAdapter = RefreshAdapter();
      client.interceptors.add(
        AuthInterceptor(
          client: client,
          refreshClient: refresh,
          tokenStorage: FakeTokenStorage(makeTokens(accessToken: 'old-access')),
          sessionEvents: SessionEvents(),
        ),
      );
      final result = await OrderRepositoryImpl(OrderRemoteDataSource(client))
          .submitItems(
            'o1',
            AddOrderItemsInput(
              expectedVersion: 5,
              submissionMode: OrderSubmissionMode.submit,
              items: [
                CreateOrderLine(itemId: itemId, quantity: OrderQuantity.one),
              ],
            ),
            'append-original-key',
          );
      expect(result, isA<Success<OrderSubmission>>());
      expect(adapter.requests.length, 2);
      expect(adapter.requests.first, adapter.requests.last);
      client.close();
      refresh.close();
    },
  );
  test(
    'legacy serializers omit mode; SUBMIT is explicit, append input immutable',
    () {
      final line = CreateOrderLine(itemId: itemId, quantity: OrderQuantity.one);
      final old = CreateOrderInput(
        context: const OrderCreationContext.takeaway(),
        items: [line],
      );
      expect(OrderRequests.create(old).containsKey('submissionMode'), false);
      final submit = CreateOrderInput(
        context: const OrderCreationContext.takeaway(),
        items: [line],
        submissionMode: OrderSubmissionMode.submit,
      );
      expect(OrderRequests.create(submit)['submissionMode'], 'SUBMIT');
      final source = [line];
      final addition = AddOrderItemsInput(
        expectedVersion: 5,
        items: source,
        submissionMode: OrderSubmissionMode.submit,
      );
      source.clear();
      expect(addition.items.length, 1);
      expect(() => addition.items.clear(), throwsUnsupportedError);
      expect(
        OrderRequests.addition(addition).keys,
        unorderedEquals(['expectedVersion', 'items', 'submissionMode']),
      );
      expect(
        OrderRequests.addition(addition)['items'],
        isNot(contains('unitPrice')),
      );
    },
  );
  test(
    'create needs both permissions for SUBMIT, DRAFT and no VIEW remain supported',
    () async {
      final repo = FakeOrders();
      final c = draft(
        repo,
        () => orderSession(permissions: {'ORDER_CREATE', 'MENU_VIEW'}),
      );
      addTearDown(c.dispose);
      c.add(dish);
      expect(c.canSubmit, false);
      expect(
        await c.submit(mode: OrderSubmissionMode.submit),
        isA<Error<OrderDetail>>(),
      );
      expect(repo.creates, isEmpty);
      expect(
        await c.submit(mode: OrderSubmissionMode.draft),
        isA<Success<OrderDetail>>(),
      );
      expect(repo.creates.single.$1.submissionMode, OrderSubmissionMode.draft);
      expect(repo.detailCalls, 0);
    },
  );
  test(
    'SUBMIT create is a single call and never invokes legacy confirmation',
    () async {
      final repo = FakeOrders();
      final c = draft(repo, () => orderSession());
      addTearDown(c.dispose);
      c.add(dish);
      await c.submit(mode: OrderSubmissionMode.submit);
      expect(c.result!.summary.status, OrderStatus.confirmed);
      expect(c.result!.confirmedAt, isNotNull);
      expect(c.result!.items.single.sentToKitchenAt, isNull);
      expect(repo.writes, isEmpty);
      expect(c.replayed, false);
    },
  );
  test(
    'create timeout freezes mode/key/payload, cannot downgrade retry',
    () async {
      final repo = FakeOrders()
        ..onCreate = () async => const Error(networkFailure);
      final c = draft(repo, () => orderSession());
      addTearDown(c.dispose);
      c.add(dish);
      await c.submit(mode: OrderSubmissionMode.submit);
      expect(c.uncertain, true);
      await c.submit(mode: OrderSubmissionMode.draft);
      expect(repo.creates.length, 1);
      repo.onCreate = () async => Success(repo.current);
      await c.retry();
      expect(identical(repo.creates.first.$1, repo.creates.last.$1), true);
      expect(repo.creates.first.$2, repo.creates.last.$2);
      expect(repo.creates.last.$1.submissionMode, OrderSubmissionMode.submit);
    },
  );
  test(
    'context identity survives remount/display changes for same session',
    () {
      expect(
        const OrderCreationContext.dineIn(
          sessionId: sessionId,
          guestCount: 1,
          tableName: 'A',
        ),
        const OrderCreationContext.dineIn(
          sessionId: sessionId,
          guestCount: 4,
          tableName: 'B',
        ),
      );
      expect(
        const OrderCreationContext.takeaway(),
        isNot(const OrderCreationContext.dineIn(sessionId: sessionId)),
      );
    },
  );
  test(
    'append confirmed order only sends new lines and applies server snapshots/totals',
    () async {
      final h = AppendHarness(
        initial: OrderDto.detail(
          orderJson(status: 'CONFIRMED', confirmed: true),
        ),
      );
      addTearDown(h.close);
      final oldLine = h.read.order!.items.single;
      final oldConfirmed = h.read.order!.confirmedAt;
      h.cart.add(dish);
      h.cart.add(dish);
      expect(h.cart.lines.first.id, isNot(h.cart.lines.last.id));
      h.cart.edit(h.cart.lines.last.id, OrderQuantity.parse('1.125'), 'Ít cay');
      expect(h.cart.lines.length, 2);
      await h.cart.send();
      final sent = h.repo.submissions.single;
      expect(sent.$1, 'o1');
      expect(sent.$2.expectedVersion, 5);
      expect(sent.$2.submissionMode, OrderSubmissionMode.submit);
      expect(sent.$2.items.length, 2);
      expect(sent.$2.items.last.note, 'Ít cay');
      expect(h.read.order!.id, 'o1');
      expect(h.read.order!.version, 7); // Do not assume +1.
      expect(h.read.order!.items.length, 3);
      expect(h.read.order!.items.first.itemName, oldLine.itemName);
      expect(
        h.read.order!.items.first.unitPrice.minorUnits,
        oldLine.unitPrice.minorUnits,
      );
      expect(h.read.order!.confirmedAt, oldConfirmed);
      expect(h.read.order!.items.last.unitPrice.minorUnits, 6000000);
      expect(h.read.order!.items.last.status, OrderItemStatus.pending);
      expect(h.read.order!.items.last.sentToKitchenAt, isNull);
      expect(h.events.revision, 1);
    },
  );
  test(
    'OPEN append confirms, old edit and cancellation boundary remain separate',
    () async {
      final h = AppendHarness(
        session: () => orderSession(permissions: {'ORDER_UPDATE', 'MENU_VIEW'}),
      );
      addTearDown(h.close);
      h.cart.add(dish);
      await h.cart.send();
      expect(h.read.order!.summary.status, OrderStatus.confirmed);
      expect(h.read.editable, false);
      expect(h.read.lineCancellable(h.read.order!.items.last), false);
      expect(h.repo.detailCalls, 0);
      expect(h.repo.creates, isEmpty);
      expect(h.repo.writes, isEmpty);
    },
  );
  test(
    'append type feature is required, TAKEAWAY does not need TABLE or CREATE',
    () {
      final session = orderSession(
        permissions: {'ORDER_UPDATE', 'MENU_VIEW'},
        features: {'ORDER_MANAGEMENT', 'POS_QUICK_ORDER', 'MENU_MANAGEMENT'},
      );
      expect(AccessPolicy.canAppendOrder(session, takeaway: true), true);
      expect(AccessPolicy.canAppendOrder(session, takeaway: false), false);
      expect(AccessPolicy.canSubmitOrder(session, takeaway: true), false);
      final h = AppendHarness(session: () => session);
      addTearDown(h.close);
      expect(h.cart.canPick, true);
    },
  );
  test('financial and terminal roots never allow new submitted append', () {
    for (final status in OrderStatus.values) {
      final o = OrderDto.detail(orderJson(status: status.code));
      expect(
        OrderAccessPolicy.canAppend(o, true),
        [
          OrderStatus.open,
          OrderStatus.confirmed,
          OrderStatus.preparing,
          OrderStatus.ready,
          OrderStatus.served,
        ].contains(status),
      );
    }
    for (final payment in OrderPaymentStatus.values.where(
      (p) => p != OrderPaymentStatus.unpaid,
    )) {
      final data = orderJson()..['paymentStatus'] = payment.code;
      expect(OrderAccessPolicy.canAppend(OrderDto.detail(data), true), false);
    }
    expect(
      OrderAccessPolicy.canAppend(
        OrderDto.detail(orderJson()..['paidAmount'] = 1),
        true,
      ),
      false,
    );
    expect(
      OrderAccessPolicy.canAppend(OrderDto.detail(orderJson()), false),
      false,
    );
  });
  test(
    'unknown outcome survives GET; stale/terminal cache cannot block matching retry',
    () async {
      final h = AppendHarness();
      addTearDown(h.close);
      h.cart.add(dish);
      h.repo.onSubmitItems = () async => const Error(networkFailure);
      await h.cart.send();
      final original = h.repo.submissions.single;
      expect(h.cart.uncertain, true);
      h.repo.current = OrderDto.detail(
        orderJson(version: 9, status: 'CANCELLED', confirmed: true),
      );
      await h.read.load();
      expect(h.read.order!.version, 9);
      expect(h.read.requiresVerification, true);
      expect(h.cart.uncertain, true);
      expect(h.cart.reviewCurrent(), false);
      h.cart.remove(h.cart.lines.single.id);
      h.cart.add(dish);
      expect(h.cart.lines.length, 1);
      await h.cart.send();
      expect(h.repo.submissions.length, 1);
      await h.read.cancel(9, 'Cannot cancel unknown intent');
      expect(h.repo.writes, isEmpty);
      h.repo.onSubmitItems = () async =>
          Success(OrderSubmission(h.repo.current, replayed: true));
      await h.cart.retry();
      expect(identical(h.repo.submissions.last.$2, original.$2), true);
      expect(h.repo.submissions.last.$3, original.$3);
      expect(h.repo.submissions.last.$2.expectedVersion, 5);
      expect(h.read.order!.summary.status, OrderStatus.cancelled);
      expect(h.cart.result!.replayed, true);
      expect(h.cart.uncertain, false);
      expect(h.read.requiresVerification, false);
    },
  );
  test('double tap uses one request and key while busy', () async {
    final h = AppendHarness();
    addTearDown(h.close);
    h.cart.add(dish);
    final pending = Completer<Result<OrderSubmission>>();
    h.repo.onSubmitItems = () => pending.future;
    final first = h.cart.send();
    await h.cart.send();
    await h.cart.retry();
    expect(h.repo.submissions.length, 1);
    expect(h.keys.calls, 2); // One local line ID, one intent key.
    pending.complete(Success(OrderSubmission(h.repo.current, replayed: false)));
    await first;
  });
  test(
    'definite conflict preserves cart and requires explicit rebase, never blind retry',
    () async {
      final h = AppendHarness();
      addTearDown(h.close);
      h.cart.add(dish);
      h.repo.onSubmitItems = () async => const Error(concurrent);
      await h.cart.send();
      final old = h.repo.submissions.single;
      expect(h.cart.needsReview, true);
      expect(h.cart.uncertain, false);
      expect(h.cart.lines.length, 1);
      expect(h.cart.reviewCurrent(), false);
      await h.cart.retry();
      await h.cart.send();
      expect(h.repo.submissions.length, 1);
      h.repo.current = OrderDto.detail(orderJson(version: 8));
      await h.read.load();
      expect(h.cart.needsReview, true);
      expect(h.cart.reviewCurrent(), true);
      h.repo.onSubmitItems = null;
      await h.cart.send();
      expect(h.repo.submissions.last.$2.expectedVersion, 8);
      expect(h.repo.submissions.last.$3, isNot(old.$3));
      expect(old.$2.expectedVersion, 5);
      expect(h.repo.creates, isEmpty);
    },
  );
  test(
    'key conflict never invents a new key or treats refusal as replay',
    () async {
      final h = AppendHarness();
      addTearDown(h.close);
      h.cart.add(dish);
      h.repo.onSubmitItems = () async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'IDEMPOTENCY_KEY_REUSED',
          message: 'Key conflict',
        ),
      );
      await h.cart.send();
      expect(h.cart.uncertain, true);
      expect(h.cart.canRetry, false);
      h.cart.discard();
      await h.cart.send();
      await h.cart.retry();
      expect(h.repo.submissions.length, 1);
      expect(h.cart.lines.length, 1);
      expect(h.cart.result, isNull);
    },
  );
  test(
    'invalid success response keeps frozen key and payload until resolved',
    () async {
      final h = AppendHarness();
      addTearDown(h.close);
      h.cart.add(dish);
      h.repo.onSubmitItems = () async => const Error(
        Failure(
          type: FailureType.internal,
          code: 'INVALID_ORDER_RESPONSE',
          message: 'Invalid response',
        ),
      );
      await h.cart.send();
      expect(h.cart.uncertain, true);
      final key = h.repo.submissions.single.$3;
      h.repo.onSubmitItems = () async =>
          Success(OrderSubmission(h.repo.current));
      await h.cart.retry();
      expect(h.repo.submissions.last.$3, key);
    },
  );
  test(
    '401/403 while resolving unknown outcome cannot falsely clear the intent',
    () async {
      final h = AppendHarness();
      addTearDown(h.close);
      h.cart.add(dish);
      h.repo.onSubmitItems = () async => const Error(networkFailure);
      await h.cart.send();
      h.repo.onSubmitItems = () async => const Error(
        Failure(
          type: FailureType.forbidden,
          code: 'FORBIDDEN',
          message: 'Missing authority',
        ),
      );
      await h.cart.retry();
      expect(h.cart.uncertain, true);
      expect(h.read.requiresVerification, true);
      expect(h.repo.submissions.first.$3, h.repo.submissions.last.$3);
    },
  );
  test(
    'token rotation preserves intent, scope loss ignores late result',
    () async {
      AppSession? session = orderSession();
      final h = AppendHarness(session: () => session);
      addTearDown(h.close);
      h.cart.add(dish);
      h.repo.onSubmitItems = () async => const Error(networkFailure);
      await h.cart.send();
      final original = h.repo.submissions.single;
      session = session.copyWithAuth(
        user: session.authenticatedUser,
        tokens: makeTokens(accessToken: 'rotated'),
      );
      final pending = Completer<Result<OrderSubmission>>();
      h.repo.onSubmitItems = () => pending.future;
      final retry = h.cart.retry();
      expect(h.repo.submissions.last.$3, original.$3);
      session = null;
      pending.complete(
        Success(
          OrderSubmission(
            OrderDto.detail(orderJson(version: 8)),
            replayed: true,
          ),
        ),
      );
      expect(await retry, isA<Error<OrderDetail>>());
      expect(h.cart.result, isNull);
      expect(h.read.order!.version, 5);
    },
  );
  test('old GET cannot overwrite submitted mutation response', () async {
    final h = AppendHarness();
    addTearDown(h.close);
    final pending = Completer<Result<OrderDetail>>();
    h.repo.onDetail = () => pending.future;
    final get = h.read.load();
    h.cart.add(dish);
    await h.cart.send();
    pending.complete(Success(OrderDto.detail(orderJson(version: 5))));
    await get;
    expect(h.read.order!.version, 7);
  });
  test(
    'new cart after completed append takes new baseline without reusing prior key',
    () async {
      final h = AppendHarness();
      addTearDown(h.close);
      h.cart.add(dish);
      await h.cart.send();
      final first = h.repo.submissions.single;
      h.cart.begin(h.read.order!);
      h.cart.add(dish);
      await h.cart.send();
      expect(h.repo.submissions.last.$2.expectedVersion, 7);
      expect(h.repo.submissions.last.$3, isNot(first.$3));
      expect(h.read.order!.items.length, 3);
    },
  );
  test(
    'cart uses exact preview, separate duplicate lines and validates 100 line limit',
    () {
      final h = AppendHarness();
      addTearDown(h.close);
      final tiny = MenuItemDto.fromJson(
        itemJson()
          ..['id'] = itemId
          ..['salePrice'] = .05,
      ).toEntity();
      h.cart.add(tiny);
      h.cart.edit(h.cart.lines.single.id, OrderQuantity.parse('0.1'), 'A');
      expect(h.cart.previewMinor, BigInt.one);
      for (var i = 0; i < 100; i++) {
        h.cart.add(dish);
      }
      expect(h.cart.lines.length, 100);
      expect(h.cart.failure!.type, FailureType.validation);
    },
  );
  test(
    'data layer submits exact allowlist/header and exposes replay metadata',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, handler) {
              requests.add(r);
              handler.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 200,
                  headers: Headers.fromMap({
                    'idempotency-replayed': ['true'],
                  }),
                  data: orderJson(
                    version: 9,
                    status: 'CANCELLED',
                    confirmed: true,
                  ),
                ),
              );
            },
          ),
        );
      addTearDown(dio.close);
      final repo = OrderRepositoryImpl(OrderRemoteDataSource(dio));
      final input = AddOrderItemsInput(
        expectedVersion: 5,
        submissionMode: OrderSubmissionMode.submit,
        items: [
          CreateOrderLine(
            itemId: itemId,
            quantity: OrderQuantity.parse('1.125'),
            note: 'Ít cay',
          ),
        ],
      );
      final result = await repo.submitItems('o1', input, 'append-stable');
      expect((result as Success<OrderSubmission>).value.replayed, true);
      expect(result.value.order.version, 9);
      expect(result.value.order.summary.status, OrderStatus.cancelled);
      expect(requests.single.path, '/api/v1/orders/o1/items');
      expect(requests.single.headers['Idempotency-Key'], 'append-stable');
      expect(requests.single.data, OrderRequests.addition(input));
      expect(
        (requests.single.data as Map).keys,
        isNot(contains('idempotencyKey')),
      );
    },
  );
  test(
    'malformed replay metadata and foreign target are invalid successful responses',
    () async {
      for (final invalidHeader in [true, false]) {
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (r, h) {
                final data = orderJson()
                  ..['id'] = invalidHeader ? 'o1' : 'foreign';
                h.resolve(
                  Response(
                    requestOptions: r,
                    statusCode: 200,
                    data: data,
                    headers: Headers.fromMap({
                      'idempotency-replayed': [invalidHeader ? 'yes' : 'false'],
                    }),
                  ),
                );
              },
            ),
          );
        final result = await OrderRepositoryImpl(OrderRemoteDataSource(dio))
            .submitItems(
              'o1',
              AddOrderItemsInput(
                expectedVersion: 5,
                items: [],
                submissionMode: OrderSubmissionMode.submit,
              ),
              'key',
            );
        expect((result as Error).failure.code, 'INVALID_ORDER_RESPONSE');
        dio.close();
      }
    },
  );
}
