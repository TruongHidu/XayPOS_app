import '../../../order/domain/entities/order_entities.dart' show ServiceType;
import 'report_date.dart';
import 'report_enums.dart';

/// Metadata envelope returned by all operational report endpoints.
class ReportMeta {
  const ReportMeta({
    required this.fromDate,
    required this.toDate,
    required this.timezone,
    required this.currencyCode,
    required this.generatedAt,
    this.serviceType,
    this.sourceChannel,
    this.granularity,
    this.dateBasis,
  });

  final ReportDate fromDate;
  final ReportDate toDate;
  final String timezone;
  final String currencyCode;
  final DateTime generatedAt;
  final ServiceType? serviceType;
  final ReportSourceChannel? sourceChannel;
  final ReportGranularity? granularity;
  final ReportDateBasis? dateBasis;

  ReportDateRange get dateRange =>
      ReportDateRange(fromDate: fromDate, toDate: toDate);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportMeta &&
          other.fromDate == fromDate &&
          other.toDate == toDate &&
          other.timezone == timezone &&
          other.currencyCode == currencyCode &&
          other.generatedAt == generatedAt &&
          other.serviceType == serviceType &&
          other.sourceChannel == sourceChannel &&
          other.granularity == granularity &&
          other.dateBasis == dateBasis;

  @override
  int get hashCode => Object.hash(
    fromDate,
    toDate,
    timezone,
    currencyCode,
    generatedAt,
    serviceType,
    sourceChannel,
    granularity,
    dateBasis,
  );
}

/// Generic response envelope containing meta and data.
class ReportEnvelope<T> {
  const ReportEnvelope({required this.meta, required this.data});

  final ReportMeta meta;
  final T data;
}
