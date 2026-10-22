import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_document_dto.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_document.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_management_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/stock_document_create_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/stock_document_detail_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_transaction_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/stock_document_forms.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/stock_widgets.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/inventory_widgets.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/inventory_threshold_dialog.dart';
import '../../helpers/auth_fakes.dart';
import 'inventory_fakes.dart';
import 'stock_fakes.dart';

Future<AuthController> _auth({
  Set<String> permissions = stockPermissions,
  SessionEvents? events,
}) async {
  final auth = makeController(
    sessionEvents: events,
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: {'INVENTORY_MANAGEMENT'})),
  );
  await auth.login(
    const LoginCredentials(email: 'stock@example.com', password: 'password'),
  );
  return auth;
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  FakeStockDocuments? docs,
  FakeStockTransactions? ledger,
  FakeWarehouses? wh,
  FakeBalances? balances,
  AuthController? auth,
  String location = '/app/inventory?tab=documents',
  Widget? dialog,
  double width = 1200,
  double scale = 1,
  bool keyboard = false,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  if (keyboard) tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.resetViewInsets);
  auth ??= await _auth();
  Widget page(Widget child) => Scaffold(body: child);
  final router = GoRouter(
    initialLocation: dialog == null ? location : '/dialog',
    routes: [
      GoRoute(
        path: '/app/inventory',
        builder: (context, state) => page(
          InventoryManagementScreen(
            initialTab: state.uri.queryParameters['tab'],
          ),
        ),
      ),
      GoRoute(
        path: '/app/inventory/stock-documents/new',
        builder: (context, state) => page(const StockDocumentCreateScreen()),
      ),
      GoRoute(
        path: '/app/inventory/stock-documents/:id',
        builder: (context, state) =>
            page(StockDocumentDetailScreen(id: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/app/inventory/transactions',
        builder: (context, state) =>
            page(InventoryTransactionRoute(query: state.uri.queryParameters)),
      ),
      GoRoute(
        path: '/dialog',
        builder: (context, state) => page(
          Consumer(
            builder: (context, ref, _) => Center(
              child: TextButton(
                onPressed: () =>
                    showInventoryDialog<void>(context, ref, child: dialog!),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth!),
        warehouseRepositoryProvider.overrideWithValue(wh ?? FakeWarehouses()),
        inventoryBalanceRepositoryProvider.overrideWithValue(
          balances ?? FakeBalances(),
        ),
        stockDocumentRepositoryProvider.overrideWithValue(
          docs ?? FakeStockDocuments(),
        ),
        inventoryTransactionRepositoryProvider.overrideWithValue(
          ledger ?? FakeStockTransactions(),
        ),
        stockKeyGeneratorProvider.overrideWithValue(FakeStockKeys()),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  if (dialog != null) {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
  return router;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key)));
Future<void> _see(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
  } else {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('inventory-only reader sees mixed sources without order reads', (
    tester,
  ) async {
    final ledger = FakeStockTransactions()
      ..rows = [
        StockDocumentDto.transaction(
          recipeUseJson()..['transactionId'] = 'recipe-use-1',
        ),
        StockDocumentDto.transaction(transactionJson()),
      ];
    await _pump(
      tester,
      ledger: ledger,
      auth: await _auth(permissions: {'INVENTORY_VIEW'}),
      location: '/app/inventory/transactions',
    );
    expect(find.text('Chưa định giá'), findsOneWidget);
    expect(find.text('Tiêu thụ theo món'), findsOneWidget);
    expect(find.text('Xem đơn'), findsNothing);
    expect(find.text('ISS-d1'), findsOneWidget);
    expect(ledger.queries, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('invalid ledger source link makes no unfiltered request', (
    tester,
  ) async {
    final ledger = FakeStockTransactions();
    await _pump(
      tester,
      ledger: ledger,
      location: '/app/inventory/transactions?sourceType=INVALID',
    );
    expect(
      find.textContaining('Bộ lọc giao dịch không hợp lệ'),
      findsOneWidget,
    );
    expect(ledger.queries, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'order stock change keeps threshold draft until explicit baseline reload',
    (tester) async {
      await _pump(
        tester,
        dialog: const InventoryThresholdDialog(
          warehouseId: 'w1',
          ingredientId: 'i1',
          edit: true,
        ),
      );
      final field = find.byType(TextField);
      await tester.enterText(field, '123.456');
      _container(tester).read(orderEventsProvider).emit('o1', null);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '123.456');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Lưu ngưỡng'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Tải lại để đối chiếu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'compact stock filters do not read the saved workspace scroll offset as a bool',
    (tester) async {
      final docs = FakeStockDocuments()
        ..onList = (q) async => Success(
          inventoryPage([
            for (var i = 0; i < 20; i++) stockDocument(id: 'd$i'),
          ]),
        );
      await _pump(tester, docs: docs);
      final workspace = find.byKey(const PageStorageKey('inventory-workspace'));
      await tester.drag(workspace, const Offset(0, -400));
      await tester.pumpAndSettle();
      final context = tester.element(workspace);
      final bucket = PageStorage.of(context);
      expect(bucket.readState(context), isA<double>());
      expect(bucket.readState(context) as double, greaterThan(0));

      tester.view.physicalSize = const Size(600, 1000);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('Lọc và sắp xếp'));
      expect(find.byType(StockSelect), findsNWidgets(5));
      expect(bucket.readState(context), isA<double>());

      tester.view.physicalSize = const Size(1200, 1000);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(600, 1000);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(StockSelect), findsNWidgets(5));
    },
  );

  testWidgets(
    'document and transaction tabs keep filter expansion separate from scrolling',
    (tester) async {
      await _pump(tester, width: 600);
      await _tap(tester, find.text('Lọc và sắp xếp'));
      expect(find.byType(StockSelect), findsNWidgets(5));

      await _tap(tester, find.widgetWithText(ChoiceChip, 'Biến động'));
      expect(tester.takeException(), isNull);
      expect(find.byType(StockSelect), findsNothing);
      await _tap(tester, find.text('Lọc và sắp xếp'));
      expect(find.byType(StockSelect), findsNWidgets(4));

      await _tap(tester, find.widgetWithText(ChoiceChip, 'Chứng từ'));
      expect(tester.takeException(), isNull);
      expect(find.byType(StockSelect), findsNWidgets(5));
    },
  );

  testWidgets(
    'logical balance opens history using warehouse and ingredient without a physical balance ID',
    (tester) async {
      final ledger = FakeStockTransactions();
      await _pump(
        tester,
        ledger: ledger,
        auth: await _auth(permissions: {'INVENTORY_VIEW'}),
        dialog: const InventoryThresholdDialog(
          warehouseId: 'w1',
          ingredientId: 'i2',
        ),
      );
      expect(find.text('Chưa cấu hình'), findsOneWidget);
      await _tap(tester, find.text('Xem biến động'));
      expect(ledger.queries.last.warehouseId, 'w1');
      expect(ledger.queries.last.ingredientId, 'i2');
      expect(find.byType(InventoryThresholdDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 600.0, 800.0, 1200.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'documents, detail and ledger fit $width px at system text $scale',
        (tester) async {
          final docs = FakeStockDocuments()
            ..value = stockDetailJson(
              warehouseName:
                  'Kho nguyên liệu có tên dài để kiểm tra khả năng xuống dòng trên thiết bị nhỏ',
              items: [
                stockItemJson(
                  name:
                      'Nguyên liệu có tên dài để kiểm tra bố cục khi phóng chữ hệ thống',
                  quantity: 99999999999.999,
                  cost: 0,
                  note:
                      'Ghi chú chi tiết dòng nguyên liệu được giữ nguyên để đối chiếu.',
                ),
              ],
            );
          final tx = FakeStockTransactions()
            ..rows = [
              StockDocumentDto.transaction(
                transactionJson(
                  name: 'Nguyên liệu có tên dài trong lịch sử biến động kho',
                ),
              ),
            ];
          final router = await _pump(
            tester,
            docs: docs,
            ledger: tx,
            width: width,
            scale: scale,
          );
          await _see(tester, find.text('RCV-20261018-d1'));
          expect(tester.takeException(), isNull);
          if (find.byType(ExpansionTile).evaluate().isNotEmpty) {
            await _tap(tester, find.text('Lọc và sắp xếp'));
            expect(find.byType(StockSelect), findsNWidgets(5));
            expect(tester.takeException(), isNull);
          }
          router.go('/app/inventory/stock-documents/d1');
          await tester.pumpAndSettle();
          await _see(
            tester,
            find.textContaining('Nguyên liệu có tên dài để kiểm tra bố cục'),
          );
          expect(tester.takeException(), isNull);
          router.go('/app/inventory/transactions?documentId=d1');
          await tester.pumpAndSettle();
          await _see(
            tester,
            find.textContaining('Nguyên liệu có tên dài trong lịch sử'),
          );
          expect(tester.takeException(), isNull);
          expect(tx.queries.last.documentId, 'd1');
        },
      );
    }
  }
  testWidgets(
    'inventory-only user creates logical ingredient draft, confirms and sees linked ledger',
    (tester) async {
      final docs = FakeStockDocuments(),
          tx = FakeStockTransactions(),
          balances = FakeBalances();
      await _pump(tester, docs: docs, ledger: tx, balances: balances);
      await _tap(tester, find.text('Tạo phiếu nhập kho'));
      await _tap(tester, find.text('Chọn kho'));
      await _tap(tester, find.byKey(const ValueKey('select-warehouse-w1')));
      await _tap(tester, find.text('Thêm nguyên liệu'));
      expect(balances.queries.last.q.ingredientActive, true);
      expect(balances.lowCalls, 0);
      await _tap(tester, find.byKey(const ValueKey('stock-pick-i2')));
      await tester.enterText(
        find.byKey(const ValueKey('stock-line-quantity')),
        '1.5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('stock-line-cost')),
        '100',
      );
      await _tap(tester, find.text('Lưu dòng'));
      await _tap(tester, find.text('Lưu nháp'));
      expect(docs.sentInputs.single.items.single.ingredientId, 'i2');
      expect(docs.confirms, 0);
      expect(find.text('Nháp'), findsWidgets);
      await _tap(tester, find.text('Xác nhận chứng từ'));
      expect(docs.confirms, 0);
      await _tap(tester, find.text('Xác nhận ghi nhận tồn'));
      expect(docs.confirms, 1);
      expect(find.text('Đã xác nhận'), findsOneWidget);
      expect(find.text('Sửa ghi chú'), findsNothing);
      tx.rows = [
        StockDocumentDto.transaction(
          transactionJson(
            document: 'created-1',
            ingredient: 'i2',
            type: 'RECEIPT',
            change: 1.5,
            before: 0,
            after: 1.5,
          ),
        ),
      ];
      await _tap(tester, find.text('Xem biến động'));
      expect(tx.queries.last.documentId, 'created-1');
      expect(tx.queries.last.warehouseId, 'w1');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'view-only history and documents never require menu or mutation permissions',
    (tester) async {
      final auth = await _auth(permissions: {'INVENTORY_VIEW'}),
          balances = FakeBalances();
      final router = await _pump(tester, auth: auth, balances: balances);
      expect(find.textContaining('Tạo phiếu'), findsNothing);
      expect(find.text('Cảnh báo tồn thấp'), findsNothing);
      router.go('/app/inventory/stock-documents/d1');
      await tester.pumpAndSettle();
      expect(find.text('Sửa ghi chú'), findsNothing);
      expect(find.text('Thêm nguyên liệu'), findsNothing);
      expect(find.text('Xác nhận chứng từ'), findsNothing);
      router.go('/app/inventory/transactions?warehouseId=w1');
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Chọn nguyên liệu'));
      expect(find.byKey(const ValueKey('stock-pick-i3')), findsOneWidget);
      expect(balances.queries.last.q.ingredientActive, isNull);
      expect(balances.lowCalls, 0);
    },
  );
  testWidgets(
    'issue-only create initializes to authorized type and permits inactive picker',
    (tester) async {
      final balances = FakeBalances();
      await _pump(
        tester,
        auth: await _auth(permissions: {'INVENTORY_VIEW', 'INVENTORY_ISSUE'}),
        balances: balances,
        location: '/app/inventory/stock-documents/new',
      );
      expect(
        tester.widget<StockSelect>(find.byType(StockSelect).first).value,
        'ISSUE',
      );
      await _tap(tester, find.text('Chọn kho'));
      await _tap(tester, find.byKey(const ValueKey('select-warehouse-w1')));
      await _tap(tester, find.text('Thêm nguyên liệu'));
      expect(balances.queries.last.q.ingredientActive, isNull);
      await _tap(tester, find.byKey(const ValueKey('stock-pick-i3')));
      expect(find.byType(StockLineEditor), findsOneWidget);
    },
  );
  testWidgets(
    'note conflict preserves draft until explicit reload confirmation',
    (tester) async {
      final docs = FakeStockDocuments()
        ..onUpdate = (id, input) async => const Error(
          Failure(
            type: FailureType.conflict,
            code: 'CONCURRENT_STOCK_DOCUMENT_UPDATE',
            message: 'Phiếu đã đổi',
          ),
        );
      await _pump(
        tester,
        docs: docs,
        location: '/app/inventory/stock-documents/d1',
      );
      await _tap(tester, find.text('Sửa ghi chú'));
      await tester.enterText(
        find.byKey(const ValueKey('stock-document-note')),
        'Bản nháp đang nhập',
      );
      await _tap(tester, find.text('Lưu ghi chú'));
      expect(
        _field(tester, 'stock-document-note').controller!.text,
        'Bản nháp đang nhập',
      );
      await _tap(tester, find.text('Tải lại để đối chiếu').last);
      await _tap(tester, find.text('Giữ bản nháp'));
      expect(
        _field(tester, 'stock-document-note').controller!.text,
        'Bản nháp đang nhập',
      );
      docs.value = stockDetailJson(version: 9, note: 'Server mới');
      await _tap(tester, find.text('Tải lại để đối chiếu').last);
      await _tap(tester, find.text('Tải dữ liệu mới'));
      expect(
        _field(tester, 'stock-document-note').controller!.text,
        'Server mới',
      );
      docs.onUpdate = null;
      await tester.enterText(
        find.byKey(const ValueKey('stock-document-note')),
        'Đã đối chiếu',
      );
      await _tap(tester, find.text('Lưu ghi chú'));
      expect(docs.lastVersion, 9);
      expect(find.byType(StockNoteEditor), findsNothing);
    },
  );
  testWidgets(
    'line validation preserves values and allows correction without dropping unitCost/note',
    (tester) async {
      final docs = FakeStockDocuments()
        ..onAdd = (id, input) async => const Error(
          Failure(
            type: FailureType.validation,
            code: 'VALIDATION_ERROR',
            message: 'Lỗi số lượng',
            fieldErrors: {'quantity': 'Kiểm tra số lượng'},
          ),
        );
      await _pump(
        tester,
        docs: docs,
        location: '/app/inventory/stock-documents/d1',
      );
      await _tap(tester, find.text('Thêm nguyên liệu'));
      await _tap(tester, find.byKey(const ValueKey('stock-pick-i2')));
      await tester.enterText(
        find.byKey(const ValueKey('stock-line-quantity')),
        '4.5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('stock-line-cost')),
        '100',
      );
      await tester.enterText(
        find.byKey(const ValueKey('stock-line-note')),
        'Giữ ghi chú',
      );
      await _tap(tester, find.text('Lưu dòng'));
      expect(
        _field(tester, 'stock-line-quantity').decoration!.errorText,
        'Kiểm tra số lượng',
      );
      expect(_field(tester, 'stock-line-cost').controller!.text, '100');
      docs.onAdd = null;
      await tester.enterText(
        find.byKey(const ValueKey('stock-line-quantity')),
        '5',
      );
      await _tap(tester, find.text('Lưu dòng'));
      expect(docs.lastLine!.line.unitCost.toString(), '100');
      expect(docs.lastLine!.line.note, 'Giữ ghi chú');
      expect(docs.lastVersion, 3);
    },
  );
  testWidgets(
    'uncertain create survives navigation and token refresh and replays frozen key',
    (tester) async {
      final events = SessionEvents(),
          auth = await _auth(events: events),
          docs = FakeStockDocuments()
            ..onCreate = (key, input) async => const Error(networkFailure);
      final router = await _pump(
        tester,
        docs: docs,
        auth: auth,
        location: '/app/inventory/stock-documents/new',
      );
      final c = _container(tester).read(stockDocumentCreateProvider);
      c.selectWarehouse(warehouse());
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Lưu nháp'));
      expect(c.uncertain, true);
      final key = c.intent!.key;
      events.refreshed(
        makeAuthSession(
          permissions: stockPermissions,
          tokens: makeTokens(accessToken: 'rotated'),
        ),
      );
      await tester.pumpAndSettle();
      expect(_container(tester).read(stockDocumentCreateProvider), same(c));
      router.go('/app/inventory?tab=documents');
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Khôi phục yêu cầu chưa xác minh'));
      docs.onCreate = (key, input) async => Success(
        stockDocument(id: 'already', status: 'CONFIRMED', version: 8),
      );
      await _tap(tester, find.text('Thử lại yêu cầu ban đầu'));
      expect(docs.sentKeys, [key, key]);
      expect(c.result!.status, StockDocumentStatus.confirmed);
      await tester.pumpWidget(const SizedBox.shrink());
      events.dispose();
    },
  );
  testWidgets(
    'logout during creation discards delayed response and old tenant form',
    (tester) async {
      final auth = await _auth(),
          docs = FakeStockDocuments(),
          pending = Completer<Result<StockDocumentDetail>>();
      docs.onCreate = (key, input) => pending.future;
      await _pump(
        tester,
        auth: auth,
        docs: docs,
        location: '/app/inventory/stock-documents/new',
      );
      final c = _container(tester).read(stockDocumentCreateProvider);
      c.selectWarehouse(warehouse());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu nháp'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await auth.logout();
      await tester.pumpAndSettle();
      pending.complete(Success(stockDocument()));
      await tester.pumpAndSettle();
      expect(c.result, isNull);
      expect(find.text('Lưu nháp'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final kind in ['line', 'note']) {
    testWidgets('$kind dialog scrolls with 320px, 200% font and keyboard', (
      tester,
    ) async {
      final d = stockDocument();
      final Widget dialog = kind == 'line'
          ? StockLineEditor(
              type: d.type,
              ingredientId: 'i1',
              name: 'Nguyên liệu với tên rất dài khi phóng chữ',
              unit: 'g',
              baseline: d,
              itemId: 'si1',
              initial: stockLine(),
            )
          : StockNoteEditor(baseline: d);
      await _pump(tester, dialog: dialog, width: 320, scale: 2, keyboard: true);
      expect(tester.takeException(), isNull);
      final action = find.text(kind == 'line' ? 'Lưu dòng' : 'Lưu ghi chú');
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(tester.getRect(action).bottom, lessThan(700));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'creation at 320px/200% displays long selected warehouse and draft lines without overflow',
    (tester) async {
      await _pump(
        tester,
        location: '/app/inventory/stock-documents/new',
        width: 320,
        scale: 2,
      );
      final c = _container(tester).read(stockDocumentCreateProvider);
      c.selectWarehouse(
        warehouse(
          name: 'Kho nguyên liệu có tên dài ở khu vực phía sau nhà hàng',
        ),
      );
      c.put(
        balance(name: 'Tên nguyên liệu dài trong phiếu chưa lưu'),
        stockLine(),
      );
      await tester.pumpAndSettle();
      await _see(tester, find.text('Tên nguyên liệu dài trong phiếu chưa lưu'));
      expect(tester.takeException(), isNull);
    },
  );
}
