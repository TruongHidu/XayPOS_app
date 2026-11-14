import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/overview/presentation/screens/overview_screen.dart';
import 'package:pos_saas_app/features/reports/presentation/widgets/report_kpi_card.dart';
import '../../helpers/auth_fakes.dart';
import '../order/order_fakes.dart';
import '../qr_order/qr_fakes.dart';
import '../reports/report_fakes.dart';
import '../tables/table_fakes.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Set<String> permissions,
  required Set<String> features,
  FakeReportRepository? reports,
}) async {
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: features)),
  );
  await auth.login(
    const LoginCredentials(email: 'a@b.com', password: 'password'),
  );
  final server = TableServer()..table = tableJson(occupied: true);
  addTearDown(server.close);
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      reportRepositoryProvider.overrideWithValue(
        reports ?? FakeReportRepository(),
      ),
      orderRepositoryProvider.overrideWithValue(FakeOrders()),
      qrRequestRepositoryProvider.overrideWithValue(FakeQrRequests()),
      restaurantTableRepositoryProvider.overrideWithValue(server.tables),
      tableAreaRepositoryProvider.overrideWithValue(server.areas),
      tableSessionRepositoryProvider.overrideWithValue(server.sessions),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: OverviewScreen())),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('shows today\'s takings and what is going on now', (
    tester,
  ) async {
    await _pump(
      tester,
      permissions: {...orderPermissions, 'REPORT_DAILY_VIEW'},
      features: {...orderFeatures, 'DAILY_REVENUE'},
    );
    expect(find.textContaining('Hôm nay, '), findsOneWidget);
    expect(find.byType(ReportKpiCard), findsNWidgets(4));
    expect(find.text('Tiền đã thu'), findsOneWidget);
    expect(find.text('Đang diễn ra'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-tables')), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-takeaway')), findsOneWidget);
    // No inventory rights in this package: that tile stays away.
    expect(find.byKey(const ValueKey('overview-low-stock')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a report-only account sees takings without live tiles', (
    tester,
  ) async {
    await _pump(
      tester,
      permissions: {'REPORT_DAILY_VIEW'},
      features: {'DAILY_REVENUE'},
    );
    expect(find.byType(ReportKpiCard), findsNWidgets(4));
    expect(find.text('Đang diễn ra'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed report offers a retry', (tester) async {
    final reports = FakeReportRepository()
      ..dailyReportResult = const Error(
        Failure(type: FailureType.network, message: 'Mất mạng.'),
      );
    await _pump(
      tester,
      permissions: {'REPORT_DAILY_VIEW'},
      features: {'DAILY_REVENUE'},
      reports: reports,
    );
    expect(find.textContaining('Chưa tải được doanh thu.'), findsOneWidget);
    reports.dailyReportResult = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportKpiCard), findsNWidgets(4));
  });

  test('the overview follows the daily report right', () {
    final owner = makeAppSession(
      permissions: {'REPORT_DAILY_VIEW'},
      features: {'DAILY_REVENUE'},
    );
    final cashier = makeAppSession(
      permissions: {'ORDER_VIEW'},
      features: {'ORDER_MANAGEMENT', 'DAILY_REVENUE'},
    );
    expect(AccessPolicy.canSeeSection(owner, 'overview'), isTrue);
    expect(AccessPolicy.canSeeSection(cashier, 'overview'), isFalse);
    expect(AccessPolicy.canOpenRoute(owner, '/app/overview'), isTrue);
    expect(AccessPolicy.canOpenRoute(cashier, '/app/overview'), isFalse);
  });
}
