import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_detail_screen.dart';

import '../tables/table_fakes.dart';
import 'order_fakes.dart';
import 'order_widget_test.dart' show pumpOrder;

const _permissions = {
  'ORDER_VIEW',
  'ORDER_UPDATE',
  'MENU_VIEW',
  'TABLE_VIEW',
  'TABLE_TRANSFER',
};

void main() {
  testWidgets('dine-in order exposes transfer while takeaway never does', (
    tester,
  ) async {
    final tables = TableServer()
      ..session = sessionJson(id: sessionId)
      ..table = tableJson(id: 't2', code: 'B02', name: 'Garden table');
    final orders = FakeOrders()
      ..current = OrderDto.detail(
        orderJson(status: 'CONFIRMED', confirmed: true)
          ..['serviceType'] = 'DINE_IN'
          ..['tableSessionId'] = sessionId,
      );
    final container = await pumpOrder(
      tester,
      tables: tables,
      orders: orders,
      permissions: _permissions,
      child: const OrderDetailScreen(id: 'o1'),
    );
    final transfer = container.read(orderTableTransferProvider(sessionId));
    expect(transfer.sessionFailure, isNull);
    expect(transfer.currentSession?.id, sessionId);
    await tester.tap(find.byTooltip('Thao tác khác'));
    await tester.pumpAndSettle();
    expect(find.text('Chuyển bàn'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final takeaway = FakeOrders();
    await pumpOrder(
      tester,
      tables: TableServer(),
      orders: takeaway,
      permissions: _permissions,
      child: const OrderDetailScreen(id: 'o1'),
    );
    expect(find.text('Chuyển bàn'), findsNothing);
  });

  testWidgets('transfer keeps order and updates table context from response', (
    tester,
  ) async {
    final tables = TableServer()
      ..session = sessionJson(id: sessionId)
      ..table = tableJson(id: 't2', code: 'B02', name: 'Garden table');
    tables.respond = (request) async {
      if (request.path.endsWith('/transfer')) {
        return Response(
          requestOptions: request,
          statusCode: 200,
          data: sessionJson(
            id: sessionId,
            version: 4,
            tableId: 't2',
            tableCode: 'B02',
            tableName: 'Garden table',
          ),
        );
      }
      return tables.response(request);
    };
    final orders = FakeOrders()
      ..current = OrderDto.detail(
        orderJson(status: 'CONFIRMED', confirmed: true)
          ..['serviceType'] = 'DINE_IN'
          ..['tableSessionId'] = sessionId,
      );
    final container = await pumpOrder(
      tester,
      tables: tables,
      orders: orders,
      permissions: _permissions,
      child: const OrderDetailScreen(id: 'o1', tableName: 'Old route hint'),
    );
    expect(
      container
          .read(orderTableTransferProvider(sessionId))
          .currentSession
          ?.tableName,
      'Window table',
    );
    expect(find.text('Window table'), findsOneWidget);
    await tester.tap(find.byTooltip('Thao tác khác'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chuyển bàn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B02 • Garden table'));
    await tester.pump();
    expect(
      container.read(tableTransferControllerProvider(sessionId)).selected?.id,
      't2',
    );
    expect(
      container.read(tableTransferControllerProvider(sessionId)).canSubmit,
      true,
    );
    await tester.ensureVisible(find.text('Xác nhận chuyển bàn'));
    final confirm = find.widgetWithText(FilledButton, 'Xác nhận chuyển bàn');
    final button = tester.widget<FilledButton>(confirm);
    expect(button.onPressed, isNotNull);
    button.onPressed!();
    await tester.pumpAndSettle();

    final transferController = container.read(
      tableTransferControllerProvider(sessionId),
    );
    expect(transferController.failure, isNull);
    expect(transferController.currentSession?.tableName, 'Garden table');
    expect(find.text('Garden table'), findsWidgets);
    expect(find.byTooltip('Gọi thêm món'), findsOneWidget);
    expect(orders.current.id, 'o1');
    expect(orders.current.summary.tableSessionId, sessionId);
    expect(orders.writes, isEmpty);
    expect(orders.creates, isEmpty);
    final transfer = tables.requests.singleWhere(
      (request) => request.path.endsWith('/transfer'),
    );
    expect(transfer.data['expectedVersion'], 3);
    expect(transfer.data['targetTableId'], 't2');
  });
}
