import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import '../../../reports/domain/entities/report_date.dart';
import '../../../reports/domain/entities/report_money.dart';
import '../../domain/entities/cashbook_enums.dart';

bool _zonesReady = false;

timezone.Location? _location(String? zone) {
  if (zone == null) return null;
  if (!_zonesReady) {
    timezone_data.initializeTimeZones();
    _zonesReady = true;
  }
  try {
    return timezone.getLocation(zone);
  } on Object {
    return null;
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

/// Wall-clock time in the restaurant's timezone, falling back to the device.
DateTime cashbookWallTime(DateTime value, String? zone) {
  final location = _location(zone);
  return location == null
      ? value.toLocal()
      : timezone.TZDateTime.from(value, location);
}

/// Converts a wall-clock time picked in the restaurant's timezone to UTC.
DateTime cashbookInstantFromWallTime(DateTime wall, String? zone) {
  final location = _location(zone);
  if (location == null) {
    return DateTime(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
    ).toUtc();
  }
  return timezone.TZDateTime(
    location,
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
  ).toUtc();
}

/// The restaurant's calendar date, which may differ from the device's.
ReportDate cashbookToday(String? zone) =>
    ReportDate.fromDateTime(cashbookWallTime(DateTime.now(), zone));

String cashbookDateTime(DateTime value, String? zone) {
  final d = cashbookWallTime(value, zone);
  return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
}

String cashbookDate(DateTime value, String? zone) {
  final d = cashbookWallTime(value, zone);
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

String cashbookMoney(ReportMoney value, String? currency) =>
    value.format(currencyCode: currency);

/// Cash flow amounts carry their direction: +income, −expense.
String cashbookSignedMoney(
  ReportMoney value,
  CashbookEntryType type,
  String? currency,
) =>
    '${type == CashbookEntryType.income ? '+' : '−'}${value.format(currencyCode: currency)}';

/// Generated codes run to 36 characters. Narrow rows keep the recognisable
/// prefix and tail; the full code stays in tables and the detail dialog.
String cashbookShortCode(String code) {
  if (code.length <= 22) return code;
  final dash = code.indexOf('-');
  final head = code.substring(0, dash < 0 ? 6 : dash + 5);
  return '$head…${code.substring(code.length - 6)}';
}

/// Amount input text in Vietnamese grouping, e.g. 1.250.000 or 12,5.
String cashbookAmountInput(ReportMoney value) =>
    value.format(includeCurrency: false);

String cashbookBucketLabel(ReportDate date, CashbookGranularity granularity) =>
    granularity == CashbookGranularity.month
    ? '${_two(date.month)}/${date.year}'
    : '${_two(date.day)}/${_two(date.month)}';

String cashbookRangeLabel(ReportDateRange range) =>
    range.fromDate == range.toDate
    ? range.fromDate.formatDisplay()
    : '${range.fromDate.formatDisplay()} – ${range.toDate.formatDisplay()}';
