import '../../../../core/result/result.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/cashbook_enums.dart';
import '../../domain/entities/cashbook_filters.dart';
import '../../domain/entities/cashbook_inputs.dart';
import '../../domain/entities/cashbook_meta.dart';
import '../../domain/entities/cashbook_records.dart';
import '../../domain/repositories/cashbook_repository.dart';
import '../data_sources/cashbook_remote_data_source.dart';
import 'cashbook_result.dart';

class CashbookRepositoryImpl implements CashbookRepository {
  const CashbookRepositoryImpl(this.remote);
  final CashbookRemoteDataSource remote;

  @override
  Future<Result<List<CashbookCategory>>> getCategories({
    CashbookEntryType? type,
  }) => cashbookResult(() => remote.getCategories(type: type));

  @override
  Future<Result<CashbookEnvelope<ReportPage<CashbookEntry>>>> getEntries(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
  ) => cashbookResult(
    () => remote.getEntries(range, filter),
    validation: range.validate(),
  );

  @override
  Future<Result<CashbookEnvelope<CashbookSummary>>> getSummary(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
  ) => cashbookResult(
    () => remote.getSummary(range, filter),
    validation: range.validate(),
  );

  @override
  Future<Result<CashbookEnvelope<List<CashbookSeriesPoint>>>> getSeries(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
    CashbookGranularity granularity,
  ) => cashbookResult(
    () => remote.getSeries(range, filter, granularity),
    validation: range.validate(),
  );

  @override
  Future<Result<CashbookEnvelope<ReportPage<CashbookExpense>>>> getExpenses(
    CashbookRangeFilter range,
    CashbookExpenseFilter filter,
  ) => cashbookResult(
    () => remote.getExpenses(range, filter),
    validation: range.validate(),
  );

  @override
  Future<Result<CashbookExpense>> getExpense(String id) =>
      cashbookResult(() => remote.getExpense(id));

  @override
  Future<Result<ExpenseCreateResult>> createExpense(
    CreateExpenseInput input, {
    required String idempotencyKey,
  }) => cashbookResult(
    () => remote.createExpense(input, idempotencyKey: idempotencyKey),
  );

  @override
  Future<Result<CashbookExpense>> voidExpense(
    String id,
    VoidExpenseInput input,
  ) => cashbookResult(() => remote.voidExpense(id, input));

  @override
  Future<Result<CashbookEnvelope<ReportPage<CashbookStockReceipt>>>>
  getStockReceipts(CashbookRangeFilter range, CashbookReceiptFilter filter) =>
      cashbookResult(
        () => remote.getStockReceipts(range, filter),
        validation: range.validate(),
      );
}
