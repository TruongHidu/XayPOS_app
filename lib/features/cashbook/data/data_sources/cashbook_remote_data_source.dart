import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/network/exact_json.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/cashbook_enums.dart';
import '../../domain/entities/cashbook_filters.dart';
import '../../domain/entities/cashbook_inputs.dart';
import '../../domain/entities/cashbook_meta.dart';
import '../../domain/entities/cashbook_records.dart';
import '../dto/cashbook_dto.dart';
import '../dto/cashbook_requests.dart';

class CashbookRemoteDataSource {
  const CashbookRemoteDataSource(this._dio);
  final Dio _dio;
  static const _prefix = '/api/v1/cashbook';

  Options _options([Map<String, String> extra = const {}]) => Options(
    responseType: ResponseType.plain,
    headers: {
      'Accept': Headers.jsonContentType,
      'Cache-Control': 'no-store',
      ...extra,
    },
  );

  Future<Response<dynamic>> _send(
    Future<Response<dynamic>> Function() request,
    Set<int> accepted,
  ) async {
    try {
      final response = await request();
      if (!accepted.contains(response.statusCode)) {
        throw const FormatException('Invalid cashbook response status');
      }
      if (response.data is String) {
        response.data = decodeExactJson(response.data as String);
      }
      return response;
    } on DioException catch (error) {
      final raw = error.response?.data;
      if (raw is String) {
        try {
          error.response!.data = jsonDecode(raw);
        } on FormatException {
          /* Preserve unknown errors. */
        }
      }
      rethrow;
    }
  }

  Future<Object?> _get(String endpoint, [Map<String, Object>? query]) async =>
      (await _send(
        () => _dio.get<dynamic>(
          '$_prefix/$endpoint',
          queryParameters: query,
          options: _options(),
        ),
        const {200},
      )).data;

  Future<List<CashbookCategory>> getCategories({
    CashbookEntryType? type,
  }) async => CashbookDto.categories(
    await _get('categories', {if (type != null) 'type': type.apiCode}),
  );

  Future<CashbookEnvelope<ReportPage<CashbookEntry>>> getEntries(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
  ) async => CashbookDto.entries(
    await _get('entries', CashbookRequests.entries(range, filter)),
  );

  Future<CashbookEnvelope<CashbookSummary>> getSummary(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
  ) async => CashbookDto.summary(
    await _get('summary', CashbookRequests.flow(range, filter)),
  );

  Future<CashbookEnvelope<List<CashbookSeriesPoint>>> getSeries(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
    CashbookGranularity granularity,
  ) async => CashbookDto.series(
    await _get('series', CashbookRequests.series(range, filter, granularity)),
    granularity,
  );

  Future<CashbookEnvelope<ReportPage<CashbookExpense>>> getExpenses(
    CashbookRangeFilter range,
    CashbookExpenseFilter filter,
  ) async => CashbookDto.expenses(
    await _get('expenses', CashbookRequests.expenses(range, filter)),
  );

  Future<CashbookExpense> getExpense(String id) async =>
      CashbookDto.expense(await _get('expenses/${Uri.encodeComponent(id)}'));

  Future<ExpenseCreateResult> createExpense(
    CreateExpenseInput input, {
    required String idempotencyKey,
  }) async {
    final response = await _send(
      () => _dio.post<dynamic>(
        '$_prefix/expenses',
        data: CashbookRequests.create(input),
        options: _options({'Idempotency-Key': idempotencyKey}),
      ),
      const {200, 201},
    );
    final header = response.headers.value('Idempotency-Replayed');
    return ExpenseCreateResult(
      expense: CashbookDto.expense(response.data),
      replayed: header == 'true' || response.statusCode == 200,
    );
  }

  Future<CashbookExpense> voidExpense(
    String id,
    VoidExpenseInput input,
  ) async => CashbookDto.expense(
    (await _send(
      () => _dio.post<dynamic>(
        '$_prefix/expenses/${Uri.encodeComponent(id)}/void',
        data: CashbookRequests.voidBody(input),
        options: _options(),
      ),
      const {200},
    )).data,
  );

  Future<CashbookEnvelope<ReportPage<CashbookStockReceipt>>> getStockReceipts(
    CashbookRangeFilter range,
    CashbookReceiptFilter filter,
  ) async => CashbookDto.receipts(
    await _get('stock-receipts', CashbookRequests.receipts(range, filter)),
  );
}
