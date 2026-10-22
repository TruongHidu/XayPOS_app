import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/stock_audit_create_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/stock_audit_detail_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/stock_audit_list.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/stock_audit_exit_guard.dart';
import '../../helpers/auth_fakes.dart';
import 'inventory_fakes.dart';
import 'stock_audit_fakes.dart';
import 'stock_fakes.dart';

Future<AuthController> _auth({
  Set<String> permissions = stockAuditPermissions,
  Set<String> features = stockAuditFeatures,
  SessionEvents? events,
}) async {
  final controller = makeController(
    sessionEvents: events,
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: features)),
  );
  await controller.login(
    const LoginCredentials(email: 'audit@example.com', password: 'password'),
  );
  return controller;
}

Future<({ProviderContainer container, GoRouter router})> pumpAudits(
  WidgetTester tester, {
  FakeStockAudits? repo,
  AuthController? auth,
  double width = 1200,
  double scale = 1,
  String location = '/app/inventory/audits/a1',
  bool keyboard = false,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  if (keyboard) tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.resetViewInsets);
  auth ??= await _auth();
  final routerProvider = Provider((ref) {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/app/inventory',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: StockAuditList(),
            ),
          ),
        ),
        GoRoute(
          path: '/app/inventory/audits/new',
          onExit: (context, _) => confirmStockAuditExit(context, ref, null),
          builder: (_, _) => const Scaffold(body: StockAuditCreateScreen()),
        ),
        GoRoute(
          path: '/app/inventory/audits/:id',
          onExit: (context, state) =>
              confirmStockAuditExit(context, ref, state.pathParameters['id']),
          builder: (_, state) => Scaffold(
            body: StockAuditDetailScreen(id: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/app/inventory/stock-documents/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Document ${state.pathParameters['id']}')),
        ),
      ],
    );
    ref.onDispose(router.dispose);
    return router;
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth!),
        stockAuditRepositoryProvider.overrideWithValue(
          repo ?? FakeStockAudits(),
        ),
        warehouseRepositoryProvider.overrideWithValue(FakeWarehouses()),
        stockKeyGeneratorProvider.overrideWithValue(FakeStockKeys()),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: ref.watch(routerProvider),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  );
  return (container: container, router: container.read(routerProvider));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _count(String id, {int epoch = 0}) =>
    find.byKey(ValueKey(('audit-count', id, epoch)));
String _text(WidgetTester tester, Finder field) => tester
    .widget<TextField>(
      find.descendant(of: field, matching: find.byType(TextField)),
    )
    .controller!
    .text;

void main() {
  testWidgets('refresh renders server changes in untouched text fields', (
    tester,
  ) async {
    final repo = FakeStockAudits();
    final host = await pumpAudits(tester, repo: repo, width: 600);
    repo.rows[0] = stockAuditItemJson(counted: 9, note: 'Ghi chú mới');
    repo.value = {...repo.value, 'version': 3};
    await host.container.read(stockAuditDetailProvider('a1')).load();
    await tester.pumpAndSettle();
    expect(_text(tester, _count('ai1', epoch: 1)), '9');
    final note = find.byKey(const ValueKey(('audit-count-note', 'ai1', 1)));
    expect(_text(tester, note), 'Ghi chú mới');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'DRAFT start requires confirmation then loads paged count sheet',
    (tester) async {
      final repo = FakeStockAudits()
        ..value = stockAuditJson(status: 'DRAFT', version: 0);
      await pumpAudits(tester, repo: repo);
      expect(repo.itemQueries, isEmpty);
      expect(find.text('Bảng số đếm'), findsNothing);
      await _tap(tester, find.text('Bắt đầu kiểm kê'));
      expect(repo.starts, 0);
      expect(find.textContaining('Kho vẫn có thể phát sinh'), findsOneWidget);
      await _tap(tester, find.text('Bắt đầu kiểm kê').last);
      expect(repo.starts, 1);
      expect(repo.itemQueries, hasLength(1));
      expect(find.text('Bảng số đếm'), findsOneWidget);
      expect(_text(tester, _count('ai2')), '');
    },
  );

  testWidgets(
    'count zero saves and visible fields keep accepted values after refresh',
    (tester) async {
      final repo = FakeStockAudits();
      final host = await pumpAudits(tester, repo: repo, width: 600);
      await tester.ensureVisible(_count('ai2'));
      await tester.enterText(_count('ai2'), '0');
      await tester.pumpAndSettle();
      expect(find.textContaining('1 dòng chưa lưu'), findsWidgets);
      await _tap(tester, find.text('Lưu bản nhập'));
      expect(repo.savedBatches.single.items.single.auditItemId, 'ai2');
      expect(repo.savedBatches.single.items.single.countedQuantity.scaled, 0);
      expect(_text(tester, _count('ai2', epoch: 1)), '0');
      expect(host.container.read(stockAuditDetailProvider('a1')).dirty, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'raw count survives server pagination, exit with retention and token refresh',
    (tester) async {
      final repo = FakeStockAudits()
        ..rows = [
          for (var i = 0; i < 23; i++)
            stockAuditItemJson(id: 'ai$i', ingredient: 'i$i', counted: null),
        ];
      repo.value = stockAuditJson(itemCount: 23, counted: 0, changed: 0);
      final events = SessionEvents(), auth = await _auth(events: events);
      final host = await pumpAudits(tester, repo: repo, auth: auth, width: 600),
          c = host.container.read(stockAuditDetailProvider('a1'));
      await tester.ensureVisible(_count('ai0'));
      await tester.enterText(_count('ai0'), '0,001');
      await tester.pumpAndSettle();
      c.page(1);
      await tester.pumpAndSettle();
      c.page(0);
      await tester.pumpAndSettle();
      expect(_text(tester, _count('ai0')), '0,001');
      events.refreshed(
        makeAuthSession(
          permissions: stockAuditPermissions,
          tokens: makeTokens(accessToken: 'refreshed'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        identical(host.container.read(stockAuditDetailProvider('a1')), c),
        true,
      );
      expect(c.draft('ai0')!.rawQuantity, '0,001');
      host.router.go('/app/inventory?tab=audits');
      await tester.pumpAndSettle();
      expect(find.text('Còn bản nhập chưa lưu'), findsOneWidget);
      await _tap(tester, find.text('Rời và giữ bản nhập'));
      host.router.go('/app/inventory/audits/a1');
      await tester.pumpAndSettle();
      expect(_text(tester, _count('ai0')), '0,001');
      expect(
        identical(host.container.read(stockAuditDetailProvider('a1')), c),
        true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmation-only reader can confirm whole audit without manage or adjustment',
    (tester) async {
      final repo = FakeStockAudits()..value = stockAuditJson(counted: 2),
          auth = await _auth(
            permissions: {'INVENTORY_VIEW', 'STOCK_AUDIT_CONFIRM'},
          );
      await pumpAudits(tester, repo: repo, auth: auth);
      expect(find.text('Sửa ghi chú'), findsNothing);
      expect(_count('ai1'), findsNothing);
      await _tap(tester, find.text('Chốt kiểm kê'));
      expect(repo.confirms, 0);
      expect(find.textContaining('Thao tác có thể điều chỉnh'), findsOneWidget);
      await _tap(tester, find.text('Chốt kiểm kê').last);
      expect(repo.confirms, 1);
      expect(find.textContaining('Xem chứng từ điều chỉnh'), findsOneWidget);
      await _tap(tester, find.textContaining('Xem chứng từ điều chỉnh'));
      expect(find.text('Document adjustment-a1'), findsOneWidget);
    },
  );

  testWidgets(
    'all-counts header blocks confirm despite current page being complete',
    (tester) async {
      final repo = FakeStockAudits();
      final host = await pumpAudits(tester, repo: repo);
      expect(
        host.container.read(stockAuditDetailProvider('a1')).canPost,
        false,
      );
      expect(
        tester
            .widget<FilledButton>(
              find
                  .ancestor(
                    of: find.text('Chốt kiểm kê'),
                    matching: find.byWidgetPredicate(
                      (widget) => widget is FilledButton,
                    ),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('Còn dòng chưa đếm trên toàn phiên'),
        findsOneWidget,
      );
    },
  );

  for (final status in ['CONFIRMED', 'CANCELLED']) {
    testWidgets('$status sheet remains readable without mutation controls', (
      tester,
    ) async {
      final repo = FakeStockAudits()
        ..value = stockAuditJson(status: status, counted: 2, changed: 0);
      await pumpAudits(tester, repo: repo);
      expect(repo.itemQueries, hasLength(1));
      expect(find.text('Bảng số đếm'), findsOneWidget);
      expect(_count('ai1'), findsNothing);
      expect(find.text('Hủy phiên'), findsNothing);
      expect(find.text('Lưu số đếm'), findsNothing);
      if (status == 'CONFIRMED') {
        expect(
          find.text('Số đếm khớp hệ thống, không phát sinh điều chỉnh.'),
          findsOneWidget,
        );
      }
      expect(find.textContaining('Xem chứng từ điều chỉnh'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing audit feature does not mount provider or fetch data', (
    tester,
  ) async {
    final repo = FakeStockAudits();
    await pumpAudits(
      tester,
      repo: repo,
      auth: await _auth(features: {'INVENTORY_MANAGEMENT'}),
    );
    expect(repo.details, 0);
    expect(repo.itemQueries, isEmpty);
    expect(find.textContaining('chưa có quyền hoặc tính năng'), findsOneWidget);
  });

  testWidgets('header note survives a version conflict and dialog reopen', (
    tester,
  ) async {
    final repo = FakeStockAudits();
    final host = await pumpAudits(tester, repo: repo);
    await _tap(tester, find.text('Sửa ghi chú'));
    final field = find.widgetWithText(TextField, 'Ghi chú (để trống để xóa)');
    await tester.enterText(field, 'Ghi chú chưa lưu');
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Đóng'));
    expect(
      host.container.read(stockAuditDetailProvider('a1')).headerNoteDraft,
      'Ghi chú chưa lưu',
    );
    await _tap(tester, find.text('Sửa ghi chú'));
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Ghi chú (để trống để xóa)'),
          )
          .controller!
          .text,
      'Ghi chú chưa lưu',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'uncertain create retained across explicit exit and reuses original key/body',
    (tester) async {
      final repo = FakeStockAudits()
        ..onCreate = (_, _) async => const Error(networkFailure);
      final host = await pumpAudits(
        tester,
        repo: repo,
        location: '/app/inventory/audits/new',
      );
      host.container
          .read(stockAuditCreateProvider)
          .selectWarehouse(warehouse());
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Tạo phiên nháp'));
      expect(repo.sentKeys, hasLength(1));
      host.router.go('/app/inventory?tab=audits');
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Rời và giữ bản nhập'));
      host.router.go('/app/inventory/audits/new');
      await tester.pumpAndSettle();
      repo.onCreate = null;
      await _tap(tester, find.text('Thử lại yêu cầu ban đầu'));
      expect(repo.sentKeys[0], repo.sentKeys[1]);
      expect(find.text('AUD-20261021-created-audit'), findsOneWidget);
    },
  );

  testWidgets('DRAFT header note can be saved before leaving the audit', (
    tester,
  ) async {
    final repo = FakeStockAudits()
      ..value = stockAuditJson(status: 'DRAFT', version: 0);
    final host = await pumpAudits(tester, repo: repo);
    await _tap(tester, find.text('Sửa ghi chú'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Ghi chú (để trống để xóa)'),
      'Kiểm kê cuối ca hôm nay',
    );
    await _tap(tester, find.byTooltip('Đóng'));
    expect(host.container.read(stockAuditDetailProvider('a1')).dirty, true);
    host.router.go('/app/inventory?tab=audits');
    await tester.pumpAndSettle();
    expect(find.text('Còn bản nhập chưa lưu'), findsOneWidget);
    await _tap(tester, find.text('Lưu và rời'));
    expect(repo.notes, 1);
    expect(repo.value['note'], 'Kiểm kê cuối ca hôm nay');
    expect(repo.value['status'], 'DRAFT');
    expect(repo.starts, 0);
    expect(repo.savedBatches, isEmpty);
    expect(find.byType(StockAuditList), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'feature/identity loss closes audit dialog and excludes late header',
    (tester) async {
      final repo = FakeStockAudits(),
          events = SessionEvents(),
          auth = await _auth(events: events);
      final host = await pumpAudits(tester, repo: repo, auth: auth);
      await _tap(tester, find.text('Sửa ghi chú'));
      events.refreshed(makeAuthSession(permissions: {'INVENTORY_VIEW'}));
      await tester.pumpAndSettle();
      expect(find.text('Sửa ghi chú kiểm kê'), findsNothing);
      expect(
        host.container.read(stockAuditDetailProvider('a1')).canManage,
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 600.0, 800.0, 1200.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'audit count UI fits $width scale $scale with long snapshot names and keyboard',
        (tester) async {
          final repo = FakeStockAudits()
            ..rows = [
              stockAuditItemJson(
                name:
                    'Nguyên liệu có tên rất dài để kiểm tra khả năng xuống dòng và hiển thị đầy đủ thông tin trong bảng kiểm kê kho của nhà hàng',
                counted: 8,
              ),
            ];
          repo.value = stockAuditJson(itemCount: 1, counted: 1, changed: 1);
          final host = await pumpAudits(
            tester,
            repo: repo,
            width: width,
            scale: scale,
            keyboard: true,
          );
          await tester.ensureVisible(_count('ai1'));
          await tester.enterText(_count('ai1'), '0,001');
          await tester.pumpAndSettle();
          expect(
            host.container
                .read(stockAuditDetailProvider('a1'))
                .draft('ai1')!
                .rawQuantity,
            '0,001',
          );
          expect(find.text('Lưu bản nhập'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
