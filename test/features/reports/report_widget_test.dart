import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/reports/domain/entities/payment_method_report_row.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_date.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_enums.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_money.dart';
import 'package:pos_saas_app/features/reports/domain/entities/revenue_series_point.dart';
import 'package:pos_saas_app/features/reports/presentation/screens/daily_revenue_screen.dart';
import 'package:pos_saas_app/features/reports/presentation/screens/reports_screen.dart';
import 'package:pos_saas_app/features/reports/presentation/widgets/payment_methods_card.dart';
import 'package:pos_saas_app/features/reports/presentation/widgets/report_kpi_card.dart';
import 'package:pos_saas_app/features/reports/presentation/widgets/report_kpi_grid.dart';
import 'package:pos_saas_app/features/reports/presentation/widgets/revenue_series_chart.dart';

import '../../helpers/auth_fakes.dart';
import 'report_fakes.dart';

Future<AuthController> _makeAuth() async {
  final repo = FakeAuthRepository()
    ..loginResult = Success(
      makeAuthSession(
        permissions: {'REPORT_DAILY_VIEW', 'REPORT_DETAIL_VIEW', 'ORDER_VIEW'},
      ),
    );
  final entitlement = FakeEntitlementRepository()
    ..result = Success(
      makeEntitlement(
        features: {'DAILY_REVENUE', 'DETAIL_REPORT', 'ORDER_MANAGEMENT'},
      ),
    );
  final auth = makeController(
    authRepository: repo,
    entitlementRepository: entitlement,
  );
  await auth.login(
    const LoginCredentials(email: 'user@example.com', password: 'password'),
  );
  return auth;
}

void main() {
  late FakeReportRepository fakeRepo;
  late AuthController authController;

  setUp(() async {
    fakeRepo = FakeReportRepository();
    authController = await _makeAuth();
  });

  Widget buildTestApp({required Widget child, double textScale = 1}) {
    return ProviderScope(
      overrides: [
        reportRepositoryProvider.overrideWithValue(fakeRepo),
        authControllerProvider.overrideWith((ref) => authController),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: child,
      ),
    );
  }

  group('DailyRevenueScreen Widget Test', () {
    testWidgets('renders daily revenue KPIs and breakdown correctly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp(child: const DailyRevenueScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Doanh thu ngày'), findsOneWidget);
      expect(find.text('Tiền đã thu'), findsOneWidget);
      expect(find.text('Doanh số đơn hoàn tất'), findsWidgets);
      expect(find.text('Đơn hoàn tất'), findsWidgets);
      expect(find.text('Giá trị TB / đơn hoàn tất'), findsOneWidget);
      expect(find.text('Cấu thành doanh số đơn hoàn tất'), findsOneWidget);
      expect(find.text('Tiền hàng (Subtotal)'), findsOneWidget);
    });
  });

  group('ReportsScreen Widget Test', () {
    testWidgets('renders 3 tabs and switches smoothly', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp(child: const ReportsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Báo cáo doanh thu'), findsOneWidget);
      expect(find.text('Tổng quan'), findsOneWidget);
      expect(find.text('Món bán chạy'), findsOneWidget);
      expect(find.text('Đơn đối chiếu'), findsOneWidget);

      // Tab 1: Overview
      expect(find.text('Xu hướng doanh thu (VND)'), findsOneWidget);
      expect(find.text('Phương thức thanh toán'), findsOneWidget);

      // Switch to Tab 2: Top Items
      await tester.tap(find.text('Món bán chạy'));
      await tester.pumpAndSettle();

      expect(fakeRepo.topItemsCalls, 1);
      expect(find.text('Phở bò đặc biệt'), findsOneWidget);
      expect(find.text('Cà phê sữa đá'), findsOneWidget);

      // Switch to Tab 3: Orders
      await tester.tap(find.text('Đơn đối chiếu'));
      await tester.pumpAndSettle();

      expect(fakeRepo.ordersCalls, 1);
      expect(find.text('ORD-20261015-001'), findsOneWidget);
      expect(find.text('ORD-20261015-002'), findsOneWidget);
    });
  });

  for (final width in [320.0, 800.0, 1200.0]) {
    for (final daily in [true, false]) {
      testWidgets(
        '${daily ? 'daily' : 'range'} report fits width $width at 200% text size',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            buildTestApp(
              textScale: 2,
              child: daily ? const DailyRevenueScreen() : const ReportsScreen(),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Tiền đã thu'), findsWidgets);
          expect(find.text('Giá trị TB / đơn hoàn tất'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('KPI cards show long values inside a narrow desktop panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const value = '123.456.789.012.345.678';

    await tester.pumpWidget(
      buildTestApp(
        textScale: 2,
        child: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: ReportKpiGrid(
                  children: [
                    ReportKpiCard(
                      title: 'Giá trị trung bình mỗi đơn hoàn tất',
                      valueText: value,
                      icon: Icons.trending_up,
                      secondaryText:
                          'Đã có 100 giao dịch thanh toán thành công',
                    ),
                    ReportKpiCard(
                      title: 'Đơn hoàn tất',
                      valueText: '100 đơn',
                      icon: Icons.check_circle_outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cards = find.byType(ReportKpiCard);
    expect(tester.getSize(cards.first).height, greaterThan(140));
    expect(
      tester.getTopLeft(cards.at(1)).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(cards.first).dy),
    );
    final valueParagraph = tester.renderObject<RenderParagraph>(
      find.text(value),
    );
    expect(valueParagraph.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  group('RevenueSeriesChart zero safety', () {
    testWidgets(
      'renders without divide-by-zero or crash when points are zero',
      (tester) async {
        final zeroPoints = [
          RevenueSeriesPoint(
            bucketStartDate: const ReportDate(2026, 10, 1),
            collectedAmount: ReportMoney.zero,
            completedOrderSalesAmount: ReportMoney.zero,
            successfulPaymentCount: 0,
            completedOrderCount: 0,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RevenueSeriesChart(
                points: zeroPoints,
                currencyCode: 'VND',
                granularity: ReportGranularity.day,
                onGranularityChanged: (_) {},
                showCollected: true,
                showCompleted: true,
                onToggleCollected: () {},
                onToggleCompleted: () {},
                isTableView: false,
                onToggleTableView: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(RevenueSeriesChart), findsOneWidget);
        expect(find.text('Xu hướng doanh thu (VND)'), findsOneWidget);
      },
    );
  });

  group('PaymentMethodsCard zero state', () {
    testWidgets('displays zero state message when collections are zero', (
      tester,
    ) async {
      final zeroMethods = [
        PaymentMethodReportRow(
          paymentMethod: ReportPaymentMethod.cash,
          collectedAmount: ReportMoney.zero,
          successfulPaymentCount: 0,
          percentage: 0.0,
        ),
        PaymentMethodReportRow(
          paymentMethod: ReportPaymentMethod.transfer,
          collectedAmount: ReportMoney.zero,
          successfulPaymentCount: 0,
          percentage: 0.0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentMethodsCard(rows: zeroMethods, currencyCode: 'VND'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chưa có phát sinh thu tiền'), findsOneWidget);
    });
  });
}
