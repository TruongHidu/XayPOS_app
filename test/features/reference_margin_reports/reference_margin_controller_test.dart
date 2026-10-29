import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_events.dart';
import 'package:pos_saas_app/features/reference_margin_reports/data/dto/reference_margin_dto.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/entities/reference_margin_enums.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/entities/reference_margin_filters.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/entities/reference_margin_report.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/use_cases/reference_margin_use_cases.dart';
import 'package:pos_saas_app/features/reference_margin_reports/presentation/controllers/reference_margin_reports_controller.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_date.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_enums.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_meta.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/entitlement.dart';

import '../../helpers/auth_fakes.dart';
import 'margin_fakes.dart';

typedef _SummaryResult = Result<ReportEnvelope<ReferenceMarginSummary>>;
typedef _SeriesResult =
    Result<ReportEnvelope<List<ReferenceMarginSeriesPoint>>>;

const _permissions = {'ORDER_VIEW', 'REPORT_DETAIL_VIEW'};
const _features = {'ORDER_MANAGEMENT', 'DETAIL_REPORT'};

AppSession _session({
  String tenant = 'restaurant-1',
  Set<String> permissions = _permissions,
  Set<String> features = _features,
  SubscriptionStatus status = SubscriptionStatus.active,
}) => makeAppSession(
  role: UserRole.cashier,
  restaurantId: tenant,
  permissions: permissions,
  features: features,
  status: status,
);

_SummaryResult _summary(
  ReferenceMarginFilter filter, {
  bool negative = false,
}) => Success(
  ReferenceMarginDto.summary(
    marginEnvelopeJson(marginSummaryJson(negative: negative), filter: filter),
    filter,
  ),
);

Future<_SeriesResult> _series(
  ReferenceMarginFilter filter,
  ReportGranularity granularity,
) =>
    FakeReferenceMarginRepository().getSeries(filter, granularity: granularity);

class _Harness {
  _Harness({
    AppSession? initialSession,
    bool anonymous = false,
    ReferenceMarginFilter? initialFilter,
  }) {
    session = anonymous ? null : initialSession ?? _session();
    controller = ReferenceMarginReportsController(
      session: () => session,
      getSummary: GetReferenceMarginSummary(repo),
      getSeries: GetReferenceMarginSeries(repo),
      getOrders: GetReferenceMarginOrders(repo),
      events: events,
      initialFilter: initialFilter ?? marginFilter(),
      onAccessDenied: (failure) async {
        accessChecks++;
        accessFailures.add(failure);
        await accessCheck?.call();
      },
    );
    addTearDown(() {
      controller.dispose();
      events.dispose();
    });
  }

  AppSession? session;
  final repo = FakeReferenceMarginRepository();
  final events = OrderEvents();
  late final ReferenceMarginReportsController controller;
  int accessChecks = 0;
  final accessFailures = <Failure>[];
  Future<void> Function()? accessCheck;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'initialization loads independent summary/series once and orders stay lazy',
    () async {
      final h = _Harness();
      await h.controller.initialize();
      expect(h.repo.summaryCalls, hasLength(1));
      expect(h.repo.seriesCalls, hasLength(1));
      expect(h.repo.ordersCalls, isEmpty);
      expect(h.controller.summary.value!.data.completedOrderCount, 10);
      expect(h.controller.series.value!.data, hasLength(2));
      expect(
        h.controller.summary.queryKey,
        isNot(h.controller.series.queryKey),
      );
      await h.controller.initialize();
      expect(h.repo.summaryCalls, hasLength(1));
      await h.controller.openOrders();
      expect(h.repo.ordersCalls, hasLength(1));
      expect(h.controller.orders.value!.data.totalElements, 10);
      await h.controller.openOrders();
      expect(h.repo.ordersCalls, hasLength(1));
    },
  );

  test(
    'draft changes do not query and Apply sends the normalized full filter',
    () async {
      final h = _Harness();
      await h.controller.initialize();
      h.controller.setDraftCurrencyCode('  usd  ');
      h.controller.setDraftServiceType(ServiceType.takeaway);
      h.controller.setDraftSourceChannel(ReportSourceChannel.qrTable);
      expect(h.repo.summaryCalls, hasLength(1));
      expect(h.controller.summary.value!.meta.currencyCode, 'VND');
      await h.controller.applyFilters();
      final query = h.repo.summaryCalls.last;
      expect(query.currencyCode, 'USD');
      expect(query.serviceType, ServiceType.takeaway);
      expect(query.sourceChannel, ReportSourceChannel.qrTable);
      expect(h.controller.appliedFilter, query);
      expect(h.controller.summary.value!.meta.currencyCode, 'USD');
      expect(h.controller.series.value!.meta.currencyCode, 'USD');
      expect(h.repo.ordersCalls, isEmpty);
    },
  );

  test(
    'late VND responses cannot replace a newer USD query or its metadata',
    () async {
      final h = _Harness();
      final oldSummary = Completer<_SummaryResult>();
      final oldSeries = Completer<_SeriesResult>();
      h.repo.onSummary = (filter) => filter.currencyCode == 'VND'
          ? oldSummary.future
          : Future.value(_summary(filter));
      h.repo.onSeries = (filter, granularity) => filter.currencyCode == 'VND'
          ? oldSeries.future
          : _series(filter, granularity);
      final initial = h.controller.initialize();
      h.controller.setDraftCurrencyCode('USD');
      await h.controller.applyFilters();
      expect(h.controller.summary.value!.meta.currencyCode, 'USD');
      expect(h.controller.series.value!.meta.currencyCode, 'USD');
      oldSummary.complete(_summary(marginFilter()));
      oldSeries.complete(await _series(marginFilter(), ReportGranularity.day));
      await initial;
      expect(h.controller.summary.value!.meta.currencyCode, 'USD');
      expect(h.controller.series.value!.meta.currencyCode, 'USD');
      expect(h.repo.summaryCalls.map((filter) => filter.currencyCode), [
        'VND',
        'USD',
      ]);
      expect(h.controller.summary.failure, isNull);
    },
  );

  test(
    'a delayed DAY series cannot replace the selected MONTH series',
    () async {
      final h = _Harness();
      final day = Completer<_SeriesResult>();
      h.repo.onSeries = (filter, granularity) =>
          granularity == ReportGranularity.day
          ? day.future
          : _series(filter, granularity);
      final initial = h.controller.initialize();
      await h.controller.setGranularity(ReportGranularity.month);
      expect(
        h.controller.series.value!.meta.granularity,
        ReportGranularity.month,
      );
      expect(h.controller.series.value!.data, hasLength(1));
      day.complete(await _series(marginFilter(), ReportGranularity.day));
      await initial;
      expect(h.controller.granularity, ReportGranularity.month);
      expect(
        h.controller.series.value!.meta.granularity,
        ReportGranularity.month,
      );
      expect(h.repo.summaryCalls, hasLength(1));
      expect(h.repo.seriesCalls.map((query) => query.$2), [
        ReportGranularity.day,
        ReportGranularity.month,
      ]);
    },
  );

  test(
    'duplicate refresh/initialize while pending does not issue repeated GETs',
    () async {
      final h = _Harness();
      final summary = Completer<_SummaryResult>();
      final series = Completer<_SeriesResult>();
      h.repo.onSummary = (_) => summary.future;
      h.repo.onSeries = (_, _) => series.future;
      final pending = h.controller.initialize();
      await h.controller.initialize();
      await h.controller.refresh();
      await h.controller.loadSummary();
      await h.controller.loadSeries();
      expect(h.repo.summaryCalls, hasLength(1));
      expect(h.repo.seriesCalls, hasLength(1));
      expect(h.repo.ordersCalls, isEmpty);
      await h.controller.openOrders();
      expect(h.repo.ordersCalls, hasLength(1));
      expect(h.controller.orders.value, isNotNull);
      summary.complete(_summary(marginFilter()));
      series.complete(await _series(marginFilter(), ReportGranularity.day));
      await pending;
      expect(h.controller.summary.loading, isFalse);
      expect(h.controller.series.loading, isFalse);
    },
  );

  test(
    'pagination, coverage, sort, direction and parent filters remain separate and reset page',
    () async {
      final h = _Harness();
      await h.controller.initialize();
      await h.controller.openOrders();
      await h.controller.setPageSize(2);
      await h.controller.setPage(2);
      expect(h.repo.ordersCalls.last.page, 2);
      expect(h.controller.orders.value!.data.content.first.orderId, 'order-4');
      await h.controller.setSort(
        ReferenceMarginOrderSort.referenceMarginAmount,
      );
      expect(h.repo.ordersCalls.last.page, 0);
      expect(
        h.repo.ordersCalls.last.sortBy,
        ReferenceMarginOrderSort.referenceMarginAmount,
      );
      await h.controller.setPage(1);
      await h.controller.setDirection(ReportSortDirection.asc);
      expect(h.repo.ordersCalls.last.page, 0);
      expect(h.repo.ordersCalls.last.direction, ReportSortDirection.asc);
      await h.controller.setPage(1);
      await h.controller.setCostCoverage(CostCoverageFilter.complete);
      expect(h.repo.ordersCalls.last.page, 0);
      expect(h.repo.ordersCalls.last.costCoverage, CostCoverageFilter.complete);
      expect(h.controller.orders.value!.data.totalElements, 8);
      await h.controller.setPage(1);
      h.controller.setDraftCurrencyCode('USD');
      await h.controller.applyFilters();
      expect(h.repo.ordersCalls.last.page, 0);
      expect(h.repo.ordersCalls.last.filter.currencyCode, 'USD');
      expect(h.repo.ordersCalls.last.costCoverage, CostCoverageFilter.complete);
      expect(h.controller.orders.value!.meta.currencyCode, 'USD');
    },
  );

  test(
    'failed same-query refresh retains explicitly stale data and original currency/date',
    () async {
      final h = _Harness();
      await h.controller.initialize();
      final previous = h.controller.summary.value;
      h.repo.onSummary = (_) async => const Error(networkFailure);
      await h.controller.loadSummary();
      expect(h.controller.summary.value, same(previous));
      expect(h.controller.summary.stale, isTrue);
      expect(h.controller.summary.failure, networkFailure);
      expect(h.controller.summary.value!.meta.currencyCode, 'VND');
      expect(
        h.controller.summary.value!.meta.fromDate,
        const ReportDate(2026, 10, 1),
      );
      h.controller.setDraftCurrencyCode('USD');
      await h.controller.applyFilters();
      expect(h.controller.summary.value, isNull);
      expect(h.controller.summary.failure, networkFailure);
      expect(h.controller.series.value!.meta.currencyCode, 'USD');
      expect(h.controller.appliedFilter.currencyCode, 'USD');
    },
  );

  test(
    '403 scrubs every panel and blocks automatic requests until explicit access retry',
    () async {
      final h = _Harness();
      await h.controller.initialize();
      await h.controller.openOrders();
      final series = Completer<_SeriesResult>();
      const denied = Failure(
        type: FailureType.forbidden,
        code: 'FORBIDDEN',
        message: 'Không được phép.',
      );
      h.repo.onSummary = (_) async => const Error(denied);
      h.repo.onSeries = (_, _) => series.future;
      final pending = h.controller.refresh();
      await _settle();
      expect(h.controller.accessFailure, denied);
      expect(h.controller.allowed, isFalse);
      expect(h.controller.summary.value, isNull);
      expect(h.controller.series.value, isNull);
      expect(h.controller.orders.value, isNull);
      expect(h.accessChecks, 1);
      final readCount = h.repo.summaryCalls.length;
      await h.controller.refresh();
      await h.controller.initialize();
      await h.controller.loadSummary();
      expect(h.repo.summaryCalls, hasLength(readCount));
      expect(h.accessChecks, 1);
      series.complete(await _series(marginFilter(), ReportGranularity.day));
      await pending;
      expect(h.controller.series.value, isNull);
      h.repo.onSeries = null;
      await h.controller.retryAccess();
      expect(h.controller.accessFailure, denied);
      expect(
        h.accessChecks,
        2,
      ); // One explicit check, no recursive denial loop.
      await h.controller.refresh();
      expect(h.accessChecks, 2);
      h.repo.onSummary = null;
      await h.controller.retryAccess();
      expect(h.accessChecks, 3);
      expect(h.controller.allowed, isTrue);
      expect(h.controller.summary.value, isNotNull);
      expect(h.controller.series.value, isNotNull);
      expect(h.controller.orders.value, isNotNull);
    },
  );

  test(
    'late 403 from an old query still revokes the current authority and scrubs newer currency data',
    () async {
      final h = _Harness();
      await h.controller.initialize();
      await h.controller.openOrders();
      final oldRead = Completer<_SummaryResult>();
      h.repo.onSummary = (filter) => filter.currencyCode == 'VND'
          ? oldRead.future
          : Future.value(_summary(filter));
      final pending = h.controller.loadSummary();
      h.controller.setDraftCurrencyCode('USD');
      await h.controller.applyFilters();
      expect(h.controller.summary.value!.meta.currencyCode, 'USD');
      expect(h.controller.series.value!.meta.currencyCode, 'USD');
      expect(h.controller.orders.value!.meta.currencyCode, 'USD');
      const denied = Failure(
        type: FailureType.forbidden,
        code: 'FORBIDDEN',
        message: 'Quyền đã thay đổi.',
      );
      oldRead.complete(const Error(denied));
      await pending;
      expect(h.controller.accessFailure, denied);
      expect(h.controller.allowed, isFalse);
      expect(h.controller.summary.value, isNull);
      expect(h.controller.series.value, isNull);
      expect(h.controller.orders.value, isNull);
      expect(h.accessChecks, 1);
      final reads = h.repo.summaryCalls.length;
      await h.controller.refresh();
      expect(h.repo.summaryCalls, hasLength(reads));
    },
  );

  test(
    'late 403 while hidden cannot be discarded by the visibility generation fence',
    () {
      fakeAsync((clock) {
        final h = _Harness();
        unawaited(h.controller.initialize());
        unawaited(h.controller.openOrders());
        clock.flushMicrotasks();
        expect(h.controller.orders.value, isNotNull);
        final oldRead = Completer<_SummaryResult>();
        h.repo.onSummary = (_) => oldRead.future;
        unawaited(h.controller.loadSummary());
        h.controller.setVisible(false);
        const denied = Failure(
          type: FailureType.featureNotEntitled,
          code: 'FEATURE_NOT_ENTITLED',
          message: 'Tính năng không còn hiệu lực.',
        );
        oldRead.complete(const Error(denied));
        clock.flushMicrotasks();
        expect(h.controller.accessFailure, denied);
        expect(h.controller.summary.value, isNull);
        expect(h.controller.series.value, isNull);
        expect(h.controller.orders.value, isNull);
        expect(h.accessChecks, 1);
        final reads = h.repo.summaryCalls.length;
        h.controller.setVisible(true);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(h.repo.summaryCalls, hasLength(reads));
        expect(h.controller.allowed, isFalse);
      });
    },
  );

  for (final deniedSession in <AppSession?>[
    null,
    _session(permissions: {'ORDER_VIEW'}),
    _session(permissions: {'REPORT_DETAIL_VIEW'}),
    _session(features: {'ORDER_MANAGEMENT'}),
    _session(features: {'DETAIL_REPORT'}),
    _session(status: SubscriptionStatus.inactive),
  ]) {
    test(
      'missing capability cannot initialize, refresh or open orders (${deniedSession?.permissions}/${deniedSession?.features})',
      () async {
        final h = _Harness(
          initialSession: deniedSession,
          anonymous: deniedSession == null,
        );
        await h.controller.initialize();
        await h.controller.refresh();
        await h.controller.openOrders();
        await h.controller.loadSummary();
        await h.controller.loadSeries();
        expect(h.controller.allowed, isFalse);
        expect(h.repo.summaryCalls, isEmpty);
        expect(h.repo.seriesCalls, isEmpty);
        expect(h.repo.ordersCalls, isEmpty);
      },
    );
  }

  for (final newSession in <AppSession?>[
    null,
    _session(tenant: 'restaurant-2'),
    _session(permissions: {'ORDER_VIEW'}),
    _session(features: {'ORDER_MANAGEMENT'}),
    _session(status: SubscriptionStatus.inactive),
  ]) {
    test(
      'late response cannot restore a cleared/replaced tenant authority (${newSession?.authenticatedUser.restaurantId}/${newSession?.permissions}/${newSession?.features}/${newSession?.subscriptionStatus})',
      () async {
        final h = _Harness();
        final summary = Completer<_SummaryResult>();
        final series = Completer<_SeriesResult>();
        h.repo.onSummary = (_) => summary.future;
        h.repo.onSeries = (_, _) => series.future;
        final pending = h.controller.initialize();
        h.session = newSession;
        summary.complete(_summary(marginFilter()));
        series.complete(await _series(marginFilter(), ReportGranularity.day));
        await pending;
        expect(h.controller.current, isFalse);
        expect(h.controller.summary.value, isNull);
        expect(h.controller.series.value, isNull);
        expect(h.controller.orders.value, isNull);
        await h.controller.refresh();
        expect(h.repo.summaryCalls, hasLength(1));
        expect(h.repo.seriesCalls, hasLength(1));
      },
    );
  }

  test(
    'token rotation preserves applied/draft filter and current response',
    () async {
      final h = _Harness();
      await h.controller.initialize();
      h.controller.setDraftCurrencyCode('USD');
      await h.controller.applyFilters();
      final previous = h.controller.summary.value;
      h.session = h.session!.copyWithAuth(
        user: h.session!.authenticatedUser,
        tokens: makeTokens(
          accessToken: 'new-access',
          refreshToken: 'new-refresh',
        ),
      );
      expect(h.controller.current, isTrue);
      expect(h.controller.allowed, isTrue);
      expect(h.controller.appliedFilter.currencyCode, 'USD');
      expect(h.controller.draftFilter.currencyCode, 'USD');
      expect(h.controller.summary.value, same(previous));
      await h.controller.initialize();
      expect(h.repo.summaryCalls, hasLength(2));
    },
  );

  test(
    'order-event revision coalesces updates; pending locks are not mutation refreshes',
    () {
      fakeAsync((clock) {
        final h = _Harness();
        unawaited(h.controller.initialize());
        clock.flushMicrotasks();
        h.events.lock('order-1');
        h.events.unlock('order-1');
        clock.elapse(const Duration(milliseconds: 500));
        clock.flushMicrotasks();
        expect(h.repo.summaryCalls, hasLength(1));
        h.events.emit('order-1', 'session-1');
        clock.elapse(const Duration(milliseconds: 90));
        h.events.emit('order-2', 'session-1');
        clock.elapse(const Duration(milliseconds: 179));
        clock.flushMicrotasks();
        expect(h.controller.summary.stale, isTrue);
        expect(h.repo.summaryCalls, hasLength(1));
        clock.elapse(const Duration(milliseconds: 1));
        clock.flushMicrotasks();
        expect(h.repo.summaryCalls, hasLength(2));
        expect(h.repo.seriesCalls, hasLength(2));
        expect(h.repo.ordersCalls, isEmpty);
        expect(h.controller.summary.stale, isFalse);
      });
    },
  );

  test(
    'mutation bursts during slow GETs queue one follow-up after all pending panels settle',
    () {
      fakeAsync((clock) {
        final h = _Harness();
        unawaited(h.controller.initialize());
        clock.flushMicrotasks();
        final slowSummary = Completer<_SummaryResult>();
        final slowSeries = Completer<_SeriesResult>();
        h.repo.onSummary = (_) => slowSummary.future;
        h.repo.onSeries = (_, _) => slowSeries.future;
        unawaited(h.controller.refresh());
        clock.flushMicrotasks();
        expect(h.repo.summaryCalls, hasLength(2));
        expect(h.repo.seriesCalls, hasLength(2));

        for (var event = 0; event < 4; event++) {
          h.events.emit('order-$event', 'session-1');
          clock.elapse(const Duration(milliseconds: 250));
          clock.flushMicrotasks();
          expect(h.repo.summaryCalls, hasLength(2));
          expect(h.repo.seriesCalls, hasLength(2));
        }
        expect(h.controller.summary.stale, isTrue);
        expect(h.controller.series.stale, isTrue);

        slowSummary.complete(_summary(marginFilter()));
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 500));
        clock.flushMicrotasks();
        expect(h.repo.summaryCalls, hasLength(2));
        expect(h.repo.seriesCalls, hasLength(2));

        // The other panel must settle before the one queued reconciliation read.
        h.repo.onSummary = null;
        h.repo.onSeries = null;
        unawaited(
          _series(
            marginFilter(),
            ReportGranularity.day,
          ).then(slowSeries.complete),
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 179));
        clock.flushMicrotasks();
        expect(h.repo.summaryCalls, hasLength(2));
        expect(h.repo.seriesCalls, hasLength(2));
        clock.elapse(const Duration(milliseconds: 1));
        clock.flushMicrotasks();
        expect(h.repo.summaryCalls, hasLength(3));
        expect(h.repo.seriesCalls, hasLength(3));
        expect(h.repo.ordersCalls, isEmpty);
        expect(h.controller.summary.value!.data.completedOrderCount, 10);
        expect(h.controller.summary.stale, isFalse);
        expect(h.controller.series.stale, isFalse);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(h.repo.summaryCalls, hasLength(3));
        expect(h.repo.seriesCalls, hasLength(3));
      });
    },
  );

  test(
    'hidden/background reports defer revision refresh until visible and foreground',
    () {
      fakeAsync((clock) {
        final h = _Harness();
        unawaited(h.controller.initialize());
        clock.flushMicrotasks();
        h.controller.setVisible(false);
        h.events.emit('order-1', 'session-1');
        clock.elapse(const Duration(seconds: 2));
        clock.flushMicrotasks();
        expect(h.repo.summaryCalls, hasLength(1));
        expect(h.controller.summary.stale, isTrue);
        h.controller.setForeground(false);
        h.controller.setVisible(true);
        clock.elapse(const Duration(seconds: 2));
        clock.flushMicrotasks();
        expect(h.repo.summaryCalls, hasLength(1));
        h.controller.setForeground(true);
        clock.elapse(const Duration(milliseconds: 180));
        clock.flushMicrotasks();
        expect(h.repo.summaryCalls, hasLength(2));
        expect(h.repo.seriesCalls, hasLength(2));
      });
    },
  );

  test(
    'returning to a loaded report rechecks it even without a local mutation event',
    () {
      fakeAsync((clock) {
        final h = _Harness();
        unawaited(h.controller.initialize());
        clock.flushMicrotasks();
        h.controller.setVisible(false);
        clock.elapse(const Duration(seconds: 1));
        expect(h.repo.summaryCalls, hasLength(1));
        h.controller.setVisible(true);
        clock.elapse(const Duration(milliseconds: 180));
        clock.flushMicrotasks();
        expect(h.repo.summaryCalls, hasLength(2));
        expect(h.repo.seriesCalls, hasLength(2));
      });
    },
  );

  test(
    '409 remains a recoverable panel error rather than a fabricated zero report',
    () async {
      final h = _Harness();
      await h.controller.initialize();
      final previous = h.controller.summary.value;
      const conflict = Failure(
        type: FailureType.conflict,
        code: 'REPORT_COST_DATA_CONFLICT',
        message: 'Cần đối soát snapshot.',
      );
      h.repo.onSummary = (_) async => const Error(conflict);
      await h.controller.loadSummary();
      expect(h.controller.summary.failure, conflict);
      expect(h.controller.summary.value, same(previous));
      expect(h.controller.summary.stale, isTrue);
      expect(
        h
            .controller
            .summary
            .value!
            .data
            .coveredReferenceMarginAmount
            .minorUnits,
        BigInt.from(50000000),
      );
      expect(h.controller.accessFailure, isNull);
      expect(h.controller.series.value, isNotNull);
      h.repo.onSummary = null;
      await h.controller.loadSummary();
      expect(h.controller.summary.failure, isNull);
      expect(h.controller.summary.stale, isFalse);
    },
  );

  test(
    'invalid initial filters never invoke a use case and can be corrected explicitly',
    () async {
      final h = _Harness(initialFilter: marginFilter(currencyCode: 'VNDD'));
      await h.controller.initialize();
      await h.controller.loadSummary();
      await h.controller.loadSeries();
      expect(h.controller.validationError, isNotNull);
      expect(h.repo.summaryCalls, isEmpty);
      expect(h.repo.seriesCalls, isEmpty);
      h.controller.setDraftCurrencyCode('VND');
      await h.controller.applyFilters();
      expect(h.controller.validationError, isNull);
      expect(h.repo.summaryCalls, hasLength(1));
      expect(h.repo.seriesCalls, hasLength(1));
      expect(h.controller.summary.value!.meta.currencyCode, 'VND');
    },
  );

  test(
    'invalid draft dates/currency and orders pagination do not send requests',
    () async {
      final h = _Harness();
      await h.controller.initialize();
      h.controller.setDraftRange(
        const ReportDateRange(
          fromDate: ReportDate(2026, 10, 2),
          toDate: ReportDate(2026, 10, 1),
        ),
      );
      await h.controller.applyFilters();
      expect(h.controller.validationError, isNotNull);
      h.controller.setDraftRange(
        const ReportDateRange(
          fromDate: ReportDate(2025, 1, 1),
          toDate: ReportDate(2026, 10, 1),
        ),
      );
      await h.controller.applyFilters();
      expect(h.controller.validationError, isNotNull);
      h.controller.setDraftRange(marginFilter().range);
      h.controller.setDraftCurrencyCode('VNDD');
      await h.controller.applyFilters();
      expect(h.controller.validationError, isNotNull);
      expect(h.repo.summaryCalls, hasLength(1));
      expect(h.repo.seriesCalls, hasLength(1));
      expect(h.controller.appliedFilter.currencyCode, 'VND');
      await h.controller.setPage(-1);
      expect(h.controller.validationError, isNotNull);
      await h.controller.setPageSize(101);
      expect(h.controller.validationError, isNotNull);
      expect(h.repo.ordersCalls, isEmpty);
    },
  );
}
