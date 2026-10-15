import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/kitchen/data/dto/kitchen_dto.dart';
import 'package:pos_saas_app/features/kitchen/domain/entities/kitchen_queue.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import '../../helpers/auth_fakes.dart';
import 'kitchen_fakes.dart';

void main() {
  test(
    'append during Ready batch stops remaining lines and retains new PENDING',
    () async {
      final repo = FakeKitchen()
        ..rows = [
          KitchenDto.item(kitchenJson(itemId: 'i1', status: 'COOKING')),
          KitchenDto.item(kitchenJson(itemId: 'i2', status: 'COOKING')),
        ];
      repo.onTransition = (input) async {
        repo.perform(input);
        repo.rows.add(KitchenDto.item(kitchenJson(itemId: 'new', version: 4)));
        return Success(
          kitchenOrder(repo.rows, version: 4, rootStatus: 'PREPARING'),
        );
      };
      final rig = KitchenRig(repository: repo);
      addTearDown(rig.dispose);
      await rig.display.refresh();
      await rig.actions.readyOrder('o1');
      expect(repo.writes.length, 1);
      expect(
        rig.display
            .forOrder('o1')
            .any(
              (r) =>
                  r.orderItemId == 'new' &&
                  r.itemStatus == OrderItemStatus.pending,
            ),
        true,
      );
      expect(rig.display.orderStatuses['o1'], OrderStatus.preparing);
      expect(rig.actions.state('o1')!.needsReview, true);
    },
  );
  test(
    'queue updates current seating after transfer without increasing order version',
    () async {
      final rig = KitchenRig();
      addTearDown(rig.dispose);
      await rig.display.refresh();
      rig.repo.rows = [KitchenDto.item(kitchenJson(table: 'Bàn mới'))];
      await rig.display.refresh();
      expect(rig.display.items.single.tableName, 'Bàn mới');
      expect(rig.display.items.single.orderVersion, 3);
      expect(rig.repo.writes, isEmpty);
    },
  );
  test(
    'POST success survives failed GET refresh; uncertain retry still works after queue disappears',
    () async {
      final rig = KitchenRig();
      addTearDown(rig.dispose);
      await rig.display.refresh();
      rig.repo.onQueue = (_) async => const Error(networkFailure);
      await rig.actions.act(
        rig.display.items.first,
        KitchenAction.startCooking,
      );
      await rig.display.refresh();
      expect(rig.display.items.single.itemStatus, OrderItemStatus.cooking);
      expect(rig.repo.writes.length, 1);
      rig.repo.onQueue = null;
      await rig.display.refresh();
      final line = rig.display.items.single;
      rig.repo.onTransition = (_) async => const Error(networkFailure);
      await rig.actions.act(line, KitchenAction.markReady);
      final old = rig.repo.rows;
      rig.repo.rows = [];
      rig.display.invalidateReads();
      await rig.display.refresh();
      expect(rig.display.items, isEmpty);
      expect(rig.actions.state('o1')!.uncertain, true);
      expect(rig.actions.canRetry('o1'), true);
      rig.repo.rows = old;
      rig.repo.onTransition = null;
      await rig.actions.retry('o1');
      expect(rig.actions.state('o1')!.uncertain, false);
    },
  );
  test('view-only and missing feature cannot start a mutation', () async {
    final rig = KitchenRig(permissions: {'KITCHEN_VIEW'});
    addTearDown(rig.dispose);
    await rig.display.refresh();
    await rig.actions.act(rig.display.items.first, KitchenAction.startCooking);
    expect(rig.repo.writes, isEmpty);
    rig.appSession = makeAppSession(
      permissions: kitchenPermissions,
      features: {},
    );
    await rig.display.refresh();
    expect(rig.display.items, isEmpty);
    expect(rig.actions.canRetry('o1'), false);
  });
  test(
    'all statuses and later pages are loaded; no per-card request',
    () async {
      final repo = FakeKitchen()
        ..rows = [
          for (var i = 0; i < 41; i++)
            KitchenDto.item(kitchenJson(orderId: 'o$i', itemId: 'i$i')),
          KitchenDto.item(kitchenJson(orderId: 'oc', status: 'COOKING')),
          KitchenDto.item(kitchenJson(orderId: 'or', status: 'READY')),
        ];
      final rig = KitchenRig(repository: repo);
      addTearDown(rig.dispose);
      await rig.display.refresh();
      expect(rig.display.items.length, 43);
      expect(
        repo.queries
            .where((q) => q.status == OrderItemStatus.pending)
            .map((q) => q.page),
        [0, 1, 2],
      );
      expect(rig.display.complete, true);
      rig.display.setFilter(OrderItemStatus.cooking);
      expect(rig.display.visibleItems.length, 1);
      expect(repo.queries.length, 5);
    },
  );
  test(
    'double submit is locked per order while another order remains operable',
    () async {
      final repo = FakeKitchen()
        ..rows = [
          KitchenDto.item(kitchenJson()),
          KitchenDto.item(kitchenJson(orderId: 'o2')),
        ];
      final rig = KitchenRig(repository: repo);
      addTearDown(rig.dispose);
      await rig.display.refresh();
      final pending = Completer<Result<OrderDetail>>();
      repo.onTransition = (input) => pending.future;
      final row = rig.display.items.first;
      final first = rig.actions.act(row, KitchenAction.startCooking);
      await rig.actions.act(row, KitchenAction.startCooking);
      expect(repo.writes.length, 1);
      expect(
        rig.actions.canAct(
          rig.display.forOrder('o2').first,
          KitchenAction.startCooking,
        ),
        true,
      );
      pending.complete(repo.perform(repo.writes.single));
      await first;
      expect(
        rig.display.forOrder('o1').first.itemStatus,
        OrderItemStatus.cooking,
      );
    },
  );
  test(
    'Ready batch chains order versions and trusts server root, even when PAID',
    () async {
      final repo = FakeKitchen()
        ..paid = true
        ..rows = [
          KitchenDto.item(kitchenJson(itemId: 'i1', status: 'COOKING')),
          KitchenDto.item(kitchenJson(itemId: 'i2', status: 'COOKING')),
        ];
      final rig = KitchenRig(repository: repo);
      addTearDown(rig.dispose);
      await rig.display.refresh();
      final result = await rig.actions.readyOrder('o1');
      expect(result, isA<Success<OrderDetail>>());
      expect(repo.writes.map((i) => i.expectedOrderVersion), [3, 4]);
      expect(rig.display.orderStatuses['o1'], OrderStatus.ready);
      expect(
        rig.display
            .forOrder('o1')
            .every((r) => r.itemStatus == OrderItemStatus.ready),
        true,
      );
    },
  );
  test(
    'timeout retains exact action/version through queue refresh and token rotation',
    () async {
      final rig = KitchenRig();
      addTearDown(rig.dispose);
      await rig.display.refresh();
      rig.repo.onTransition = (input) async {
        rig.repo.perform(input);
        return const Error(networkFailure);
      };
      await rig.actions.act(
        rig.display.items.first,
        KitchenAction.startCooking,
      );
      final intent = rig.repo.writes.single;
      await rig.display.refresh();
      rig.appSession = rig.appSession!.copyWithAuth(
        user: rig.appSession!.authenticatedUser,
        tokens: makeTokens(accessToken: 'rotated'),
      );
      expect(rig.actions.state('o1')!.uncertain, true);
      expect(rig.events.unresolved('o1'), true);
      rig.repo.onTransition = null;
      await rig.actions.retry('o1');
      expect(identical(rig.repo.writes.last, intent), true);
      expect(rig.actions.state('o1')!.uncertain, false);
      expect(rig.display.forOrder('o1').first.orderVersion, 4);
    },
  );
  test(
    'batch stops at uncertain second line and preserves confirmed first line',
    () async {
      final repo = FakeKitchen()
        ..rows = [
          KitchenDto.item(kitchenJson(itemId: 'i1', status: 'COOKING')),
          KitchenDto.item(kitchenJson(itemId: 'i2', status: 'COOKING')),
          KitchenDto.item(kitchenJson(itemId: 'i3', status: 'COOKING')),
        ];
      repo.onTransition = (input) async => input.orderItemId == 'i2'
          ? const Error(networkFailure)
          : repo.perform(input);
      final rig = KitchenRig(repository: repo);
      addTearDown(rig.dispose);
      await rig.display.refresh();
      await rig.actions.readyOrder('o1');
      expect(repo.writes.length, 2);
      expect(
        rig.display
            .forOrder('o1')
            .firstWhere((r) => r.orderItemId == 'i1')
            .itemStatus,
        OrderItemStatus.ready,
      );
      final original = repo.writes.last;
      repo.onTransition = null;
      await rig.actions.retry('o1');
      expect(identical(repo.writes.last, original), true);
      expect(repo.writes.any((i) => i.orderItemId == 'i3'), false);
    },
  );
  test(
    'conflict reloads without POST retry and requires explicit review',
    () async {
      final rig = KitchenRig();
      addTearDown(rig.dispose);
      await rig.display.refresh();
      rig.repo.rows = [KitchenDto.item(kitchenJson(version: 4))];
      await rig.actions.act(
        rig.display.items.first,
        KitchenAction.startCooking,
      );
      await rig.display.refresh();
      expect(rig.repo.writes.length, 1);
      expect(rig.actions.state('o1')!.needsReview, true);
      expect(
        rig.actions.canAct(rig.display.items.first, KitchenAction.startCooking),
        false,
      );
      rig.actions.review('o1');
      expect(
        rig.actions.canAct(rig.display.items.first, KitchenAction.startCooking),
        true,
      );
    },
  );
  test(
    'late old queue cannot overwrite POST; tenant change rejects late mutation',
    () async {
      final rig = KitchenRig();
      addTearDown(rig.dispose);
      await rig.display.refresh();
      final old = rig.repo.rows.toList();
      final read = Completer<Result<KitchenQueuePage>>();
      rig.repo.onQueue = (q) => q.status == OrderItemStatus.pending
          ? read.future
          : Future.value(
              Success(
                KitchenQueuePage(
                  content: [],
                  page: 0,
                  size: 20,
                  totalElements: 0,
                  totalPages: 0,
                ),
              ),
            );
      final reading = rig.display.refresh();
      await rig.actions.act(
        rig.display.items.first,
        KitchenAction.startCooking,
      );
      read.complete(
        Success(
          KitchenQueuePage(
            content: old,
            page: 0,
            size: 20,
            totalElements: 1,
            totalPages: 1,
          ),
        ),
      );
      await reading;
      expect(rig.display.items.first.itemStatus, OrderItemStatus.cooking);
      rig.repo.onQueue = null;
      await rig.display.refresh();
      final write = Completer<Result<OrderDetail>>();
      rig.repo.onTransition = (_) => write.future;
      final sending = rig.actions.act(
        rig.display.items.first,
        KitchenAction.markReady,
      );
      rig.appSession = makeAppSession(
        restaurantId: 'other',
        permissions: kitchenPermissions,
        features: {'KITCHEN_DISPLAY'},
      );
      write.complete(
        Success(kitchenOrder(rig.repo.rows, version: 5, rootStatus: 'READY')),
      );
      expect(await sending, isA<Error<OrderDetail>>());
      expect(rig.display.items, isEmpty);
    },
  );
  test(
    'partial data blocks batch; search/summary preserves notes, units and decimals',
    () async {
      final repo = FakeKitchen()
        ..rows = [
          KitchenDto.item(kitchenJson(status: 'COOKING', quantity: 1.25)),
          KitchenDto.item(
            kitchenJson(
              itemId: 'i2',
              status: 'COOKING',
              unit: 'kg',
              quantity: 0.5,
            ),
          ),
          KitchenDto.item(
            kitchenJson(itemId: 'i3', status: 'COOKING', note: 'Có hành'),
          ),
        ];
      final rig = KitchenRig(repository: repo);
      addTearDown(rig.dispose);
      await rig.display.refresh();
      expect(summarizeKitchenDishes(rig.display.items).length, 3);
      repo.onQueue = (q) async => const Error(networkFailure);
      await rig.display.refresh();
      expect(rig.display.items.length, 3);
      expect(rig.actions.canReadyOrder('o1'), false);
      expect(repo.writes, isEmpty);
    },
  );
  test(
    'transfer/external order mutation blocks only related session',
    () async {
      final repo = FakeKitchen()
        ..rows = [
          KitchenDto.item(kitchenJson()),
          KitchenDto.item(kitchenJson(orderId: 'o2')),
        ];
      final rig = KitchenRig(repository: repo);
      addTearDown(rig.dispose);
      await rig.display.refresh();
      rig.tables.lockTransfer('s-o1');
      expect(
        rig.actions.canAct(
          rig.display.forOrder('o1').first,
          KitchenAction.startCooking,
        ),
        false,
      );
      expect(
        rig.actions.canAct(
          rig.display.forOrder('o2').first,
          KitchenAction.startCooking,
        ),
        true,
      );
    },
  );
  testWidgets(
    'poll is single flight and pauses on hidden/background lifecycle',
    (tester) async {
      final rig = KitchenRig(interval: const Duration(seconds: 1));
      addTearDown(rig.dispose);
      rig.display.setVisible(true);
      await tester.pump();
      final initial = rig.repo.queries.length;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(rig.repo.queries.length, greaterThan(initial));
      rig.display.setForeground(false);
      final stopped = rig.repo.queries.length;
      await tester.pump(const Duration(seconds: 10));
      expect(rig.repo.queries.length, stopped);
      rig.display.setForeground(true);
      await tester.pump();
      rig.display.setVisible(false);
      final hidden = rig.repo.queries.length;
      await tester.pump(const Duration(seconds: 10));
      expect(rig.repo.queries.length, hidden);
    },
  );
}
