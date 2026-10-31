import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/exact_json.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/cashbook/data/dto/cashbook_dto.dart';
import 'package:pos_saas_app/features/cashbook/data/dto/cashbook_requests.dart';
import 'package:pos_saas_app/features/cashbook/data/repositories/cashbook_result.dart';
import 'package:pos_saas_app/features/cashbook/domain/entities/cashbook_enums.dart';
import 'package:pos_saas_app/features/cashbook/domain/entities/cashbook_filters.dart';
import 'package:pos_saas_app/features/cashbook/domain/entities/cashbook_inputs.dart';
import 'package:pos_saas_app/features/cashbook/domain/policies/expense_validation.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_date.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_money.dart';

const _meta = '''
"meta":{"fromDate":"2026-10-01","toDate":"2026-10-29","timezone":"Asia/Ho_Chi_Minh",
"currencyCode":"VND","dateBasis":"CASH_OCCURRED_AT","granularity":null,
"generatedAt":"2026-10-29T03:00:00Z"}''';

void main() {
  group('CashbookDto', () {
    test('parses entries with exact decimals and a two-source row key', () {
      final raw = decodeExactJson(
        '''
{$_meta,"data":{"content":[{"sourceType":"EXPENSE_VOUCHER","sourceId":"a1",
"code":"EXP-1","type":"EXPENSE","categoryCode":"UTILITIES","categoryName":"Điện nước",
"amount":12345678901234.55,"currencyCode":"VND","paymentMethod":"TRANSFER",
"occurredAt":"2026-10-28T05:00:00Z","recordedAt":"2026-10-29T01:00:00Z",
"createdBy":"u1","orderId":null,"orderCode":null,"stockDocumentId":null,
"sourceDocumentCode":null}],"page":0,"size":20,"totalElements":1,"totalPages":1}}''',
      );
      final page = CashbookDto.entries(raw);
      final entry = page.data.content.single;
      expect(entry.amount.minorUnits, BigInt.parse('1234567890123455'));
      expect(entry.rowKey, 'EXPENSE_VOUCHER:a1');
      expect(page.meta.timezone, 'Asia/Ho_Chi_Minh');
    });

    test('summary rejects a missing amount instead of reading zero', () {
      final raw = decodeExactJson('''
{$_meta,"data":{"totalIncomeAmount":1000000,"totalExpenseAmount":500000,
"incomeEntryCount":1,"expenseEntryCount":2,"saleIncomeAmount":1000000,
"receiptLinkedExpenseAmount":400000,"otherExpenseAmount":100000}}''');
      expect(() => CashbookDto.summary(raw), throwsFormatException);
    });

    test('unknown-currency receipts carry no recorded amount', () {
      final raw = decodeExactJson(
        '''
{"stockDocumentId":"d1","documentCode":"PN-1","warehouseId":"w1","warehouseName":"Kho",
"confirmedAt":"2026-10-10T02:00:00Z","totalCost":1500000,"currencyCode":null,
"currencyStatus":"UNKNOWN","linkedPostedExpenseCount":0,"recordedExpenseAmountAllTime":null}''',
      );
      final receipt = CashbookDto.receipt(raw);
      expect(receipt.currencyUnknown, isTrue);
      expect(receipt.recordedExpenseAmountAllTime, isNull);
    });

    test('expense keeps void metadata and version', () {
      final raw = decodeExactJson('''
{"id":"e1","expenseCode":"EXP-1","categoryCode":"RENT","categoryName":"Thuê mặt bằng",
"amount":400000.00,"currencyCode":"VND","paymentMethod":"CASH","expenseAt":"2026-10-29T03:30:00Z",
"stockDocumentId":null,"sourceDocumentCode":null,"sourceCurrencyStatus":null,"referenceNo":null,
"payeeName":"Chủ nhà","note":null,"status":"VOIDED","createdBy":"u1",
"createdAt":"2026-10-29T04:00:00Z","updatedAt":"2026-10-29T05:00:00Z","version":1,
"voidedBy":"u1","voidedAt":"2026-10-29T05:00:00Z","voidReason":"Ghi nhầm"}''');
      final expense = CashbookDto.expense(raw);
      expect(expense.isVoided, isTrue);
      expect(expense.version, 1);
      expect(expense.voidReason, 'Ghi nhầm');
    });
  });

  group('CashbookRequests', () {
    final range = CashbookRangeFilter(
      range: ReportDateRange(
        fromDate: const ReportDate(2026, 10, 1),
        toDate: const ReportDate(2026, 10, 29),
      ),
    );

    test('summary uses the entry criteria without paging or sorting', () {
      const filter = CashbookEntryFilter(
        type: CashbookEntryType.expense,
        q: '  điện ',
        page: 3,
      );
      final query = CashbookRequests.flow(range, filter);
      expect(query, {
        'fromDate': '2026-10-01',
        'toDate': '2026-10-29',
        'type': 'EXPENSE',
        'q': 'điện',
      });
      expect(CashbookRequests.entries(range, filter)['page'], 3);
    });

    test('create body keeps cents exact and sends UTC', () {
      final body = CashbookRequests.create(
        CreateExpenseInput(
          categoryCode: 'INGREDIENT_PURCHASE',
          amount: ReportMoney(BigInt.from(40000050)),
          paymentMethod: CashbookPaymentMethod.transfer,
          expenseAt: DateTime.utc(2026, 10, 29, 3, 30),
          stockDocumentId: 'd1',
          referenceNo: ' ',
        ),
      );
      expect(body['amount'], '400000.50');
      expect(body['expenseAt'], '2026-10-29T03:30:00.000Z');
      expect(body.containsKey('referenceNo'), isFalse);
    });
  });

  group('expense validation', () {
    test('parses Vietnamese amount notation', () {
      expect(
        parseExpenseAmount('1.250.000').value,
        ReportMoney(BigInt.from(125000000)),
      );
      expect(parseExpenseAmount('12,5').value, ReportMoney(BigInt.from(1250)));
      expect(parseExpenseAmount('12.50').value, ReportMoney(BigInt.from(1250)));
      expect(parseExpenseAmount('0').error, isNotNull);
      expect(parseExpenseAmount('1,234').error, isNotNull);
      expect(parseExpenseAmount('-5').error, isNotNull);
      expect(parseExpenseAmount('1' * 17).error, isNotNull);
    });

    test('rejects future time and receipt links on other categories', () {
      final now = DateTime.utc(2026, 10, 29, 4);
      final errors = validateExpenseDraft(
        categoryCode: 'RENT',
        amountText: '100000',
        expenseAt: now.add(const Duration(hours: 1)),
        now: now,
        stockDocumentId: 'd1',
      );
      expect(errors.keys, containsAll(['expenseAt', 'stockDocumentId']));
      expect(
        validateExpenseDraft(
          categoryCode: 'RENT',
          amountText: '100000',
          expenseAt: now.subtract(const Duration(days: 1)),
          now: now,
        ),
        isEmpty,
      );
      expect(validateVoidReason('  '), isNotNull);
    });
  });

  test(
    'cashbook business codes map to Vietnamese messages by status',
    () async {
      final result = await cashbookResult<void>(
        () => throw DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 409,
            data: {'code': 'CONCURRENT_CASHBOOK_UPDATE', 'message': 'conflict'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      final failure = (result as Error<void>).failure;
      expect(failure.type, FailureType.conflict);
      expect(failure.message, contains('vừa được thay đổi'));
    },
  );
}
