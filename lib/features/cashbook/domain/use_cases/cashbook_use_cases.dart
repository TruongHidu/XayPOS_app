import '../../../../core/result/result.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../entities/cashbook_enums.dart';
import '../entities/cashbook_filters.dart';
import '../entities/cashbook_inputs.dart';
import '../entities/cashbook_meta.dart';
import '../entities/cashbook_records.dart';
import '../repositories/cashbook_repository.dart';

class GetCashbookCategories {
  const GetCashbookCategories(this.repository);
  final CashbookRepository repository;
  Future<Result<List<CashbookCategory>>> call({CashbookEntryType? type}) =>
      repository.getCategories(type: type);
}

class GetCashbookEntries {
  const GetCashbookEntries(this.repository);
  final CashbookRepository repository;
  Future<Result<CashbookEnvelope<ReportPage<CashbookEntry>>>> call(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
  ) => repository.getEntries(range, filter);
}

class GetCashbookSummary {
  const GetCashbookSummary(this.repository);
  final CashbookRepository repository;
  Future<Result<CashbookEnvelope<CashbookSummary>>> call(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
  ) => repository.getSummary(range, filter);
}

class GetCashbookSeries {
  const GetCashbookSeries(this.repository);
  final CashbookRepository repository;
  Future<Result<CashbookEnvelope<List<CashbookSeriesPoint>>>> call(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
    CashbookGranularity granularity,
  ) => repository.getSeries(range, filter, granularity);
}

class GetCashbookExpenses {
  const GetCashbookExpenses(this.repository);
  final CashbookRepository repository;
  Future<Result<CashbookEnvelope<ReportPage<CashbookExpense>>>> call(
    CashbookRangeFilter range,
    CashbookExpenseFilter filter,
  ) => repository.getExpenses(range, filter);
}

class GetCashbookExpense {
  const GetCashbookExpense(this.repository);
  final CashbookRepository repository;
  Future<Result<CashbookExpense>> call(String id) => repository.getExpense(id);
}

class CreateCashbookExpense {
  const CreateCashbookExpense(this.repository);
  final CashbookRepository repository;
  Future<Result<ExpenseCreateResult>> call(
    CreateExpenseInput input, {
    required String idempotencyKey,
  }) => repository.createExpense(input, idempotencyKey: idempotencyKey);
}

class VoidCashbookExpense {
  const VoidCashbookExpense(this.repository);
  final CashbookRepository repository;
  Future<Result<CashbookExpense>> call(String id, VoidExpenseInput input) =>
      repository.voidExpense(id, input);
}

class GetCashbookStockReceipts {
  const GetCashbookStockReceipts(this.repository);
  final CashbookRepository repository;
  Future<Result<CashbookEnvelope<ReportPage<CashbookStockReceipt>>>> call(
    CashbookRangeFilter range,
    CashbookReceiptFilter filter,
  ) => repository.getStockReceipts(range, filter);
}
