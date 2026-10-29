import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/exact_json.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/reference_margin_reports/data/data_sources/reference_margin_remote_data_source.dart';
import 'package:pos_saas_app/features/reference_margin_reports/data/dto/reference_margin_dto.dart';
import 'package:pos_saas_app/features/reference_margin_reports/data/repositories/reference_margin_repository_impl.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/entities/reference_margin_enums.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/entities/reference_margin_filters.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/entities/reference_margin_report.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_date.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_enums.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_meta.dart';
import 'margin_fakes.dart';

void main() {
  test(
    'query identities include endpoint and every endpoint-specific field',
    () {
      final filter = marginFilter();
      expect(filter.queryKey('summary'), isNot(filter.queryKey('series')));
      expect(
        filter.queryKey('series', granularity: ReportGranularity.day),
        isNot(filter.queryKey('series', granularity: ReportGranularity.month)),
      );
      expect(
        filter.queryKey('summary'),
        isNot(filter.copyWith(currencyCode: () => 'USD').queryKey('summary')),
      );
      expect(
        filter.queryKey('summary'),
        isNot(
          filter
              .copyWith(serviceType: () => ServiceType.takeaway)
              .queryKey('summary'),
        ),
      );
      expect(
        filter.queryKey('summary'),
        isNot(
          filter
              .copyWith(sourceChannel: () => ReportSourceChannel.qrTable)
              .queryKey('summary'),
        ),
      );
      expect(filter, filter.copyWith(currencyCode: () => 'vnd'));
      final orders = ReferenceMarginOrdersFilter(filter: filter);
      final variants = [
        orders,
        orders.copyWith(page: 1),
        orders.copyWith(size: 10),
        orders.copyWith(costCoverage: CostCoverageFilter.excluded),
        orders.copyWith(sortBy: ReferenceMarginOrderSort.referenceMarginAmount),
        orders.copyWith(direction: ReportSortDirection.asc),
        orders.copyWith(filter: filter.copyWith(currencyCode: () => 'USD')),
      ];
      expect(
        variants.map((e) => e.queryKey()).toSet(),
        hasLength(variants.length),
      );
      expect(orders.page, 0);
      expect(orders.size, 20);
      expect(orders.sortBy, ReferenceMarginOrderSort.completedAt);
      expect(orders.direction, ReportSortDirection.desc);
    },
  );

  test(
    'date filters stay calendar dates, allow366days and reject invalid ranges/currency',
    () {
      final from = const ReportDate(2026, 1, 1);
      final valid = ReferenceMarginFilter(
        range: ReportDateRange(fromDate: from, toDate: from.addDays(365)),
      );
      expect(valid.validate(), null);
      expect(
        valid
            .copyWith(
              range: ReportDateRange(fromDate: from, toDate: from.addDays(366)),
            )
            .validate(),
        isNotNull,
      );
      expect(
        valid
            .copyWith(
              range: ReportDateRange(fromDate: from.addDays(1), toDate: from),
            )
            .validate(),
        isNotNull,
      );
      expect(
        valid
            .copyWith(
              range: const ReportDateRange(
                fromDate: ReportDate(2026, 2, 30),
                toDate: ReportDate(2026, 3, 2),
              ),
            )
            .validate(),
        isNotNull,
      );
      expect(
        valid.copyWith(currencyCode: () => 'VND/USD').validate(),
        isNotNull,
      );
      expect(
        ReferenceMarginOrdersFilter(filter: valid, size: 101).validate(),
        isNotNull,
      );
      expect(
        ReferenceMarginOrdersFilter(filter: valid, page: -1).validate(),
        isNotNull,
      );
    },
  );

  test(
    'summary preserves two cohorts and uses authoritative percentage, not issue totals',
    () {
      final json = marginSummaryJson();
      json['coveredReferenceMarginPercent'] = 62.51;
      (json['costIssues'] as List).add({
        'code': 'LEGACY_UNAVAILABLE',
        'orderCount': 2,
        'itemCount': 1,
      });
      final value = ReferenceMarginDto.summary(
        marginEnvelopeJson(json),
        marginFilter(),
      ).data;
      expect(value.netSalesAmount.toString(), '1000000.00');
      expect(value.coveredNetSalesAmount.toString(), '800000.00');
      expect(value.coveredReferenceMarginAmount.toString(), '500000.00');
      expect(value.coveredReferenceMarginPercent!.formatted, '62,51%');
      expect(value.excludedOrderCount, 2);
      expect(
        value.costIssues.map((e) => e.orderCount).reduce((a, b) => a + b),
        4,
      );
      expect(value.costIssues.last.label, contains('Đơn cũ'));
    },
  );

  for (final coverage in CostCoverageStatus.values) {
    test(
      'coverage ${coverage.code} remains a successful report including empty cohorts',
      () {
        final value = ReferenceMarginDto.summary(
          marginEnvelopeJson(marginSummaryJson(coverage: coverage.code)),
          marginFilter(),
        ).data;
        expect(value.costCoverageStatus, coverage);
        if (coverage == CostCoverageStatus.noData) {
          expect(value.completedOrderCount, 0);
          expect(value.orderCoveragePercent, null);
        }
        if (coverage == CostCoverageStatus.noData ||
            coverage == CostCoverageStatus.unavailable) {
          expect(value.coveredNetSalesAmount.isZero, true);
          expect(value.coveredReferenceMarginAmount.isZero, true);
          expect(value.coveredReferenceMarginPercent, null);
        }
      },
    );
  }

  test(
    'negative margin and percentage are valid, nullable zero-denominator stays null',
    () {
      final value = ReferenceMarginDto.summary(
        marginEnvelopeJson(marginSummaryJson(negative: true)),
        marginFilter(),
      ).data;
      expect(value.coveredReferenceMarginAmount.isNegative, true);
      expect(value.coveredReferenceMarginPercent!.formatted, '-12,50%');
      final row = ReferenceMarginDto.orderValue(
        marginOrderJson(negative: true),
      );
      expect(row.referenceMarginAmount!.toString(), '-20000.00');
      final zero = marginOrderJson()
        ..['netSalesAmount'] = 0
        ..['referenceCostAmount'] = 0
        ..['referenceMarginAmount'] = 0
        ..['referenceMarginPercent'] = null;
      final known = ReferenceMarginDto.orderValue(zero);
      expect(known.costCoverageStatus, CostCoverageStatus.complete);
      expect(known.referenceCostAmount!.isZero, true);
      expect(known.referenceMarginPercent, null);
      final excluded = ReferenceMarginDto.orderValue(
        marginOrderJson(excluded: true),
      );
      expect(excluded.referenceCostAmount, null);
      expect(excluded.referenceMarginAmount, null);
      expect(excluded.referenceMarginPercent, null);
    },
  );

  test(
    'required/malformed values never become zero; excluded fields must remain nullable',
    () {
      for (final key in [
        'netSalesAmount',
        'coveredReferenceCostAmount',
        'completedOrderCount',
        'orderCoveragePercent',
      ]) {
        final missing = marginSummaryJson()..remove(key);
        expect(
          () => ReferenceMarginDto.summaryValue(missing),
          throwsFormatException,
          reason: key,
        );
        for (final malformed in [
          true,
          '12',
          'bad',
          <String, dynamic>{},
          double.nan,
        ]) {
          final raw = marginSummaryJson()..[key] = malformed;
          expect(
            () => ReferenceMarginDto.summaryValue(raw),
            throwsFormatException,
            reason: '$key: $malformed',
          );
        }
      }
      expect(
        () => ReferenceMarginDto.summaryValue(
          marginSummaryJson()..['netSalesAmount'] = .001,
        ),
        throwsFormatException,
      );
      expect(
        () => ReferenceMarginDto.orderValue(
          marginOrderJson(excluded: true)..['referenceCostAmount'] = 0,
        ),
        throwsFormatException,
      );
      expect(
        () => ReferenceMarginDto.orderValue(
          marginOrderJson()..remove('referenceCostAmount'),
        ),
        throwsFormatException,
      );
      expect(
        () => ReferenceMarginDto.summaryValue(
          marginSummaryJson()..['costCoverageStatus'] = 'EXCLUDED',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'legacy, unavailable and no-eligible issues remain unknown, without sum-deduplicating order counts',
    () {
      final raw = marginOrderJson(excluded: true)
        ..['eligibleItemCount'] = 0
        ..['fullyCostedItemCount'] = 0
        ..['costCoverageStatus'] = 'UNAVAILABLE'
        ..['costIssues'] = [
          {'code': 'NO_ELIGIBLE_ITEMS', 'orderCount': 1, 'itemCount': 0},
          {'code': 'UNAVAILABLE', 'orderCount': 1, 'itemCount': 0},
        ];
      final value = ReferenceMarginDto.orderValue(raw);
      expect(value.referenceCostAmount, null);
      expect(value.referenceMarginAmount, null);
      expect(value.costIssues.first.label, 'Không có dòng món được xét');
      expect(value.costIssues.last.label, 'Chưa có nguồn giá vốn');
      expect(value.costIssues, hasLength(2));
    },
  );

  test('exact JSON preserves huge signed cents and scientific notation', () {
    final raw =
        jsonEncode(marginEnvelopeJson(marginSummaryJson(negative: true)))
            .replaceFirst(
              '"coveredReferenceCostAmount":900000',
              '"coveredReferenceCostAmount":999999999999999999.99',
            )
            .replaceFirst(
              '"coveredReferenceMarginAmount":-100000',
              '"coveredReferenceMarginAmount":-1.001e18',
            );
    final value = ReferenceMarginDto.summary(
      decodeExactJson(raw),
      marginFilter(),
    ).data;
    expect(
      value.coveredReferenceCostAmount.toString(),
      '999999999999999999.99',
    );
    expect(
      value.coveredReferenceMarginAmount.toString(),
      '-1001000000000000000.00',
    );
  });

  test('response metadata is checked for the exact applied query', () {
    final changes = <String, Object>{
      'currencyCode': 'USD',
      'fromDate': '2026-09-30',
      'serviceType': 'TAKEAWAY',
      'sourceChannel': 'QR_TABLE',
      'dateBasis': 'PAID',
      'granularity': 'DAY',
      'generatedAt': '2026-10-28T12:00:00',
    };
    for (final entry in changes.entries) {
      final raw = marginEnvelopeJson(marginSummaryJson());
      (raw['meta'] as Map<String, dynamic>)[entry.key] = entry.value;
      expect(
        () => ReferenceMarginDto.summary(raw, marginFilter()),
        throwsFormatException,
        reason: entry.key,
      );
    }
  });

  test(
    'series unwraps flat metrics and accepts clipped monthly bucket starting before fromDate',
    () {
      final filter = marginFilter().copyWith(
        range: const ReportDateRange(
          fromDate: ReportDate(2026, 10, 15),
          toDate: ReportDate(2026, 11, 2),
        ),
      );
      final raw = marginEnvelopeJson(
        [
          {'bucketStartDate': '2026-10-01', ...marginSummaryJson()},
          {
            'bucketStartDate': '2026-11-01',
            ...marginSummaryJson(coverage: 'NO_DATA'),
          },
        ],
        filter: filter,
        granularity: ReportGranularity.month,
      );
      final result = ReferenceMarginDto.series(
        raw,
        filter,
        ReportGranularity.month,
      );
      expect(result.data.first.bucketStartDate, const ReportDate(2026, 10, 1));
      expect(
        result.data.first.metrics.coveredReferenceMarginPercent!.formatted,
        '62,50%',
      );
      expect(
        result.data.last.metrics.costCoverageStatus,
        CostCoverageStatus.noData,
      );
      final nested = marginEnvelopeJson(
        [
          {'bucketStartDate': '2026-10-01', 'metrics': marginSummaryJson()},
        ],
        filter: filter,
        granularity: ReportGranularity.month,
      );
      expect(
        () =>
            ReferenceMarginDto.series(nested, filter, ReportGranularity.month),
        throwsFormatException,
      );
      final duplicate = marginEnvelopeJson(
        [
          {'bucketStartDate': '2026-10-01', ...marginSummaryJson()},
          {'bucketStartDate': '2026-10-01', ...marginSummaryJson()},
        ],
        filter: filter,
        granularity: ReportGranularity.month,
      );
      expect(
        () => ReferenceMarginDto.series(
          duplicate,
          filter,
          ReportGranularity.month,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'orders parse PageResponse preserve server order and excluded null, not old Spring number',
    () {
      final query = ReferenceMarginOrdersFilter(filter: marginFilter());
      final body = {
        'content': [
          marginOrderJson(id: 'second'),
          marginOrderJson(id: 'first', excluded: true),
        ],
        'page': 0,
        'size': 20,
        'totalElements': 2,
        'totalPages': 1,
      };
      final value = ReferenceMarginDto.orders(
        marginEnvelopeJson(body),
        query,
      ).data;
      expect(value.content.map((e) => e.orderId), ['second', 'first']);
      expect(value.content.last.referenceCostAmount, null);
      expect(
        () => ReferenceMarginDto.orders(
          marginEnvelopeJson(
            {...body}
              ..remove('page')
              ..['number'] = 0,
          ),
          query,
        ),
        throwsFormatException,
      );
      expect(
        () => ReferenceMarginDto.orders(
          marginEnvelopeJson(body),
          query.copyWith(costCoverage: CostCoverageFilter.complete),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'all3GETs use scoped authenticated client, exact query, no body and fresh no-store reads',
    () async {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://reports.invalid',
          headers: {'Authorization': 'Bearer test-token'},
        ),
      );
      addTearDown(dio.close);
      final requests = <RequestOptions>[];
      final filter = marginFilter(
        currencyCode: 'usd',
        serviceType: ServiceType.takeaway,
        sourceChannel: ReportSourceChannel.qrTable,
      );
      final orders = ReferenceMarginOrdersFilter(
        filter: filter,
        costCoverage: CostCoverageFilter.excluded,
        page: 1,
        size: 5,
        sortBy: ReferenceMarginOrderSort.referenceMarginAmount,
        direction: ReportSortDirection.asc,
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests.add(r);
            Object data = marginSummaryJson()
              ..['coveredReferenceMarginAmount'] = requests.length;
            ReportGranularity? granularity;
            if (r.path.endsWith('/series')) {
              granularity = ReportGranularity.month;
              data = [
                {'bucketStartDate': '2026-10-01', ...marginSummaryJson()},
              ];
            } else if (r.path.endsWith('/orders')) {
              data = {
                'content': [],
                'page': 1,
                'size': 5,
                'totalElements': 0,
                'totalPages': 0,
              };
            }
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: 200,
                data: jsonEncode(
                  marginEnvelopeJson(
                    data,
                    filter: filter,
                    granularity: granularity,
                  ),
                ),
              ),
            );
          },
        ),
      );
      final repo = ReferenceMarginRepositoryImpl(
        ReferenceMarginRemoteDataSource(dio),
      );
      final first =
          await repo.getSummary(filter)
              as Success<ReportEnvelope<ReferenceMarginSummary>>;
      final second =
          await repo.getSummary(filter)
              as Success<ReportEnvelope<ReferenceMarginSummary>>;
      expect(first.value.data.coveredReferenceMarginAmount.toString(), '1.00');
      expect(second.value.data.coveredReferenceMarginAmount.toString(), '2.00');
      expect(
        await repo.getSeries(filter, granularity: ReportGranularity.month),
        isA<Success>(),
      );
      expect(await repo.getOrders(orders), isA<Success>());
      for (final request in requests) {
        expect(request.method, 'GET');
        expect(request.data, null);
        expect(request.responseType, ResponseType.plain);
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.headers['Accept'], 'application/json');
        expect(request.headers['Cache-Control'], 'no-store');
        expect(request.headers.containsKey('Idempotency-Key'), false);
        expect(request.queryParameters['restaurantId'], null);
        expect(request.path, startsWith('/api/v1/reports/reference-margin/'));
        expect(request.queryParameters['fromDate'], '2026-10-01');
        expect(request.queryParameters['toDate'], '2026-10-02');
        expect(request.queryParameters['currencyCode'], 'USD');
        expect(request.queryParameters['serviceType'], 'TAKEAWAY');
        expect(request.queryParameters['sourceChannel'], 'QR_TABLE');
      }
      expect(requests[2].queryParameters['granularity'], 'MONTH');
      expect(requests.last.queryParameters, {
        'fromDate': '2026-10-01',
        'toDate': '2026-10-02',
        'currencyCode': 'USD',
        'serviceType': 'TAKEAWAY',
        'sourceChannel': 'QR_TABLE',
        'costCoverage': 'EXCLUDED',
        'page': 1,
        'size': 5,
        'sortBy': 'referenceMarginAmount',
        'direction': 'asc',
      });
    },
  );

  test(
    'real transformer preserves cents above JavaScript safe integer precision',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://reports.invalid'));
      addTearDown(dio.close);
      dio.httpClientAdapter = _JsonAdapter(
        jsonEncode(marginEnvelopeJson(marginSummaryJson())).replaceFirst(
          '"coveredReferenceCostAmount":300000',
          '"coveredReferenceCostAmount":999999999999999999.99',
        ),
      );
      final result =
          await ReferenceMarginRepositoryImpl(
                ReferenceMarginRemoteDataSource(dio),
              ).getSummary(marginFilter())
              as Success<ReportEnvelope<ReferenceMarginSummary>>;
      expect(
        result.value.data.coveredReferenceCostAmount.minorUnits,
        BigInt.parse('99999999999999999999'),
      );
    },
  );

  test(
    'invalid filters block GET, malformed response maps internal instead of fabricated empty',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://reports.invalid'));
      addTearDown(dio.close);
      var calls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            calls++;
            h.resolve(Response(requestOptions: r, statusCode: 200, data: '{}'));
          },
        ),
      );
      final repo = ReferenceMarginRepositoryImpl(
        ReferenceMarginRemoteDataSource(dio),
      );
      final invalid =
          await repo.getOrders(
                ReferenceMarginOrdersFilter(filter: marginFilter(), size: 101),
              )
              as Error;
      expect(invalid.failure.type, FailureType.validation);
      expect(calls, 0);
      final malformed = await repo.getSummary(marginFilter()) as Error;
      expect(malformed.failure.code, 'INVALID_REFERENCE_MARGIN_RESPONSE');
      expect(calls, 1);
    },
  );

  for (final code in [
    'REPORT_COST_DATA_CONFLICT',
    'INVALID_REPORT_TIMEZONE',
    'FEATURE_NOT_ENTITLED',
    'FORBIDDEN',
  ]) {
    test(
      'plain error envelope $code remains recoverable failure, never zero',
      () async {
        final dio = Dio(BaseOptions(baseUrl: 'https://reports.invalid'));
        addTearDown(dio.close);
        final forbidden = code == 'FEATURE_NOT_ENTITLED' || code == 'FORBIDDEN';
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) => h.reject(
              DioException(
                requestOptions: r,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: r,
                  statusCode: forbidden ? 403 : 409,
                  data: jsonEncode({
                    'success': false,
                    'code': code,
                    'message': 'Backend detail',
                    'fieldErrors': {},
                  }),
                ),
              ),
            ),
          ),
        );
        final result =
            await ReferenceMarginRepositoryImpl(
                  ReferenceMarginRemoteDataSource(dio),
                ).getSummary(marginFilter())
                as Error;
        expect(result.failure.code, code);
        expect(
          result.failure.type,
          forbidden
              ? code == 'FEATURE_NOT_ENTITLED'
                    ? FailureType.featureNotEntitled
                    : FailureType.forbidden
              : FailureType.conflict,
        );
      },
    );
  }
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);
  final String body;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    200,
    headers: {
      'content-type': ['application/json'],
      'cache-control': ['no-store'],
    },
  );
  @override
  void close({bool force = false}) {}
}
