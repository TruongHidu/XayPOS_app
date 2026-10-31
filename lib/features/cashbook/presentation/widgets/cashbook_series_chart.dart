import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../reports/domain/entities/report_money.dart';
import '../../domain/entities/cashbook_enums.dart';
import '../../domain/entities/cashbook_records.dart';
import 'cashbook_common.dart';
import 'cashbook_format.dart';

/// Paired income/expense bars per bucket with the difference as a line.
/// A table view gives exact figures for every bucket.
class CashbookSeriesChart extends StatefulWidget {
  const CashbookSeriesChart({
    super.key,
    required this.points,
    required this.currency,
    required this.granularity,
    required this.onGranularity,
    this.loading = false,
  });

  final List<CashbookSeriesPoint> points;
  final String currency;
  final CashbookGranularity granularity;
  final ValueChanged<CashbookGranularity> onGranularity;
  final bool loading;

  @override
  State<CashbookSeriesChart> createState() => _CashbookSeriesChartState();
}

class _CashbookSeriesChartState extends State<CashbookSeriesChart> {
  bool _table = false;
  int? _selected;
  final _visible = [true, true, true];
  static const _labels = ['Thu', 'Chi', 'Chênh lệch'];

  @override
  void didUpdateWidget(covariant CashbookSeriesChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) _selected = null;
  }

  List<Color> _colors(ColorScheme colors) => [
    CashbookColors.income(colors),
    CashbookColors.expense(colors),
    colors.primary,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _colors(theme.colorScheme);
    final empty = widget.points.every((p) => p.isEmpty);
    return CashbookCard(
      title: 'Dòng tiền theo ${widget.granularity.label.toLowerCase()}',
      subtitle: 'Đơn vị: ${widget.currency}',
      icon: Icons.bar_chart,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<CashbookGranularity>(
            showSelectedIcon: false,
            segments: [
              for (final g in CashbookGranularity.values)
                ButtonSegment(value: g, label: Text(g.label)),
            ],
            selected: {widget.granularity},
            onSelectionChanged: widget.loading
                ? null
                : (value) => widget.onGranularity(value.first),
          ),
          IconButton(
            key: const ValueKey('cashbook-series-mode'),
            tooltip: _table ? 'Xem biểu đồ' : 'Xem bảng số liệu',
            onPressed: () => setState(() => _table = !_table),
            icon: Icon(_table ? Icons.bar_chart : Icons.table_rows_outlined),
          ),
        ],
      ),
      child: empty
          ? const CashbookEmptyState(
              icon: Icons.show_chart,
              message: 'Chưa có giao dịch thu chi trong kỳ này.',
            )
          : _table
          ? _buildTable(context)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < _labels.length; i++)
                      FilterChip(
                        avatar: Icon(
                          i == 2 ? Icons.show_chart : Icons.square_rounded,
                          size: 16,
                          color: colors[i],
                        ),
                        label: Text(_labels[i]),
                        selected: _visible[i],
                        showCheckmark: false,
                        onSelected: (value) {
                          if (!value && _visible.where((v) => v).length == 1) {
                            return;
                          }
                          setState(() => _visible[i] = value);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildChart(context, colors),
                const SizedBox(height: 12),
                _buildDetail(context, colors),
              ],
            ),
    );
  }

  List<double> _values(CashbookSeriesPoint p) => [
    p.totalIncomeAmount.toDouble(),
    p.totalExpenseAmount.toDouble(),
    p.netCashFlowAmount.toDouble(),
  ];

  Widget _buildChart(BuildContext context, List<Color> colors) {
    final theme = Theme.of(context);
    final points = widget.points;
    final values = points.map(_values).toList();
    var minimum = 0.0, maximum = 0.0;
    for (final row in values) {
      for (var i = 0; i < 3; i++) {
        if (!_visible[i]) continue;
        minimum = math.min(minimum, row[i]);
        maximum = math.max(maximum, row[i]);
      }
    }
    final ticks = _ticks(minimum, maximum);
    final labelStyle = theme.textTheme.labelSmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final tickLabels = [
      for (final tick in ticks) ReportMoney.parse(tick).formatCompact(),
    ];
    var leftInset = 0.0;
    for (final label in tickLabels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      leftInset = math.max(leftInset, painter.width);
      painter.dispose();
    }
    leftInset += 8;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = width < 600 ? 220.0 : 280.0;
        void select(Offset position) {
          final plot = math.max(1.0, width - leftInset - 8);
          final slot = plot / points.length;
          final index = ((position.dx - leftInset) / slot).floor().clamp(
            0,
            points.length - 1,
          );
          if (_selected != index) setState(() => _selected = index);
        }

        return Semantics(
          label: 'Biểu đồ thu chi theo kỳ. Chọn Xem bảng số liệu để đọc số.',
          child: MouseRegion(
            onHover: (event) => select(event.localPosition),
            child: GestureDetector(
              key: const ValueKey('cashbook-series-chart'),
              onTapDown: (event) => select(event.localPosition),
              onHorizontalDragUpdate: (event) => select(event.localPosition),
              child: SizedBox(
                height: height,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SeriesPainter(
                    values: values,
                    colors: colors,
                    visible: List.of(_visible),
                    selected: _selected,
                    ticks: ticks,
                    tickLabels: tickLabels,
                    xLabels: [
                      for (final p in points)
                        cashbookBucketLabel(
                          p.bucketStartDate,
                          widget.granularity,
                        ),
                    ],
                    leftInset: leftInset,
                    labelStyle: labelStyle,
                    textScaler: scaler,
                    gridColor: theme.colorScheme.outlineVariant,
                    axisColor: theme.colorScheme.outline,
                    highlight: theme.colorScheme.primary.withValues(
                      alpha: 0.08,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetail(BuildContext context, List<Color> colors) {
    final theme = Theme.of(context);
    final index = _selected;
    final decoration = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
    );
    if (index == null || index >= widget.points.length) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: decoration,
        child: Row(
          children: [
            Icon(Icons.touch_app_outlined, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Chạm hoặc rê chuột lên cột để xem chi tiết kỳ.'),
            ),
          ],
        ),
      );
    }
    final point = widget.points[index];
    final currency = widget.currency;
    Widget value(String label, String amount, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(
          amount,
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
    return Container(
      key: const ValueKey('cashbook-series-detail'),
      padding: const EdgeInsets.all(12),
      decoration: decoration,
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            widget.granularity == CashbookGranularity.month
                ? 'Tháng ${cashbookBucketLabel(point.bucketStartDate, widget.granularity)}'
                : 'Ngày ${point.bucketStartDate.formatDisplay()}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          value(
            'Thu (${point.incomeEntryCount})',
            cashbookMoney(point.totalIncomeAmount, currency),
            colors[0],
          ),
          value(
            'Chi (${point.expenseEntryCount})',
            cashbookMoney(point.totalExpenseAmount, currency),
            colors[1],
          ),
          value(
            'Chênh lệch',
            cashbookMoney(point.netCashFlowAmount, currency),
            point.netCashFlowAmount.isNegative
                ? theme.colorScheme.error
                : colors[2],
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final theme = Theme.of(context);
    final currency = widget.currency;
    DataCell money(ReportMoney value, {Color? color}) => DataCell(
      Text(
        cashbookMoney(value, currency),
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        key: const ValueKey('cashbook-series-table'),
        columnSpacing: 24,
        headingTextStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        columns: const [
          DataColumn(label: Text('Kỳ')),
          DataColumn(label: Text('Thu'), numeric: true),
          DataColumn(label: Text('Chi'), numeric: true),
          DataColumn(label: Text('Chênh lệch'), numeric: true),
          DataColumn(label: Text('Số giao dịch'), numeric: true),
        ],
        rows: [
          for (final p in widget.points)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    widget.granularity == CashbookGranularity.month
                        ? cashbookBucketLabel(
                            p.bucketStartDate,
                            widget.granularity,
                          )
                        : p.bucketStartDate.formatDisplay(),
                  ),
                ),
                money(p.totalIncomeAmount),
                money(p.totalExpenseAmount),
                money(
                  p.netCashFlowAmount,
                  color: p.netCashFlowAmount.isNegative
                      ? theme.colorScheme.error
                      : null,
                ),
                DataCell(Text('${p.incomeEntryCount + p.expenseEntryCount}')),
              ],
            ),
        ],
      ),
    );
  }

  /// Round axis steps (1, 2, 2.5, 5 × 10ⁿ) that always include zero.
  static List<double> _ticks(double minimum, double maximum) {
    if (minimum == maximum) return [0, 1];
    final raw = (maximum - minimum) / 4;
    final magnitude = math
        .pow(10, (math.log(raw) / math.ln10).floor())
        .toDouble();
    final normalized = raw / magnitude;
    final step =
        magnitude *
        (normalized <= 1
            ? 1
            : normalized <= 2
            ? 2
            : normalized <= 2.5
            ? 2.5
            : normalized <= 5
            ? 5
            : 10);
    final start = (minimum / step).floor() * step;
    final end = (maximum / step).ceil() * step;
    return [for (var tick = start; tick <= end + step / 2; tick += step) tick];
  }
}

class _SeriesPainter extends CustomPainter {
  const _SeriesPainter({
    required this.values,
    required this.colors,
    required this.visible,
    required this.selected,
    required this.ticks,
    required this.tickLabels,
    required this.xLabels,
    required this.leftInset,
    required this.labelStyle,
    required this.textScaler,
    required this.gridColor,
    required this.axisColor,
    required this.highlight,
  });

  final List<List<double>> values;
  final List<Color> colors;
  final List<bool> visible;
  final int? selected;
  final List<double> ticks;
  final List<String> tickLabels, xLabels;
  final double leftInset;
  final TextStyle labelStyle;
  final TextScaler textScaler;
  final Color gridColor, axisColor, highlight;
  static const _rightInset = 8.0;

  TextPainter _text(String text) => TextPainter(
    text: TextSpan(text: text, style: labelStyle),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || ticks.length < 2) return;
    final sample = _text('0');
    final bottomInset = sample.height + 8;
    final topInset = sample.height / 2 + 2;
    sample.dispose();
    final plotWidth = math.max(1.0, size.width - leftInset - _rightInset);
    final plotHeight = math.max(1.0, size.height - topInset - bottomInset);
    final minimum = ticks.first, maximum = ticks.last;
    final range = maximum == minimum ? 1.0 : maximum - minimum;
    final slot = plotWidth / values.length;
    double center(int index) => leftInset + slot * (index + 0.5);
    double y(double amount) =>
        topInset + plotHeight - (amount - minimum) / range * plotHeight;

    if (selected != null && selected! < values.length) {
      canvas.drawRect(
        Rect.fromLTWH(leftInset + slot * selected!, topInset, slot, plotHeight),
        Paint()..color = highlight,
      );
    }

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < ticks.length; i++) {
      final lineY = y(ticks[i]);
      canvas.drawLine(
        Offset(leftInset, lineY),
        Offset(size.width - _rightInset, lineY),
        ticks[i] == 0
            ? (Paint()
                ..color = axisColor
                ..strokeWidth = 1.5)
            : grid,
      );
      final label = _text(tickLabels[i]);
      label.paint(
        canvas,
        Offset(leftInset - 8 - label.width, lineY - label.height / 2),
      );
      label.dispose();
    }

    // Label as many buckets as fit without overlapping.
    double lastRight = -double.infinity;
    final step = math.max(
      1,
      (values.length / math.max(1, plotWidth / 56)).ceil(),
    );
    for (var index = 0; index < values.length; index += step) {
      final label = _text(xLabels[index]);
      final left = (center(index) - label.width / 2)
          .clamp(0.0, math.max(0.0, size.width - label.width))
          .toDouble();
      if (left > lastRight + 6) {
        label.paint(canvas, Offset(left, size.height - label.height));
        lastRight = left + label.width;
      }
      label.dispose();
    }

    final bars = [0, 1].where((i) => visible[i]).toList();
    if (bars.isNotEmpty) {
      // Dense ranges on phones drop the gaps so bars stay visible.
      final group = math.min(slot * 0.9, 48.0);
      final barWidth = group / bars.length;
      final gap = barWidth < 6 ? 0.0 : 1.0;
      final zero = y(0);
      for (var index = 0; index < values.length; index++) {
        final start = center(index) - group / 2;
        for (var b = 0; b < bars.length; b++) {
          final top = y(values[index][bars[b]]);
          final rect = Rect.fromLTRB(
            start + barWidth * b + gap,
            math.min(top, zero),
            start + barWidth * (b + 1) - gap,
            math.max(top, zero),
          );
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              rect,
              topLeft: const Radius.circular(3),
              topRight: const Radius.circular(3),
            ),
            Paint()..color = colors[bars[b]],
          );
        }
      }
    }

    if (visible[2]) {
      final path = Path();
      for (var index = 0; index < values.length; index++) {
        final point = Offset(center(index), y(values[index][2]));
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[2]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
      for (var index = 0; index < values.length; index++) {
        if (values.length > 31 && index != selected) continue;
        canvas.drawCircle(
          Offset(center(index), y(values[index][2])),
          index == selected ? 5 : 3,
          Paint()..color = colors[2],
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter oldDelegate) => true;
}
