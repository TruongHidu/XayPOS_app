/// Represents a pure calendar date in yyyy-MM-dd format without timezone skew.
class ReportDate implements Comparable<ReportDate> {
  const ReportDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  /// Creates a ReportDate from today's date in local clock.
  factory ReportDate.today() {
    final now = DateTime.now();
    return ReportDate(now.year, now.month, now.day);
  }

  factory ReportDate.fromDateTime(DateTime dt) =>
      ReportDate(dt.year, dt.month, dt.day);

  DateTime toDateTime() => DateTime(year, month, day);

  /// Parses a string formatted as yyyy-MM-dd.
  factory ReportDate.parse(String input) {
    final trimmed = input.trim();
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(trimmed);
    if (match == null) {
      throw FormatException(
        'Định dạng ngày không hợp lệ (cần yyyy-MM-dd): $input',
      );
    }
    final y = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final d = int.parse(match.group(3)!);

    if (m < 1 || m > 12) {
      throw FormatException('Tháng không hợp lệ: $m');
    }
    final maxD = daysInMonth(y, m);
    if (d < 1 || d > maxD) {
      throw FormatException(
        'Ngày không hợp lệ trong tháng $m: $d (tối đa $maxD)',
      );
    }
    return ReportDate(y, m, d);
  }

  /// Safe parse returning null on invalid input.
  static ReportDate? tryParse(String? input) {
    if (input == null) return null;
    try {
      return ReportDate.parse(input);
    } catch (_) {
      return null;
    }
  }

  /// Returns the number of days in month [m] of year [y].
  static int daysInMonth(int y, int m) {
    if (m == 2) {
      final isLeap = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
      return isLeap ? 29 : 28;
    }
    const days30 = {4, 6, 9, 11};
    return days30.contains(m) ? 30 : 31;
  }

  /// Adds [days] calendar days. Uses UTC DateTime arithmetic to avoid DST distortion.
  ReportDate addDays(int days) {
    final dt = DateTime.utc(year, month, day).add(Duration(days: days));
    return ReportDate(dt.year, dt.month, dt.day);
  }

  /// Subtracts [days] calendar days.
  ReportDate subtractDays(int days) => addDays(-days);

  /// Inclusive calendar day count between this and [other].
  ///
  /// For example, 2026-10-01 to 2026-10-01 is 1 day.
  /// 2026-10-01 to 2026-10-07 is 7 days.
  int daysToInclusive(ReportDate other) {
    final a = DateTime.utc(year, month, day);
    final b = DateTime.utc(other.year, other.month, other.day);
    return b.difference(a).inDays + 1;
  }

  int differenceInDays(ReportDate other) => (daysToInclusive(other) - 1).abs();

  /// Formatted as yyyy-MM-dd string.
  String toIso8601Date() {
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$year-$m-$d';
  }

  /// Formatted for human reading: dd/MM/yyyy.
  String toDisplayString() {
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$d/$m/$year';
  }

  String formatDisplay() => toDisplayString();

  @override
  int compareTo(ReportDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  bool operator <(ReportDate other) => compareTo(other) < 0;
  bool operator <=(ReportDate other) => compareTo(other) <= 0;
  bool operator >(ReportDate other) => compareTo(other) > 0;
  bool operator >=(ReportDate other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportDate &&
          other.year == year &&
          other.month == month &&
          other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso8601Date();
}

/// Represents an inclusive calendar date range [fromDate] to [toDate].
class ReportDateRange {
  const ReportDateRange({required this.fromDate, required this.toDate});

  final ReportDate fromDate;
  final ReportDate toDate;

  /// Max allowable inclusive range per backend specification (366 days).
  static const int maxInclusiveDays = 366;

  /// Validates the range rules.
  String? validate() {
    if (fromDate > toDate) {
      return 'Ngày bắt đầu ($fromDate) phải trước hoặc bằng ngày kết thúc ($toDate).';
    }
    final days = inclusiveDays;
    if (days > maxInclusiveDays) {
      return 'Khoảng thời gian tối đa là $maxInclusiveDays ngày (khoảng hiện tại: $days ngày).';
    }
    return null;
  }

  bool get isValid => validate() == null;

  int get inclusiveDays => fromDate.daysToInclusive(toDate);
  int get daysCount => inclusiveDays;

  /// Presets based on an anchor [today] (from restaurant timezone or local clock).
  static ReportDateRange today([ReportDate? today]) {
    final t = today ?? ReportDate.today();
    return ReportDateRange(fromDate: t, toDate: t);
  }

  static ReportDateRange yesterday([ReportDate? today]) {
    final t = today ?? ReportDate.today();
    final y = t.subtractDays(1);
    return ReportDateRange(fromDate: y, toDate: y);
  }

  /// Exactly 7 days inclusive: [today - 6 days, today].
  static ReportDateRange last7Days([ReportDate? today]) {
    final t = today ?? ReportDate.today();
    return ReportDateRange(fromDate: t.subtractDays(6), toDate: t);
  }

  /// Exactly 30 days inclusive: [today - 29 days, today].
  static ReportDateRange last30Days([ReportDate? today]) {
    final t = today ?? ReportDate.today();
    return ReportDateRange(fromDate: t.subtractDays(29), toDate: t);
  }

  /// From the 1st of current month up to [today].
  static ReportDateRange thisMonth([ReportDate? today]) {
    final t = today ?? ReportDate.today();
    return ReportDateRange(fromDate: ReportDate(t.year, t.month, 1), toDate: t);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportDateRange &&
          other.fromDate == fromDate &&
          other.toDate == toDate;

  @override
  int get hashCode => Object.hash(fromDate, toDate);

  @override
  String toString() =>
      '${fromDate.toIso8601Date()} -> ${toDate.toIso8601Date()}';
}
