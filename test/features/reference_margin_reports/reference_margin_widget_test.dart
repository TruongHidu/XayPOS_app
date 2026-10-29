import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart' show authControllerProvider;
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/entities/reference_margin_enums.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/entities/reference_margin_report.dart';
import 'package:pos_saas_app/features/reference_margin_reports/presentation/providers/reference_margin_providers.dart';
import 'package:pos_saas_app/features/reference_margin_reports/presentation/screens/reference_margin_reports_screen.dart';
import 'package:pos_saas_app/features/reference_margin_reports/presentation/widgets/reference_margin_format.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_meta.dart';
import '../../helpers/auth_fakes.dart';
import 'margin_fakes.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeReferenceMarginRepository repository, {
  double width = 800,
  double scale = 1,
  bool keyboard = false,
  bool allowed = true,
  FakeEntitlementRepository? entitlements,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = makeAuthSession(
    permissions: {'REPORT_DETAIL_VIEW', if (allowed) 'ORDER_VIEW'},
  );
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(session)
      ..restoreResult = Success(session),
    entitlementRepository:
        entitlements ??
        (FakeEntitlementRepository()
          ..result = Success(
            makeEntitlement(features: {'ORDER_MANAGEMENT', 'DETAIL_REPORT'}),
          )),
  );
  await auth.login(
    const LoginCredentials(email: 'margin@example.com', password: 'password'),
  );
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((_) => auth),
      referenceMarginRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorObservers: [
          container.read(referenceMarginRouteObserverProvider),
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: keyboard
                ? const EdgeInsets.only(bottom: 280)
                : EdgeInsets.zero,
          ),
          child: child!,
        ),
        home: const Scaffold(body: ReferenceMarginReportsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('timestamp uses restaurant aliases, DST and explicit UTC fallback', () {
    expect(
      marginTimestamp(
        DateTime.parse('2026-10-28T12:00:00Z'),
        'Asia/Ho_Chi_Minh',
      ),
      '28/10/2026 19:00 · Asia/Ho_Chi_Minh',
    );
    expect(
      marginTimestamp(
        DateTime.parse('2026-07-01T12:00:00Z'),
        'America/New_York',
      ),
      '01/07/2026 08:00 · America/New_York',
    );
    expect(
      marginTimestamp(
        DateTime.parse('2026-01-01T12:00:00Z'),
        'America/New_York',
      ),
      '01/01/2026 07:00 · America/New_York',
    );
    expect(
      marginTimestamp(DateTime.parse('2026-10-28T12:00:00Z'), 'Unknown/Zone'),
      '28/10/2026 12:00 · UTC',
    );
  });

  testWidgets(
    'guard blocks all reads before creating private report provider',
    (tester) async {
      final repository = FakeReferenceMarginRepository();
      await _pump(tester, repository, allowed: false);
      expect(
        find.text('Chưa có quyền xem giá vốn và lãi tham chiếu.'),
        findsOneWidget,
      );
      expect(repository.summaryCalls, isEmpty);
      expect(repository.seriesCalls, isEmpty);
      expect(repository.ordersCalls, isEmpty);
    },
  );

  testWidgets(
    'summary separates cohorts and only opens orders after an explicit tab selection',
    (tester) async {
      final repository = FakeReferenceMarginRepository();
      await _pump(tester, repository);
      expect(find.text('Toàn bộ đơn hoàn tất'), findsOneWidget);
      expect(find.text('Các đơn đủ giá vốn'), findsOneWidget);
      expect(find.text('1.000.000 VND'), findsOneWidget);
      expect(find.text('800.000 VND'), findsOneWidget);
      expect(find.text('62,50%'), findsOneWidget);
      expect(find.textContaining('Bị loại: 2'), findsOneWidget);
      expect(find.text('Múi giờ: Asia/Ho_Chi_Minh'), findsOneWidget);
      expect(repository.summaryCalls, hasLength(1));
      expect(repository.seriesCalls, hasLength(1));
      expect(repository.ordersCalls, isEmpty);
      await tester.pump();
      expect(repository.summaryCalls, hasLength(1));
      await _tap(tester, find.text('Đơn đối chiếu'));
      expect(repository.ordersCalls, hasLength(1));
      expect(
        find.byKey(const ValueKey(('margin-order', 'order-0'))),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'excluded action preserves unknown costs and detail never fetches per-order data',
    (tester) async {
      final repository = FakeReferenceMarginRepository();
      await _pump(tester, repository);
      await _tap(tester, find.byKey(const ValueKey('margin-view-excluded')));
      expect(
        repository.ordersCalls.single.costCoverage,
        CostCoverageFilter.excluded,
      );
      // Missing cost and margin stay unknown on each excluded card, never 0.
      for (final id in ['order-8', 'order-9']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey(('margin-order', id))),
            matching: find.text('Chưa xác định'),
          ),
          findsNWidgets(2),
        );
      }
      await _tap(tester, find.text('Chi tiết đối chiếu').first);
      expect(find.text('Đối chiếu OD-order-8'), findsOneWidget);
      expect(
        find.textContaining('Giá tham chiếu được chốt khi nhận món.'),
        findsOneWidget,
      );
      expect(repository.ordersCalls, hasLength(1));
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Chưa xác định'),
        ),
        findsNWidgets(2),
      );
      await _tap(tester, find.text('Đóng'));
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'currency draft does not relabel previous results and Apply loads the new query',
    (tester) async {
      final repository = FakeReferenceMarginRepository();
      await _pump(tester, repository);
      await tester.enterText(
        find.byKey(const ValueKey('margin-currency')),
        'USD',
      );
      await tester.pumpAndSettle();
      expect(repository.summaryCalls, hasLength(1));
      expect(find.text('Tiền tệ: VND'), findsOneWidget);
      expect(find.text('1.000.000 VND'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('margin-apply')));
      expect(repository.summaryCalls.last.currencyCode, 'USD');
      expect(repository.seriesCalls.last.$1.currencyCode, 'USD');
      expect(find.text('Tiền tệ: USD'), findsOneWidget);
      expect(find.text('1.000.000 USD'), findsOneWidget);
      expect(find.text('1.000.000 VND'), findsNothing);
      expect(repository.ordersCalls, isEmpty);
    },
  );

  testWidgets(
    'series conflict is recoverable and never replaces successful summary with zero',
    (tester) async {
      final repository = FakeReferenceMarginRepository()
        ..onSeries = (_, _) async => const Error(
          Failure(
            type: FailureType.conflict,
            code: 'REPORT_COST_DATA_CONFLICT',
            message: 'Dữ liệu giá vốn cần đối soát.',
          ),
        );
      await _pump(tester, repository);
      expect(find.text('Dữ liệu giá vốn cần đối soát.'), findsOneWidget);
      expect(find.text('1.000.000 VND'), findsOneWidget);
      expect(find.byKey(const ValueKey('margin-series-chart')), findsNothing);
      repository.onSeries = null;
      await _tap(tester, find.text('Thử lại'));
      expect(repository.seriesCalls, hasLength(2));
      expect(repository.summaryCalls, hasLength(1));
      expect(find.byKey(const ValueKey('margin-series-chart')), findsOneWidget);
    },
  );

  testWidgets(
    'no-data is a successful zero cohort with unavailable percentages',
    (tester) async {
      final repository = FakeReferenceMarginRepository()
        ..summaryJson = marginSummaryJson(coverage: 'NO_DATA');
      await _pump(tester, repository);
      expect(find.text('Không áp dụng'), findsOneWidget);
      expect(find.text('Tỷ lệ đơn đủ giá vốn: Không áp dụng'), findsOneWidget);
      expect(find.text('0,00%'), findsNothing);
      // Three covered amounts plus net sales and sales of all completed orders.
      expect(find.text('0 VND'), findsNWidgets(5));
      expect(
        find.textContaining('Chưa có đơn hoàn tất trong bộ lọc này.'),
        findsOneWidget,
      );
      expect(find.text('Thử lại'), findsNothing);
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'downgrade closes an open private reconciliation dialog and clears its values',
    (tester) async {
      final repository = FakeReferenceMarginRepository();
      final entitlements = FakeEntitlementRepository()
        ..result = Success(
          makeEntitlement(features: {'ORDER_MANAGEMENT', 'DETAIL_REPORT'}),
        );
      final container = await _pump(
        tester,
        repository,
        entitlements: entitlements,
      );
      await _tap(tester, find.byKey(const ValueKey('margin-view-excluded')));
      await _tap(tester, find.text('Chi tiết đối chiếu').first);
      expect(find.text('Đối chiếu OD-order-8'), findsOneWidget);
      entitlements.result = Success(
        makeEntitlement(features: {'ORDER_MANAGEMENT'}),
      );
      await container.read(authControllerProvider).revalidateAccess();
      await tester.pumpAndSettle();
      expect(find.text('Đối chiếu OD-order-8'), findsNothing);
      expect(
        find.text('Chưa có quyền xem giá vốn và lãi tham chiếu.'),
        findsOneWidget,
      );
      expect(repository.ordersCalls, hasLength(1));
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'late same-scope server denial scrubs an open detail dialog and does not restart private reads',
    (tester) async {
      final repository = FakeReferenceMarginRepository();
      final entitlements = FakeEntitlementRepository()
        ..result = Success(
          makeEntitlement(features: {'ORDER_MANAGEMENT', 'DETAIL_REPORT'}),
        );
      final container = await _pump(
        tester,
        repository,
        entitlements: entitlements,
      );
      await _tap(tester, find.text('Đơn đối chiếu'));
      expect(repository.ordersCalls, hasLength(1));

      final response =
          Completer<Result<ReportEnvelope<ReferenceMarginSummary>>>();
      repository.onSummary = (_) => response.future;
      final controller = container.read(referenceMarginReportsProvider);
      final request = controller.loadSummary();
      await tester.pump();
      expect(controller.summary.loading, true);
      expect(controller.summary.value, isNotNull);
      await _tap(tester, find.text('Chi tiết đối chiếu').first);
      expect(find.text('Đối chiếu OD-order-0'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('40.000 VND'),
        ),
        findsOneWidget,
      );

      response.complete(
        const Error(
          Failure(
            type: FailureType.forbidden,
            code: 'FORBIDDEN',
            message: 'Báo cáo đã bị máy chủ từ chối.',
          ),
        ),
      );
      await request;
      await tester.pumpAndSettle();
      expect(find.text('Đối chiếu OD-order-0'), findsNothing);
      expect(find.text('40.000 VND'), findsNothing);
      expect(find.textContaining('Giá vốn tham chiếu:'), findsNothing);
      expect(find.text('Báo cáo đã bị máy chủ từ chối.'), findsOneWidget);
      expect(find.text('Kiểm tra lại quyền truy cập'), findsOneWidget);
      expect(
        container.read(authControllerProvider).state.session!.permissions,
        containsAll({'ORDER_VIEW', 'REPORT_DETAIL_VIEW'}),
      );
      expect(entitlements.calls, 2); // Login and one automatic access check.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(repository.summaryCalls, hasLength(2));
      expect(repository.seriesCalls, hasLength(1));
      expect(repository.ordersCalls, hasLength(1));
      expect(entitlements.calls, 2);
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'draft changes are flagged until applied and presets show their selection',
    (tester) async {
      final repository = FakeReferenceMarginRepository();
      await _pump(tester, repository);
      final dirty = find.byKey(const ValueKey('margin-filter-dirty'));
      expect(dirty, findsNothing);
      ChoiceChip chip(String label) =>
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
      expect(chip('7 ngày qua').selected, true);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Hôm nay'));
      expect(chip('Hôm nay').selected, true);
      expect(chip('7 ngày qua').selected, false);
      expect(dirty, findsOneWidget);
      expect(repository.summaryCalls, hasLength(1));
      await _tap(tester, find.byKey(const ValueKey('margin-apply')));
      expect(dirty, findsNothing);
      expect(repository.summaryCalls, hasLength(2));
      expect(tester.takeException(), null);
    },
  );

  testWidgets('series detail appears for the bucket the user selects', (
    tester,
  ) async {
    final repository = FakeReferenceMarginRepository();
    await _pump(tester, repository, width: 1200);
    final detail = find.byKey(const ValueKey('margin-series-detail'));
    expect(detail, findsNothing);
    final chart = find.byKey(const ValueKey('margin-series-chart'));
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(chart) + const Offset(80, 40));
    await tester.pumpAndSettle();
    expect(detail, findsOneWidget);
    expect(
      find.descendant(of: detail, matching: find.text('800.000 VND')),
      findsOneWidget,
    );
    expect(tester.takeException(), null);
  });

  for (final width in [320.0, 600.0, 800.0, 1200.0, 1440.0]) {
    testWidgets(
      'margin workspace, cards, series table and detail fit ${width}px at text200 with keyboard',
      (tester) async {
        final repository = FakeReferenceMarginRepository()
          ..summaryJson = marginSummaryJson(negative: true);
        await _pump(tester, repository, width: width, scale: 2, keyboard: true);
        expect(tester.takeException(), null);
        expect(find.text('-100.000 VND'), findsOneWidget);
        await _tap(tester, find.byKey(const ValueKey('margin-series-mode')));
        expect(
          find.byKey(const ValueKey('margin-series-table')),
          findsOneWidget,
        );
        expect(tester.takeException(), null);
        await _tap(tester, find.byKey(const ValueKey('margin-view-excluded')));
        expect(
          repository.ordersCalls.single.costCoverage,
          CostCoverageFilter.excluded,
        );
        expect(tester.takeException(), null);
        await _tap(tester, find.text('Chi tiết đối chiếu').first);
        expect(find.text('Đối chiếu OD-order-8'), findsOneWidget);
        expect(tester.takeException(), null);
        await _tap(tester, find.text('Đóng'));
        expect(tester.takeException(), null);
      },
    );
  }
}
