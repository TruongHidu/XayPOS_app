import '../../../../core/result/result.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../entities/cashbook_enums.dart';
import '../entities/cashbook_filters.dart';
import '../entities/cashbook_inputs.dart';
import '../entities/cashbook_meta.dart';
import '../entities/cashbook_records.dart';

abstract interface class CashbookRepository {
  Future<Result<List<CashbookCategory>>> getCategories({
    CashbookEntryType? type,
  });

  Future<Result<CashbookEnvelope<ReportPage<CashbookEntry>>>> getEntries(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
  );

  Future<Result<CashbookEnvelope<CashbookSummary>>> getSummary(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
  );

  Future<Result<CashbookEnvelope<List<CashbookSeriesPoint>>>> getSeries(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
    CashbookGranularity granularity,
  );

  Future<Result<CashbookEnvelope<ReportPage<CashbookExpense>>>> getExpenses(
    CashbookRangeFilter range,
    CashbookExpenseFilter filter,
  );

  Future<Result<CashbookExpense>> getExpense(String id);

  Future<Result<ExpenseCreateResult>> createExpense(
    CreateExpenseInput input, {
    required String idempotencyKey,
  });

  Future<Result<CashbookExpense>> voidExpense(
    String id,
    VoidExpenseInput input,
  );

  Future<Result<CashbookEnvelope<ReportPage<CashbookStockReceipt>>>>
  getStockReceipts(CashbookRangeFilter range, CashbookReceiptFilter filter);
}
