import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/tables/data/dto/table_dto.dart';
import 'package:pos_saas_app/features/tables/presentation/screens/tables_management_screen.dart';
import 'package:pos_saas_app/features/tables/presentation/widgets/restaurant_table_form.dart';
import 'package:pos_saas_app/features/tables/presentation/widgets/table_details.dart';
import 'package:pos_saas_app/features/tables/presentation/widgets/table_dialogs.dart';
import 'package:pos_saas_app/features/tables/presentation/widgets/table_session_form.dart';
import 'package:pos_saas_app/features/tables/presentation/widgets/table_transfer_dialog.dart';
import '../../helpers/auth_fakes.dart';
import 'table_fakes.dart';

Future<ProviderContainer> pumpTables(
  WidgetTester tester,
  TableServer s, {
  Widget child = const TablesManagementScreen(),
  Set<String> permissions = tablePermissions,
  SessionEvents? events,
}) async {
  final auth = makeController(
    sessionEvents: events,
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: {'TABLE_MANAGEMENT'})),
  );
  await auth.login(
    const LoginCredentials(email: 'a@b.com', password: 'password'),
  );
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      restaurantTableRepositoryProvider.overrideWithValue(s.tables),
      tableAreaRepositoryProvider.overrideWithValue(s.areas),
      tableSessionRepositoryProvider.overrideWithValue(s.sessions),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(s.close);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final width in [320.0, 800.0]) {
    testWidgets('transfer picker is responsive at $width with keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 760);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final server = TableServer()
        ..table = tableJson(id: 't2', code: 'B02', name: 'Garden table');
      await pumpTables(
        tester,
        server,
        child: const TableTransferDialog(sessionId: 's1'),
      );
      expect(find.textContaining('Bàn hiện tại: B01'), findsOneWidget);
      expect(find.text('B02 • Garden table'), findsOneWidget);
      await tester.ensureVisible(find.text('Xác nhận chuyển bàn'));
      expect(tester.takeException(), isNull);
      expect(
        server.requests.where((r) => r.path.endsWith('/current-session')),
        isEmpty,
      );
    });
  }

  for (final width in [320.0, 800.0, 1440.0]) {
    testWidgets('responsive tables at $width and independent occupied badge', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = TableServer()..table = tableJson(occupied: true);
      await pumpTables(tester, s);
      expect(find.text('Có khách • 6 người'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        s.requests.where((r) => r.path.endsWith('current-session')),
        isEmpty,
      );
    });
  }
  testWidgets(
    'small keyboard form scrolls, validates, occupied fields locked',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final s = TableServer();
      await pumpTables(
        tester,
        s,
        child: RestaurantTableForm(
          initial: TableDto.restaurantTable(tableJson(occupied: true)),
        ),
      );
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields[0].enabled, false);
      expect(fields[1].enabled, true);
      expect(fields[2].enabled, false);
      expect(fields[3].enabled, true);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextFormField).at(1), '');
      await tester.ensureVisible(find.text('Lưu thay đổi'));
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(find.text('Không được để trống.'), findsOneWidget);
      expect(s.requests.where((r) => r.method == 'PATCH'), isEmpty);
    },
  );
  testWidgets(
    'background refresh and 409 preserve draft and original version',
    (tester) async {
      final s = TableServer();
      final container = await pumpTables(
        tester,
        s,
        child: RestaurantTableForm(
          initial: TableDto.restaurantTable(tableJson()),
        ),
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'My draft');
      s.table = tableJson(version: 12);
      await tester.runAsync(
        () => container.read(restaurantTableControllerProvider).load(),
      );
      await tester.pumpAndSettle();
      expect(find.text('My draft'), findsOneWidget);
      s.respond = (r) async {
        if (r.method == 'PATCH') {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: r,
              statusCode: 409,
              data: {'code': 'CONCURRENT_TABLE_UPDATE'},
            ),
          );
        }
        return s.response(r);
      };
      await tester.ensureVisible(find.text('Lưu thay đổi'));
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(
        s.requests
            .where((r) => r.method == 'PATCH')
            .single
            .data['expectedVersion'],
        9,
      );
      expect(find.text('My draft'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Tải lại dữ liệu'));
      await tester.tap(find.text('Tải lại dữ liệu'));
      await tester.pumpAndSettle();
      expect(find.text('Thay thế bản đang sửa?'), findsOneWidget);
    },
  );
  testWidgets('terminal sessions are read only', (tester) async {
    final s = TableServer();
    await pumpTables(
      tester,
      s,
      permissions: {'TABLE_VIEW'},
      child: TableSessionCard(
        session: TableDto.tableSession(sessionJson(status: 'CANCELLED')),
      ),
    );
    expect(find.text('Sửa phiên'), findsNothing);
    expect(find.text('Hủy mở nhầm'), findsNothing);
  });
  testWidgets('open session without order exposes transfer and history', (
    tester,
  ) async {
    final server = TableServer();
    await pumpTables(
      tester,
      server,
      child: TableSessionCard(session: TableDto.tableSession(sessionJson())),
    );
    expect(find.text('Chuyển bàn'), findsOneWidget);
    expect(find.text('Lịch sử chuyển bàn'), findsOneWidget);
    expect(server.requests.where((r) => r.path.contains('/orders')), isEmpty);
  });
  testWidgets('cancel form requires a reason before any request', (
    tester,
  ) async {
    final s = TableServer();
    await pumpTables(
      tester,
      s,
      child: TableSessionForm(
        session: TableDto.tableSession(sessionJson()),
        cancel: true,
      ),
    );
    await tester.ensureVisible(find.text('Xác nhận hủy phiên'));
    await tester.tap(find.text('Xác nhận hủy phiên'));
    await tester.pumpAndSettle();
    expect(find.text('Không được để trống.'), findsOneWidget);
    expect(s.requests.where((r) => r.method == 'POST'), isEmpty);
  });
  testWidgets('empty, failure and retry', (tester) async {
    final s = TableServer()..empty = true;
    await pumpTables(tester, s);
    expect(
      find.text('Chưa có bàn. Thêm bàn để bắt đầu phục vụ.'),
      findsOneWidget,
    );
    s.respond = (r) async => throw DioException(
      requestOptions: r,
      type: DioExceptionType.connectionError,
    );
    await tester.tap(find.byTooltip('Bộ lọc').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tải lại'));
    await tester.pumpAndSettle();
    expect(
      find.text('Không thể kết nối đến máy chủ. Vui lòng thử lại.'),
      findsWidgets,
    );
    s.respond = null;
    await tester.tap(find.text('Tải lại dữ liệu'));
    await tester.pumpAndSettle();
    expect(find.byType(TableFailurePanel), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('QR rotates only after confirmation and shows returned version', (
    tester,
  ) async {
    final s = TableServer();
    await pumpTables(tester, s, child: const TableQrDialog(id: 't1'));
    expect(find.text('Phiên bản mã QR: 9'), findsOneWidget);
    await tester.tap(find.text('Đổi mã QR'));
    await tester.pumpAndSettle();
    expect(find.text('Đổi mã QR?'), findsOneWidget);
    expect(s.requests.where((r) => r.method == 'POST'), isEmpty);
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(s.requests.where((r) => r.path.endsWith('/qr/rotate')).single.data, {
      'expectedVersion': 9,
    });
    expect(find.text('Phiên bản mã QR: 10'), findsOneWidget);
  });
  testWidgets(
    'timed-out create keeps draft and requires checking server before retry',
    (tester) async {
      final s = TableServer();
      await pumpTables(tester, s, child: const RestaurantTableForm());
      await tester.enterText(find.byType(TextFormField).at(0), 'B01');
      await tester.enterText(find.byType(TextFormField).at(1), 'Draft table');
      s.respond = (r) async {
        if (r.method == 'POST') {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return s.response(r);
      };
      await tester.ensureVisible(find.text('Lưu thay đổi'));
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(find.text('Draft table'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Tải lại dữ liệu'));
      await tester.tap(find.text('Tải lại dữ liệu'));
      await tester.pumpAndSettle();
      expect(find.text('B01 - Window table'), findsOneWidget);
      expect(s.requests.where((r) => r.method == 'POST').length, 1);
      await tester.ensureVisible(find.text('Đã kiểm tra, cho phép gửi lại'));
      await tester.tap(find.text('Đã kiểm tra, cho phép gửi lại'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNotNull,
      );
      expect(find.text('Draft table'), findsOneWidget);
      expect(s.requests.where((r) => r.method == 'POST').length, 1);
    },
  );
  testWidgets(
    'dialog draft survives token refresh and closes on tenant change',
    (tester) async {
      final events = SessionEvents();
      addTearDown(events.dispose);
      await pumpTables(
        tester,
        TableServer(),
        events: events,
        child: const _FormLauncher(),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(1), 'Draft');
      events.refreshed(
        makeAuthSession(
          permissions: tablePermissions,
          tokens: makeTokens(accessToken: 'new'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Draft'), findsOneWidget);
      events.refreshed(
        makeAuthSession(restaurantId: 'other', permissions: tablePermissions),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantTableForm), findsNothing);
      expect(find.text('Draft'), findsNothing);
    },
  );
}

class _FormLauncher extends ConsumerWidget {
  const _FormLauncher();
  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
    onPressed: () => showTableDialog(
      context,
      ref,
      permission: 'TABLE_UPDATE',
      child: RestaurantTableForm(
        initial: TableDto.restaurantTable(tableJson()),
      ),
    ),
    child: const Text('Open'),
  );
}
