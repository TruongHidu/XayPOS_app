import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/app/router/app_routes.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/network/api_client.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/shell/app_shell.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/reference_margin_reports/presentation/screens/reference_margin_reports_screen.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_date.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/entitlement.dart';

import '../../helpers/auth_fakes.dart';
import 'reference_margin_access_test.dart'
    show marginFeatures, marginPermissions;

class _ReportServer implements HttpClientAdapter {
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final query = options.queryParameters;
    final meta = <String, Object?>{
      'fromDate': query['fromDate'],
      'toDate': query['toDate'],
      'timezone': 'Asia/Ho_Chi_Minh',
      'currencyCode': query['currencyCode'] ?? 'VND',
      'generatedAt': '2026-10-28T05:00:00Z',
      'serviceType': query['serviceType'],
      'sourceChannel': query['sourceChannel'],
      'granularity': query['granularity'],
      'dateBasis': 'COMPLETED',
    };
    final summary = <String, Object?>{
      'costBasis': 'CATALOG_REFERENCE_AT_ACCEPTANCE',
      'marginScope': 'FULLY_COSTED_COMPLETED_ORDERS',
      'costCoverageStatus': 'NO_DATA',
      'completedOrderCount': 0,
      'fullyCostedOrderCount': 0,
      'excludedOrderCount': 0,
      'orderCoveragePercent': null,
      'subtotalAmount': 0,
      'discountAmount': 0,
      'taxAmount': 0,
      'serviceChargeAmount': 0,
      'salesAmount': 0,
      'netSalesAmount': 0,
      'coveredNetSalesAmount': 0,
      'coveredReferenceCostAmount': 0,
      'coveredReferenceMarginAmount': 0,
      'coveredReferenceMarginPercent': null,
      'costIssues': [],
    };
    final Object data;
    if (options.path.endsWith('/summary')) {
      data = summary;
    } else if (options.path.endsWith('/series')) {
      final from = ReportDate.parse(query['fromDate'] as String);
      final to = ReportDate.parse(query['toDate'] as String);
      final monthly = query['granularity'] == 'MONTH';
      var cursor = monthly ? ReportDate(from.year, from.month, 1) : from;
      final buckets = <Map<String, Object?>>[];
      while (cursor <= to) {
        buckets.add({'bucketStartDate': cursor.toIso8601Date(), ...summary});
        cursor = monthly
            ? ReportDate.fromDateTime(
                DateTime.utc(cursor.year, cursor.month + 1),
              )
            : cursor.addDays(1);
      }
      data = buckets;
    } else if (options.path.endsWith('/orders')) {
      data = {
        'content': [],
        'page': query['page'] ?? 0,
        'size': query['size'] ?? 20,
        'totalElements': 0,
        'totalPages': 0,
      };
    } else {
      throw StateError('Unexpected endpoint: ${options.path}');
    }
    return ResponseBody.fromString(
      jsonEncode({'meta': meta, 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        'cache-control': ['no-store'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Rig {
  _Rig({
    required this.container,
    required this.auth,
    required this.authRepository,
    required this.entitlements,
    required this.server,
    required this.router,
  });
  final ProviderContainer container;
  final AuthController auth;
  final FakeAuthRepository authRepository;
  final FakeEntitlementRepository entitlements;
  final _ReportServer server;
  final GoRouter router;
}

Future<_Rig> _pump(
  WidgetTester tester, {
  Set<String> permissions = marginPermissions,
  Set<String> features = marginFeatures,
  bool sidebarSource = false,
}) async {
  tester.view.physicalSize = const Size(1200, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final role = sidebarSource ? UserRole.owner : UserRole.cashier;
  final authRepository = FakeAuthRepository()
    ..loginResult = Success(
      makeAuthSession(role: role, permissions: permissions),
    )
    ..restoreResult = Success(
      makeAuthSession(role: role, permissions: permissions),
    );
  final entitlements = FakeEntitlementRepository()
    ..result = Success(makeEntitlement(features: features));
  final auth = makeController(
    authRepository: authRepository,
    entitlementRepository: entitlements,
  );
  await auth.login(
    const LoginCredentials(email: 'margin@example.com', password: 'password'),
  );
  final events = SessionEvents();
  final clients = ApiClients(
    tokenStorage: FakeTokenStorage(),
    sessionEvents: events,
    baseUrl: 'https://reference-margin.example.test',
  );
  final server = _ReportServer();
  clients.authenticated.httpClientAdapter = server;
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((_) => auth),
      apiClientsProvider.overrideWithValue(clients),
    ],
  );
  final router = sidebarSource
      ? GoRouter(
          initialLocation: '/navigation-source',
          observers: [container.read(referenceMarginRouteObserverProvider)],
          routes: [
            GoRoute(
              path: '/navigation-source',
              builder: (_, _) => const AppShell(
                initialSection: 'reports',
                child: Center(child: Text('Màn hình trước khi mở báo cáo')),
              ),
            ),
            GoRoute(
              path: AppRoutes.referenceMargin,
              builder: (_, _) => const AppShell(
                initialSection: 'reference-margin-reports',
                child: ReferenceMarginReportsScreen(),
              ),
            ),
          ],
        )
      : (container.read(appRouterProvider)..go(AppRoutes.referenceMargin));
  addTearDown(() {
    if (sidebarSource) router.dispose();
    container.dispose();
    clients.authenticated.close(force: true);
    clients.raw.close(force: true);
    events.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return _Rig(
    container: container,
    auth: auth,
    authRepository: authRepository,
    entitlements: entitlements,
    server: server,
    router: router,
  );
}

void main() {
  testWidgets(
    'real router admits cashier into separate report and loads no ordinary report',
    (tester) async {
      final rig = await _pump(tester);
      expect(
        rig.router.routeInformationProvider.value.uri.path,
        AppRoutes.referenceMargin,
      );
      expect(find.byType(ReferenceMarginReportsScreen), findsOneWidget);
      expect(rig.server.paths, hasLength(2));
      expect(
        rig.server.paths,
        containsAll([
          '/api/v1/reports/reference-margin/summary',
          '/api/v1/reports/reference-margin/series',
        ]),
      );
      expect(rig.server.paths.any((path) => path.endsWith('/orders')), isFalse);
      await tester.pumpAndSettle();
      expect(rig.server.paths, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  for (final missing in [...marginPermissions, ...marginFeatures]) {
    testWidgets(
      'deep link without $missing cannot mount or fetch protected report',
      (tester) async {
        final rig = await _pump(
          tester,
          permissions: {...marginPermissions}..remove(missing),
          features: {...marginFeatures}..remove(missing),
        );
        expect(
          rig.router.routeInformationProvider.value.uri.path,
          AppRoutes.cashierWebOnly,
        );
        expect(find.byType(ReferenceMarginReportsScreen), findsNothing);
        expect(rig.server.paths, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'tapping new sidebar entry opens actual screen instead of placeholder',
    (tester) async {
      final rig = await _pump(tester, sidebarSource: true);
      expect(rig.server.paths, isEmpty);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      final entry = find.widgetWithText(ListTile, 'Giá vốn & lãi tham chiếu');
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(
        rig.router.routeInformationProvider.value.uri.path,
        AppRoutes.referenceMargin,
      );
      expect(find.byType(ReferenceMarginReportsScreen), findsOneWidget);
      expect(find.text('Màn hình trước khi mở báo cáo'), findsNothing);
      expect(rig.server.paths, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'subscription downgrade redirects and removes protected report without another GET',
    (tester) async {
      final rig = await _pump(tester);
      final reads = rig.server.paths.length;
      rig.entitlements.result = Success(
        makeEntitlement(
          features: marginFeatures,
          status: SubscriptionStatus.inactive,
        ),
      );
      await rig.auth.revalidateAccess();
      await tester.pumpAndSettle();
      expect(find.byType(ReferenceMarginReportsScreen), findsNothing);
      expect(
        rig.router.routeInformationProvider.value.uri.path,
        AppRoutes.cashierWebOnly,
      );
      expect(rig.server.paths, hasLength(reads));
      expect(tester.takeException(), isNull);
    },
  );
}
