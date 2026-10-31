import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_date.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_enums.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_meta.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_order_row.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_page.dart';
import 'package:pos_saas_app/features/reports/domain/use_cases/report_use_cases.dart';
import 'package:pos_saas_app/features/reports/presentation/controllers/daily_report_controller.dart';
import 'package:pos_saas_app/features/reports/presentation/controllers/report_orders_controller.dart';
import 'package:pos_saas_app/features/reports/presentation/controllers/report_summary_controller.dart';
import 'package:pos_saas_app/features/reports/presentation/controllers/top_items_report_controller.dart';

import 'report_fakes.dart';

void main() {
  group('DailyReportController', () {
    late FakeReportRepository repo;
    late DailyReportController controller;

    setUp(() {
      repo = FakeReportRepository();
      controller = DailyReportController(getDailyReport: GetDailyReport(repo));
    });

    test('initial state and successful load', () async {
      expect(controller.isLoading, isFalse);
      expect(controller.data, isNull);

      await controller.load();

      expect(controller.isLoading, isFalse);
      expect(controller.data, isNotNull);
      expect(controller.failure, isNull);
      expect(repo.dailyCalls, 1);
    });

    test('draft filters commit on applyFilters', () async {
      final targetDate = const ReportDate(2026, 10, 10);
      controller.setDraftDate(targetDate);
      controller.setDraftServiceType(ServiceType.takeaway);
      controller.setDraftSourceChannel(ReportSourceChannel.cashier);
      controller.setDraftCurrencyCode('USD');

      // Before applying
      expect(controller.appliedFilter.date, isNull);

      await controller.applyFilters();

      expect(controller.appliedFilter.date, targetDate);
      expect(controller.appliedFilter.serviceType, ServiceType.takeaway);
      expect(
        controller.appliedFilter.sourceChannel,
        ReportSourceChannel.cashier,
      );
      expect(controller.appliedFilter.currencyCode, 'USD');
      expect(repo.lastDailyFilter?.date, targetDate);
    });

    test('handles failure without crashing', () async {
      repo.dailyReportResult = const Error(
        Failure(type: FailureType.validation, message: 'Invalid date'),
      );

      await controller.load();

      expect(controller.isLoading, isFalse);
      expect(controller.data, isNull);
      expect(controller.failure, isNotNull);
      expect(controller.failure?.message, 'Invalid date');
    });

    test(
      'refresh maintains previous data while isRefreshing is true',
      () async {
        await controller.load();
        expect(controller.data, isNotNull);

        final future = controller.refresh();
        expect(controller.isRefreshing, isTrue);
        expect(controller.data, isNotNull); // still visible

        await future;
        expect(controller.isRefreshing, isFalse);
      },
    );
  });

  group('ReportSummaryController', () {
    late FakeReportRepository repo;
    late ReportSummaryController controller;

    setUp(() {
      repo = FakeReportRepository();
      controller = ReportSummaryController(
        getReportSummary: GetReportSummary(repo),
        getRevenueSeries: GetRevenueSeries(repo),
        getPaymentMethodReport: GetPaymentMethodReport(repo),
      );
    });

    test('loads 3 panels in parallel', () async {
      await controller.applyFilters();

      expect(controller.summaryData, isNotNull);
      expect(controller.seriesData, isNotNull);
      expect(controller.paymentsData, isNotNull);
      expect(repo.summaryCalls, 1);
      expect(repo.seriesCalls, 1);
      expect(repo.paymentsCalls, 1);
    });

    test('supports independent panel failure and retry', () async {
      repo.revenueSeriesResult = const Error(
        Failure(type: FailureType.network, message: 'Series failed'),
      );

      await controller.applyFilters();

      expect(controller.summaryData, isNotNull);
      expect(controller.paymentsData, isNotNull);
      expect(controller.seriesData, isNull);
      expect(controller.seriesFailure?.message, 'Series failed');

      // Retry series only
      repo.revenueSeriesResult = Success(
        ReportEnvelope(meta: testReportMeta(), data: testRevenueSeries()),
      );

      await controller.retrySeries();

      expect(controller.seriesData, isNotNull);
      expect(controller.seriesFailure, isNull);
      expect(repo.summaryCalls, 1); // unchanged
      expect(repo.seriesCalls, 2); // retried
    });

    test('changing granularity only reloads series', () async {
      await controller.applyFilters();
      expect(repo.seriesCalls, 1);

      controller.setGranularity(ReportGranularity.month);
      await Future.delayed(Duration.zero);

      expect(controller.granularity, ReportGranularity.month);
      expect(repo.seriesCalls, 2);
      expect(repo.summaryCalls, 1); // summary not reloaded
      expect(repo.paymentsCalls, 1); // payments not reloaded
    });

    test('legend toggle does not allow hiding both series', () {
      expect(controller.showCollectedSeries, isTrue);
      expect(controller.showCompletedSeries, isTrue);

      controller.toggleShowCollected();
      expect(controller.showCollectedSeries, isFalse);
      expect(controller.showCompletedSeries, isTrue);

      // Attempting to toggle completed while collected is hidden must keep completed visible
      controller.toggleShowCompleted();
      expect(controller.showCompletedSeries, isTrue);
    });
  });

  group('TopItemsReportController', () {
    late FakeReportRepository repo;
    late TopItemsReportController controller;

    setUp(() {
      repo = FakeReportRepository();
      controller = TopItemsReportController(
        getTopItemsReport: GetTopItemsReport(repo),
      );
    });

    test('loads top items page', () async {
      await controller.load();
      expect(controller.data, isNotNull);
      expect(controller.data?.data.content.length, 2);
      expect(repo.topItemsCalls, 1);
    });

    test('changing sort or direction or size resets page to 0', () async {
      controller.setPage(3);
      expect(controller.filter.page, 3);

      controller.setSortBy(TopItemSortBy.quantity);
      expect(controller.filter.page, 0);
      expect(controller.filter.sortBy, TopItemSortBy.quantity);

      controller.setPage(2);
      controller.toggleSortDirection();
      expect(controller.filter.page, 0);
      expect(controller.filter.direction, ReportSortDirection.asc);

      controller.setPage(2);
      controller.setSize(50);
      expect(controller.filter.page, 0);
      expect(controller.filter.size, 50);
    });
  });

  group('ReportOrdersController', () {
    late FakeReportRepository repo;
    late ReportOrdersController controller;

    setUp(() {
      repo = FakeReportRepository();
      controller = ReportOrdersController(
        getReportOrders: GetReportOrders(repo),
      );
    });

    test('loads reconciliation orders', () async {
      await controller.load();
      expect(controller.data, isNotNull);
      expect(controller.data?.data.content.length, 2);
      expect(repo.ordersCalls, 1);
    });

    test('loadMore grows the list and a refresh keeps those pages', () async {
      await controller.load();
      final first = controller.data!;
      repo.reportOrdersResult = Success(
        ReportEnvelope(
          meta: first.meta,
          data: ReportPage(
            content: first.data.content,
            page: 0,
            size: 2,
            totalElements: 4,
            totalPages: 2,
          ),
        ),
      );
      await controller.load();
      repo.ordersCalls = 0;

      await controller.loadMore();
      expect(controller.filter.page, 1);
      expect(controller.data?.data.hasNextPage, isFalse);
      expect(controller.data?.data.content.length, 2); // Shifted rows collapse.
      expect(repo.ordersCalls, 1);

      await controller.refresh();
      expect(repo.ordersCalls, 3);
      expect(controller.filter.page, 1);
    });

    test('a failed next page keeps the rows and can be retried', () async {
      await controller.load();
      final first = controller.data!;
      final twoPages = Success<ReportEnvelope<ReportPage<ReportOrderRow>>>(
        ReportEnvelope(
          meta: first.meta,
          data: ReportPage(
            content: first.data.content,
            page: 0,
            size: 2,
            totalElements: 4,
            totalPages: 2,
          ),
        ),
      );
      repo.reportOrdersResult = twoPages;
      await controller.load();
      repo.reportOrdersResult = const Error(
        Failure(type: FailureType.network, message: 'offline'),
      );

      await controller.loadMore();
      expect(controller.loadMoreFailure?.message, 'offline');
      expect(controller.failure, isNull);
      expect(controller.data?.data.content.length, 2);
      expect(controller.filter.page, 0);

      repo.reportOrdersResult = twoPages;
      await controller.loadMore();
      expect(controller.loadMoreFailure, isNull);
      expect(controller.filter.page, 1);
    });

    test(
      'dateBasis change to completed/cancelled clears conflicting status',
      () {
        controller.setStatus(OrderStatus.open);
        expect(controller.filter.status, OrderStatus.open);

        controller.setDateBasis(ReportDateBasis.completed);
        expect(controller.filter.dateBasis, ReportDateBasis.completed);
        expect(controller.filter.status, isNull); // cleared conflict
        expect(controller.filter.page, 0); // reset page
      },
    );

    test('PAID dateBasis does not auto-add paymentStatus=PAID', () {
      controller.setDateBasis(ReportDateBasis.paid);
      expect(controller.filter.dateBasis, ReportDateBasis.paid);
      expect(controller.filter.paymentStatus, isNull);
    });
  });
}
