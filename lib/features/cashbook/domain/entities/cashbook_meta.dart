import '../../../reports/domain/entities/report_date.dart';
import 'cashbook_enums.dart';

/// Attribution of a cashbook response. Totals on screen always belong to the
/// range, timezone and currency echoed here, never to an unapplied draft.
class CashbookMeta {
  const CashbookMeta({
    required this.fromDate,
    required this.toDate,
    required this.timezone,
    required this.currencyCode,
    required this.dateBasis,
    required this.generatedAt,
    this.granularity,
  });

  final ReportDate fromDate, toDate;
  final String timezone, currencyCode, dateBasis;
  final DateTime generatedAt;
  final CashbookGranularity? granularity;
}

class CashbookEnvelope<T> {
  const CashbookEnvelope({required this.meta, required this.data});
  final CashbookMeta meta;
  final T data;
}
