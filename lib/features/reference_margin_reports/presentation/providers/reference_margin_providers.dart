import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart'
    show apiClientsProvider, authControllerProvider;
import '../../../../core/auth/access_policy.dart';
import '../../../order/presentation/providers/order_providers.dart'
    show orderEventsProvider;
import '../../data/data_sources/reference_margin_remote_data_source.dart';
import '../../data/repositories/reference_margin_repository_impl.dart';
import '../../domain/repositories/reference_margin_repository.dart';
import '../../domain/use_cases/reference_margin_use_cases.dart';
import '../controllers/reference_margin_reports_controller.dart';

final referenceMarginScopeProvider = authControllerProvider.select(
  (auth) => AccessPolicy.referenceMarginScope(auth.state.session),
);
final referenceMarginRouteObserverProvider = Provider(
  (ref) => RouteObserver<ModalRoute<void>>(),
);
final referenceMarginRepositoryProvider = Provider<ReferenceMarginRepository>(
  (ref) => ReferenceMarginRepositoryImpl(
    ReferenceMarginRemoteDataSource(
      ref.watch(apiClientsProvider).authenticated,
    ),
  ),
);
final referenceMarginReportsProvider =
    ChangeNotifierProvider.autoDispose<ReferenceMarginReportsController>((ref) {
      ref.watch(referenceMarginScopeProvider);
      final auth = ref.read(authControllerProvider);
      final repository = ref.watch(referenceMarginRepositoryProvider);
      final controller = ReferenceMarginReportsController(
        session: () => auth.state.session,
        getSummary: GetReferenceMarginSummary(repository),
        getSeries: GetReferenceMarginSeries(repository),
        getOrders: GetReferenceMarginOrders(repository),
        events: ref.read(orderEventsProvider),
        onAccessDenied: (_) => auth.revalidateAccess(),
      );
      controller.setForeground(
        WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
      unawaited(Future.microtask(controller.initialize));
      return controller;
    });
