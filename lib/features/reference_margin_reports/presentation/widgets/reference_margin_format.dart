import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import '../../../reports/domain/entities/report_date.dart';
import '../../../reports/domain/entities/report_enums.dart';
import '../../../reports/domain/entities/report_money.dart';
import '../../domain/entities/reference_margin_report.dart';

String marginMoney(ReportMoney? value, String currency) =>
    value?.format(currencyCode: currency) ?? 'Chưa xác định';

String marginPercent(ReferenceMarginPercent? value) =>
    value?.formatted ?? 'Không áp dụng';

/// Short bucket label for chart axes and tables: dd/MM or MM/yyyy.
String marginBucketLabel(ReportDate date, ReportGranularity granularity) {
  String two(int number) => number.toString().padLeft(2, '0');
  return granularity == ReportGranularity.month
      ? '${two(date.month)}/${date.year}'
      : '${two(date.day)}/${two(date.month)}';
}

bool _zonesReady = false;

/// Uses the report's restaurant timezone, never the device's local timezone.
/// An unsupported zone remains readable and explicitly identifies UTC.
String marginTimestamp(DateTime value, String zone) {
  if (!_zonesReady) {
    timezone_data.initializeTimeZones();
    _zonesReady = true;
  }
  DateTime date;
  var label = zone;
  try {
    date = timezone.TZDateTime.from(value, timezone.getLocation(zone));
  } on Object {
    date = value.toUtc();
    label = 'UTC';
  }
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(date.hour)}:${two(date.minute)} · $label';
}
