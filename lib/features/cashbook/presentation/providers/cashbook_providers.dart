import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart'
    show apiClientsProvider, authControllerProvider;
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../order/presentation/providers/order_providers.dart'
    show orderEventsProvider;
import '../../data/cashbook_key_generator.dart';
import '../../data/data_sources/cashbook_remote_data_source.dart';
import '../../data/repositories/cashbook_repository_impl.dart';
import '../../domain/entities/cashbook_inputs.dart';
import '../../domain/entities/cashbook_records.dart';
import '../../domain/repositories/cashbook_repository.dart';
import '../../domain/use_cases/cashbook_use_cases.dart';
import '../controllers/cashbook_flow_controller.dart';
import '../controllers/cashbook_range_controller.dart';
import '../controllers/expense_actions_controller.dart';

final cashbookScopeProvider = authControllerProvider.select(
  (auth) => AccessPolicy.cashbookScope(auth.state.session),
);

final cashbookRepositoryProvider = Provider<CashbookRepository>(
  (ref) => CashbookRepositoryImpl(
    CashbookRemoteDataSource(ref.watch(apiClientsProvider).authenticated),
  ),
);

final cashbookKeyGeneratorProvider = Provider<CashbookKeyGenerator>(
  (ref) => SecureCashbookKeyGenerator(),
);

/// Signals that a voucher was created or voided; every opened tab rereads.
class CashbookChanges extends ChangeNotifier {
  void notifyChanged() => notifyListeners();
}

final cashbookChangesProvider = ChangeNotifierProvider.autoDispose((ref) {
  ref.watch(cashbookScopeProvider);
  return CashbookChanges();
});

final cashbookRangeProvider =
    ChangeNotifierProvider.autoDispose<CashbookRangeController>((ref) {
      ref.watch(cashbookScopeProvider);
      return CashbookRangeController();
    });

/// Every expense and income category, active or not, for filters and forms.
final cashbookCategoriesProvider =
    FutureProvider.autoDispose<List<CashbookCategory>>((ref) async {
      ref.watch(cashbookScopeProvider);
      final result = await GetCashbookCategories(
        ref.watch(cashbookRepositoryProvider),
      )();
      return switch (result) {
        Success(:final value) => value,
        Error(:final failure) => throw failure,
      };
    });

Future<void> Function(Failure) _revalidate(Ref ref) {
  final auth = ref.read(authControllerProvider);
  return (_) => auth.revalidateAccess();
}

final cashbookFlowProvider =
    ChangeNotifierProvider.autoDispose<CashbookFlowController>((ref) {
      ref.watch(cashbookScopeProvider);
      final auth = ref.read(authControllerProvider);
      final repository = ref.watch(cashbookRepositoryProvider);
      final range = ref.watch(cashbookRangeProvider.notifier);
      final controller = CashbookFlowController(
        session: () => auth.state.session,
        range: range.applied,
        getSummary: GetCashbookSummary(repository),
        getSeries: GetCashbookSeries(repository),
        getEntries: GetCashbookEntries(repository),
        onAccessDenied: _revalidate(ref),
        onMeta: range.reportMeta,
        changes: ref.watch(cashbookChangesProvider.notifier),
        paymentEvents: ref.read(orderEventsProvider),
      );
      ref.listen(
        cashbookRangeProvider.select((c) => c.applied),
        (_, next) => controller.setRange(next),
      );
      return controller;
    });

final expenseSubmitProvider =
    ChangeNotifierProvider.autoDispose<ExpenseSubmitController>((ref) {
      ref.watch(cashbookScopeProvider);
      final repository = ref.watch(cashbookRepositoryProvider);
      return ExpenseSubmitController(
        create: CreateCashbookExpense(repository),
        keys: ref.watch(cashbookKeyGeneratorProvider),
      );
    });
