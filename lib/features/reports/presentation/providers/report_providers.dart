import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../data/data_sources/report_remote_data_source.dart';
import '../../data/repositories/report_repository_impl.dart';
import '../../domain/repositories/report_repository.dart';
import '../../domain/use_cases/report_use_cases.dart';
import '../controllers/daily_report_controller.dart';
import '../controllers/report_orders_controller.dart';
import '../controllers/report_summary_controller.dart';
import '../controllers/top_items_report_controller.dart';

final reportRemoteDataSourceProvider = Provider<ReportRemoteDataSource>((ref) {
  return ReportRemoteDataSource(ref.watch(apiClientsProvider).authenticated);
});

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepositoryImpl(ref.watch(reportRemoteDataSourceProvider));
});

// Use Cases
final getDailyReportUseCaseProvider = Provider<GetDailyReport>((ref) {
  return GetDailyReport(ref.watch(reportRepositoryProvider));
});

final getReportSummaryUseCaseProvider = Provider<GetReportSummary>((ref) {
  return GetReportSummary(ref.watch(reportRepositoryProvider));
});

final getRevenueSeriesUseCaseProvider = Provider<GetRevenueSeries>((ref) {
  return GetRevenueSeries(ref.watch(reportRepositoryProvider));
});

final getPaymentMethodReportUseCaseProvider = Provider<GetPaymentMethodReport>((
  ref,
) {
  return GetPaymentMethodReport(ref.watch(reportRepositoryProvider));
});

final getTopItemsReportUseCaseProvider = Provider<GetTopItemsReport>((ref) {
  return GetTopItemsReport(ref.watch(reportRepositoryProvider));
});

final getReportOrdersUseCaseProvider = Provider<GetReportOrders>((ref) {
  return GetReportOrders(ref.watch(reportRepositoryProvider));
});

// Scope tracking provider
final reportScopeProvider = Provider<Object?>((ref) {
  final session = ref.watch(authControllerProvider).state.session;
  return AccessPolicy.reportScope(session);
});

// Controllers
final dailyReportControllerProvider =
    ChangeNotifierProvider.autoDispose<DailyReportController>((ref) {
      // Invalidate controller when reportScope changes
      ref.watch(reportScopeProvider);

      final controller = DailyReportController(
        getDailyReport: ref.watch(getDailyReportUseCaseProvider),
      );

      // Initial load
      Future.microtask(controller.load);
      return controller;
    });

final reportSummaryControllerProvider =
    ChangeNotifierProvider.autoDispose<ReportSummaryController>((ref) {
      ref.watch(reportScopeProvider);

      final controller = ReportSummaryController(
        getReportSummary: ref.watch(getReportSummaryUseCaseProvider),
        getRevenueSeries: ref.watch(getRevenueSeriesUseCaseProvider),
        getPaymentMethodReport: ref.watch(
          getPaymentMethodReportUseCaseProvider,
        ),
      );

      Future.microtask(controller.applyFilters);
      return controller;
    });

final topItemsReportControllerProvider =
    ChangeNotifierProvider.autoDispose<TopItemsReportController>((ref) {
      ref.watch(reportScopeProvider);

      final controller = TopItemsReportController(
        getTopItemsReport: ref.watch(getTopItemsReportUseCaseProvider),
      );

      return controller;
    });

final reportOrdersControllerProvider =
    ChangeNotifierProvider.autoDispose<ReportOrdersController>((ref) {
      ref.watch(reportScopeProvider);

      final controller = ReportOrdersController(
        getReportOrders: ref.watch(getReportOrdersUseCaseProvider),
      );

      return controller;
    });
