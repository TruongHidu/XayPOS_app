import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/features/reports/data/dto/report_dto.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_date.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_enums.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_money.dart';

void main() {
  group('ReportDate', () {
    test('parses yyyy-MM-dd correctly', () {
      final date = ReportDate.parse('2026-10-15');
      expect(date.year, 2026);
      expect(date.month, 10);
      expect(date.day, 15);
      expect(date.toString(), '2026-10-15');
      expect(date.formatDisplay(), '15/10/2026');
    });

    test('validates invalid dates', () {
      expect(ReportDate.tryParse('invalid'), isNull);
      expect(ReportDate.tryParse('2026-02-30'), isNull);
      expect(ReportDate.tryParse('2026-13-01'), isNull);
    });

    test('handles leap years correctly', () {
      // 2024 is a leap year
      expect(ReportDate.tryParse('2024-02-29'), isNotNull);
      // 2025 is not a leap year
      expect(ReportDate.tryParse('2025-02-29'), isNull);
    });

    test('calculates difference and range days correctly', () {
      final d1 = ReportDate(2026, 1, 1);
      final d2 = ReportDate(2026, 1, 7);
      expect(d1.differenceInDays(d2), 6);
      final range = ReportDateRange(fromDate: d1, toDate: d2);
      expect(range.daysCount, 7); // inclusive of both ends
      expect(range.isValid, isTrue);
    });

    test('validates 366 days max limit', () {
      final start = ReportDate(2026, 1, 1);
      // 366 days inclusive
      final validEnd = start.addDays(365);
      final validRange = ReportDateRange(fromDate: start, toDate: validEnd);
      expect(validRange.daysCount, 366);
      expect(validRange.isValid, isTrue);

      // 367 days inclusive
      final invalidEnd = start.addDays(366);
      final invalidRange = ReportDateRange(fromDate: start, toDate: invalidEnd);
      expect(invalidRange.daysCount, 367);
      expect(invalidRange.isValid, isFalse);
    });

    test('rejects fromDate > toDate', () {
      final d1 = ReportDate(2026, 10, 15);
      final d2 = ReportDate(2026, 10, 10);
      final range = ReportDateRange(fromDate: d1, toDate: d2);
      expect(range.isValid, isFalse);
    });
  });

  group('ReportMoney', () {
    test('preserves 2 decimal precision without floating point errors', () {
      final m1 = ReportMoney.parse(100.5);
      final m2 = ReportMoney.parse('200.25');
      final sum = m1 + m2;
      expect(sum.minorUnits, BigInt.from(30075));
      expect(sum.majorValueString, '300.75');
    });

    test('formats Vietnamese money display', () {
      final money = ReportMoney.fromMajor(15000000);
      expect(money.format(currencyCode: 'VND'), '15.000.000 VND');
    });

    test('formats compact display for charts', () {
      expect(
        ReportMoney.fromMajor(500).formatCompact(currencyCode: 'VND'),
        '500 VND',
      );
      expect(
        ReportMoney.fromMajor(500000).formatCompact(currencyCode: 'VND'),
        '500 k VND',
      );
      expect(
        ReportMoney.fromMajor(15000000).formatCompact(currencyCode: 'VND'),
        '15 tr VND',
      );
      expect(
        ReportMoney.fromMajor(2500000000).formatCompact(currencyCode: 'VND'),
        '2.5 tỷ VND',
      );
    });

    test('handles zero and negative amounts safely', () {
      final zero = ReportMoney.zero;
      expect(zero.minorUnits, BigInt.zero);
      expect(zero.toDouble(), 0.0);
    });
  });

  group('ReportDto JSON Parsing', () {
    test('parses Daily/Summary Overview envelope successfully', () {
      final json = {
        'meta': {
          'fromDate': '2026-10-15',
          'toDate': '2026-10-15',
          'timezone': 'Asia/Ho_Chi_Minh',
          'currencyCode': 'VND',
          'generatedAt': '2026-10-15T12:00:00Z',
          'serviceType': 'DINE_IN',
          'sourceChannel': 'WAITER',
        },
        'data': {
          'collections': {
            'collectedAmount': 5000000,
            'successfulPaymentCount': 15,
            'paidOrderCount': 14,
          },
          'orders': {
            'completedOrderSalesAmount': 4800000,
            'completedOrderCount': 12,
            'averageCompletedOrderValue': 400000,
            'createdOrderCount': 16,
            'cancelledOrderCount': 1,
            'completedSubtotalAmount': 4500000,
            'completedDiscountAmount': 200000,
            'completedTaxAmount': 350000,
            'completedServiceChargeAmount': 150000,
          },
        },
      };

      final envelope = ReportDto.parseOverviewEnvelope(json);
      expect(envelope.meta.timezone, 'Asia/Ho_Chi_Minh');
      expect(envelope.meta.currencyCode, 'VND');
      expect(envelope.meta.fromDate, ReportDate(2026, 10, 15));
      expect(envelope.meta.serviceType?.name, 'dineIn');
      expect(envelope.meta.sourceChannel, ReportSourceChannel.waiter);

      final overview = envelope.data;
      expect(overview.collections.collectedAmount.majorValueString, '5000000');
      expect(overview.collections.successfulPaymentCount, 15);
      expect(
        overview.orders.completedOrderSalesAmount.majorValueString,
        '4800000',
      );
      expect(
        overview.orders.averageCompletedOrderValue.majorValueString,
        '400000',
      );
      expect(
        overview.orders.completedDiscountAmount.majorValueString,
        '200000',
      );
    });

    test('parses Revenue Series list envelope successfully', () {
      final json = {
        'meta': {
          'fromDate': '2026-10-01',
          'toDate': '2026-10-02',
          'timezone': 'Asia/Ho_Chi_Minh',
          'currencyCode': 'VND',
          'granularity': 'DAY',
        },
        'data': [
          {
            'bucketStartDate': '2026-10-01',
            'collectedAmount': 2000000,
            'completedOrderSalesAmount': 1900000,
            'successfulPaymentCount': 8,
            'completedOrderCount': 7,
          },
          {
            'bucketStartDate': '2026-10-02',
            'collectedAmount': 0,
            'completedOrderSalesAmount': 0,
            'successfulPaymentCount': 0,
            'completedOrderCount': 0,
          },
        ],
      };

      final envelope = ReportDto.parseRevenueSeriesEnvelope(json);
      expect(envelope.data.length, 2);
      expect(envelope.data[0].bucketStartDate, ReportDate(2026, 10, 1));
      expect(envelope.data[0].collectedAmount.majorValueString, '2000000');
      expect(envelope.data[1].collectedAmount.majorValueString, '0');
    });

    test('parses Payment Methods envelope with server percentage', () {
      final json = {
        'meta': {
          'fromDate': '2026-10-01',
          'toDate': '2026-10-15',
          'timezone': 'Asia/Ho_Chi_Minh',
          'currencyCode': 'VND',
        },
        'data': [
          {
            'paymentMethod': 'CASH',
            'collectedAmount': 3000000,
            'successfulPaymentCount': 10,
            'percentage': 30.0,
          },
          {
            'paymentMethod': 'TRANSFER',
            'collectedAmount': 7000000,
            'successfulPaymentCount': 20,
            'percentage': 70.0,
          },
        ],
      };

      final envelope = ReportDto.parsePaymentMethodsEnvelope(json);
      expect(envelope.data.length, 2);
      expect(envelope.data[0].paymentMethod, ReportPaymentMethod.cash);
      expect(envelope.data[0].percentage, 30.0);
      expect(envelope.data[1].paymentMethod, ReportPaymentMethod.transfer);
      expect(envelope.data[1].percentage, 70.0);
    });

    test(
      'parses Top Items page envelope with decimal quantity and nullable itemId',
      () {
        final json = {
          'meta': {
            'fromDate': '2026-10-01',
            'toDate': '2026-10-15',
            'timezone': 'Asia/Ho_Chi_Minh',
            'currencyCode': 'VND',
          },
          'data': {
            'content': [
              {
                'itemId': null,
                'snapshotItemName': 'Món đã xóa khỏi menu',
                'unit': 'Phần',
                'quantity': 15.75,
                'itemSalesAmount': 787500,
                'completedOrderCount': 12,
              },
            ],
            'number': 0,
            'size': 20,
            'totalElements': 1,
            'totalPages': 1,
            'first': true,
            'last': true,
            'hasNext': false,
            'hasPrevious': false,
          },
        };

        final envelope = ReportDto.parseTopItemsEnvelope(json);
        expect(envelope.data.content.length, 1);
        final row = envelope.data.content[0];
        expect(row.itemId, isNull);
        expect(row.snapshotItemName, 'Món đã xóa khỏi menu');
        expect(row.quantity, 15.75);
        expect(row.formattedQuantity, '15.75');
        expect(row.rowKey, 'null::Món đã xóa khỏi menu::Phần');
      },
    );

    test('parses Reconciliation Orders page envelope', () {
      final json = {
        'meta': {
          'fromDate': '2026-10-01',
          'toDate': '2026-10-15',
          'timezone': 'Asia/Ho_Chi_Minh',
          'currencyCode': 'VND',
          'dateBasis': 'PAID',
        },
        'data': {
          'content': [
            {
              'orderId': 'ord-123',
              'orderCode': 'ORD-2026-001',
              'serviceType': 'TAKEAWAY',
              'sourceChannel': 'CASHIER',
              'status': 'CONFIRMED',
              'paymentStatus': 'PARTIALLY_PAID',
              'totalAmount': 500000,
              'collectedAmountInRange': 200000,
              'reportEventAt': '2026-10-15T10:30:00Z',
            },
          ],
          'number': 0,
          'size': 20,
          'totalElements': 1,
          'totalPages': 1,
          'first': true,
          'last': true,
          'hasNext': false,
          'hasPrevious': false,
        },
      };

      final envelope = ReportDto.parseOrdersEnvelope(json);
      expect(envelope.data.content.length, 1);
      final row = envelope.data.content[0];
      expect(row.orderCode, 'ORD-2026-001');
      expect(row.serviceType.name, 'takeaway');
      expect(row.sourceChannel, ReportSourceChannel.cashier);
      expect(row.status.name, 'confirmed');
      expect(row.paymentStatus.name, 'partiallyPaid');
      expect(row.totalAmount.majorValueString, '500000');
      expect(row.collectedAmountInRange.majorValueString, '200000');
    });
  });

  group('ApiErrorMapper for Reports', () {
    test('maps report error codes to user-friendly Vietnamese messages', () {
      Failure failureFor(String code) {
        return ApiErrorMapper.fromException(
          DioException(
            requestOptions: RequestOptions(path: '/api/v1/reports'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/v1/reports'),
              statusCode: 400,
              data: {'code': code, 'message': 'Original error'},
            ),
          ),
        );
      }

      expect(
        failureFor('INVALID_REPORT_DATE_RANGE').message,
        'Khoảng ngày báo cáo không hợp lệ.',
      );
      expect(
        failureFor('REPORT_RANGE_TOO_LARGE').message,
        'Khoảng ngày báo cáo vượt quá giới hạn cho phép (tối đa 366 ngày).',
      );
      expect(
        failureFor('INVALID_REPORT_CURRENCY').message,
        'Mã tiền tệ báo cáo không hợp lệ.',
      );
      expect(
        failureFor('INVALID_REPORT_SORT').message,
        'Tiêu chí sắp xếp báo cáo không hợp lệ.',
      );
      expect(
        failureFor('INVALID_REPORT_TIMEZONE').message,
        'Cấu hình múi giờ của nhà hàng không hợp lệ. Vui lòng liên hệ quản lý.',
      );
    });
  });
}
