import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/cashbook/domain/entities/cashbook_enums.dart';
import 'package:pos_saas_app/features/cashbook/domain/entities/cashbook_filters.dart';
import 'package:pos_saas_app/features/cashbook/domain/entities/cashbook_inputs.dart';
import 'package:pos_saas_app/features/cashbook/domain/entities/cashbook_meta.dart';
import 'package:pos_saas_app/features/cashbook/domain/entities/cashbook_records.dart';
import 'package:pos_saas_app/features/cashbook/domain/repositories/cashbook_repository.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_money.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_page.dart';

const cashbookPermissions = {
  'CASHBOOK_VIEW',
  'CASHBOOK_CREATE',
  'CASHBOOK_VOID',
  'INVENTORY_VIEW',
  'ORDER_VIEW',
};
const cashbookFeatures = {
  'DETAIL_REPORT',
  'INVENTORY_MANAGEMENT',
  'ORDER_MANAGEMENT',
};

ReportMoney money(int major) =>
    ReportMoney(BigInt.from(major) * BigInt.from(100));

CashbookMeta testCashbookMeta(
  CashbookRangeFilter range, {
  String dateBasis = 'CASH_OCCURRED_AT',
  CashbookGranularity? granularity,
}) => CashbookMeta(
  fromDate: range.range.fromDate,
  toDate: range.range.toDate,
  timezone: 'Asia/Ho_Chi_Minh',
  currencyCode: range.currencyCode ?? 'VND',
  dateBasis: dateBasis,
  generatedAt: DateTime.utc(2026, 10, 29, 3),
  granularity: granularity,
);

ReportPage<T> testPage<T>(List<T> content, {int page = 0, int size = 20}) =>
    ReportPage(
      content: content,
      page: page,
      size: size,
      totalElements: content.length + page * size,
      totalPages: content.isEmpty && page == 0 ? 0 : page + 1,
    );

CashbookEntry testEntry({
  CashbookSourceType sourceType = CashbookSourceType.orderPayment,
  String sourceId = 'payment-1',
  CashbookEntryType type = CashbookEntryType.income,
  int amount = 1000000,
  String? code,
}) => CashbookEntry(
  sourceType: sourceType,
  sourceId: sourceId,
  code:
      code ??
      (sourceType == CashbookSourceType.orderPayment ? 'PAY-001' : 'EXP-001'),
  type: type,
  categoryCode: type == CashbookEntryType.income
      ? 'SALES_COLLECTION'
      : 'UTILITIES',
  categoryName: type == CashbookEntryType.income ? 'Thu bán hàng' : 'Điện nước',
  amount: money(amount),
  currencyCode: 'VND',
  paymentMethod: CashbookPaymentMethod.cash,
  occurredAt: DateTime.utc(2026, 10, 28, 5),
  recordedAt: DateTime.utc(2026, 10, 28, 5),
  orderId: sourceType == CashbookSourceType.orderPayment ? 'order-1' : null,
  orderCode: sourceType == CashbookSourceType.orderPayment ? 'ORD-001' : null,
);

CashbookExpense testExpense({
  String id = 'expense-1',
  CashbookExpenseStatus status = CashbookExpenseStatus.posted,
  int version = 0,
  int amount = 400000,
}) => CashbookExpense(
  id: id,
  expenseCode: 'EXP-$id',
  categoryCode: 'INGREDIENT_PURCHASE',
  categoryName: 'Chi mua nguyên liệu',
  amount: money(amount),
  currencyCode: 'VND',
  paymentMethod: CashbookPaymentMethod.transfer,
  expenseAt: DateTime.utc(2026, 10, 29, 3, 30),
  status: status,
  createdAt: DateTime.utc(2026, 10, 29, 4),
  updatedAt: DateTime.utc(2026, 10, 29, 4),
  version: version,
  payeeName: 'Nhà cung cấp A',
  createdBy: 'user-1',
  voidedBy: status == CashbookExpenseStatus.voided ? 'user-1' : null,
  voidedAt: status == CashbookExpenseStatus.voided
      ? DateTime.utc(2026, 10, 29, 5)
      : null,
  voidReason: status == CashbookExpenseStatus.voided ? 'Ghi nhầm' : null,
);

CashbookStockReceipt testReceipt({
  String id = 'receipt-1',
  bool unknown = false,
}) => CashbookStockReceipt(
  stockDocumentId: id,
  documentCode: 'PN-$id',
  warehouseId: 'warehouse-1',
  warehouseName: 'Kho chính',
  confirmedAt: DateTime.utc(2026, 10, 10, 2),
  totalCost: money(1500000),
  currencyCode: unknown ? null : 'VND',
  currencyStatus: unknown
      ? CashbookCurrencyStatus.unknown
      : CashbookCurrencyStatus.known,
  linkedPostedExpenseCount: unknown ? 0 : 1,
  recordedExpenseAmountAllTime: unknown ? null : money(400000),
);

CashbookSummary testSummary() => CashbookSummary(
  totalIncomeAmount: money(1000000),
  totalExpenseAmount: money(500000),
  netCashFlowAmount: money(500000),
  incomeEntryCount: 1,
  expenseEntryCount: 2,
  saleIncomeAmount: money(1000000),
  receiptLinkedExpenseAmount: money(400000),
  otherExpenseAmount: money(100000),
);

class SequenceKeys implements CashbookKeyGenerator {
  int _next = 0;
  @override
  String next() => 'key-${++_next}';
}

class FakeCashbookRepository implements CashbookRepository {
  List<CashbookCategory> categories = const [
    CashbookCategory(
      id: 'c1',
      code: 'SALES_COLLECTION',
      name: 'Thu bán hàng',
      type: CashbookEntryType.income,
      active: true,
    ),
    CashbookCategory(
      id: 'c2',
      code: 'INGREDIENT_PURCHASE',
      name: 'Chi mua nguyên liệu',
      type: CashbookEntryType.expense,
      active: true,
    ),
    CashbookCategory(
      id: 'c3',
      code: 'UTILITIES',
      name: 'Điện nước',
      type: CashbookEntryType.expense,
      active: true,
    ),
  ];
  List<CashbookEntry> entries = [
    testEntry(),
    testEntry(
      sourceType: CashbookSourceType.expenseVoucher,
      sourceId: 'expense-1',
      type: CashbookEntryType.expense,
      amount: 100000,
    ),
  ];
  List<CashbookExpense> expenses = [
    testExpense(),
    testExpense(id: 'expense-2', status: CashbookExpenseStatus.voided),
  ];
  List<CashbookStockReceipt> receipts = [testReceipt()];
  Result<CashbookExpense>? expenseResult;
  Result<ExpenseCreateResult>? createResult;
  Result<CashbookExpense>? voidResult;
  Result<CashbookEnvelope<CashbookSummary>>? summaryResult;

  final summaryCalls = <(CashbookRangeFilter, CashbookEntryFilter)>[];
  final seriesCalls = <(CashbookRangeFilter, CashbookEntryFilter)>[];
  final entryCalls = <(CashbookRangeFilter, CashbookEntryFilter)>[];
  final expenseCalls = <(CashbookRangeFilter, CashbookExpenseFilter)>[];
  final createKeys = <String>[];
  final voidInputs = <VoidExpenseInput>[];
  int expenseLoads = 0;

  @override
  Future<Result<List<CashbookCategory>>> getCategories({
    CashbookEntryType? type,
  }) async => Success(categories);

  @override
  Future<Result<CashbookEnvelope<ReportPage<CashbookEntry>>>> getEntries(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
  ) async {
    entryCalls.add((range, filter));
    return Success(
      CashbookEnvelope(
        meta: testCashbookMeta(range),
        data: testPage(entries, page: filter.page, size: filter.size),
      ),
    );
  }

  @override
  Future<Result<CashbookEnvelope<CashbookSummary>>> getSummary(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
  ) async {
    summaryCalls.add((range, filter));
    return summaryResult ??
        Success(
          CashbookEnvelope(meta: testCashbookMeta(range), data: testSummary()),
        );
  }

  @override
  Future<Result<CashbookEnvelope<List<CashbookSeriesPoint>>>> getSeries(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
    CashbookGranularity granularity,
  ) async {
    seriesCalls.add((range, filter));
    return Success(
      CashbookEnvelope(
        meta: testCashbookMeta(range, granularity: granularity),
        data: [
          CashbookSeriesPoint(
            bucketStartDate: range.range.fromDate,
            totalIncomeAmount: money(1000000),
            totalExpenseAmount: money(500000),
            netCashFlowAmount: money(500000),
            incomeEntryCount: 1,
            expenseEntryCount: 2,
          ),
        ],
      ),
    );
  }

  @override
  Future<Result<CashbookEnvelope<ReportPage<CashbookExpense>>>> getExpenses(
    CashbookRangeFilter range,
    CashbookExpenseFilter filter,
  ) async {
    expenseCalls.add((range, filter));
    final rows = [
      for (final e in expenses)
        if (filter.status == null || e.status == filter.status) e,
    ];
    return Success(
      CashbookEnvelope(
        meta: testCashbookMeta(range, dateBasis: 'EXPENSE_AT'),
        data: testPage(rows, page: filter.page, size: filter.size),
      ),
    );
  }

  @override
  Future<Result<CashbookExpense>> getExpense(String id) async {
    expenseLoads++;
    return expenseResult ?? Success(expenses.firstWhere((e) => e.id == id));
  }

  @override
  Future<Result<ExpenseCreateResult>> createExpense(
    CreateExpenseInput input, {
    required String idempotencyKey,
  }) async {
    createKeys.add(idempotencyKey);
    return createResult ??
        Success(ExpenseCreateResult(expense: testExpense(), replayed: false));
  }

  @override
  Future<Result<CashbookExpense>> voidExpense(
    String id,
    VoidExpenseInput input,
  ) async {
    voidInputs.add(input);
    return voidResult ??
        Success(testExpense(id: id, status: CashbookExpenseStatus.voided));
  }

  @override
  Future<Result<CashbookEnvelope<ReportPage<CashbookStockReceipt>>>>
  getStockReceipts(
    CashbookRangeFilter range,
    CashbookReceiptFilter filter,
  ) async => Success(
    CashbookEnvelope(
      meta: testCashbookMeta(range, dateBasis: 'CONFIRMED_AT'),
      data: testPage(receipts, page: filter.page, size: filter.size),
    ),
  );
}
