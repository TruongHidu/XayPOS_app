import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../reports/domain/entities/report_enums.dart';
import '../../../reports/domain/entities/report_money.dart';
import '../../domain/entities/reference_margin_enums.dart';
import '../../domain/entities/reference_margin_report.dart';
import 'reference_margin_common.dart';
import 'reference_margin_format.dart';

class MarginSeries extends StatefulWidget {
  const MarginSeries({
    super.key,
    required this.points,
    required this.currency,
    required this.granularity,
    required this.onGranularity,
    required this.layout,
    this.loading = false,
  });
  final List<ReferenceMarginSeriesPoint> points;
  final String currency;
  final ReportGranularity granularity;
  final ValueChanged<ReportGranularity> onGranularity;
  final MarginLayout layout;
  final bool loading;
  @override
  State<MarginSeries> createState() => _MarginSeriesState();
}

class _MarginSeriesState extends State<MarginSeries> {
  bool _table = false;
  int? _selected;
  final List<bool> _visible = [true, true, true];
  static const _labels = [
    'Doanh số thuần đủ giá vốn',
    'Giá vốn tham chiếu',
    'Lãi tham chiếu',
  ];
  static const _rightInset = 12.0;

  List<double> _values(ReferenceMarginSeriesPoint point) => [
    point.metrics.coveredNetSalesAmount.toDouble(),
    point.metrics.coveredReferenceCostAmount.toDouble(),
    point.metrics.coveredReferenceMarginAmount.toDouble(),
  ];

  @override
  void didUpdateWidget(covariant MarginSeries oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = [
      theme.colorScheme.primary,
      theme.colorScheme.tertiary,
      theme.colorScheme.error,
    ];
    final points = widget.points;
    final drawable = points.every((p) => _values(p).every((v) => v.isFinite));
    return MarginSectionCard(
      title: 'Xu hướng nhóm đủ giá vốn (${widget.currency})',
      icon: Icons.show_chart,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final granularity in ReportGranularity.values)
            ChoiceChip(
              label: Text(granularity.label),
              selected: widget.granularity == granularity,
              onSelected: widget.loading
                  ? null
                  : (_) => widget.onGranularity(granularity),
            ),
          TextButton.icon(
            key: const ValueKey('margin-series-mode'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => setState(() => _table = !_table),
            icon: Icon(_table ? Icons.show_chart : Icons.table_chart_outlined),
            label: Text(_table ? 'Xem biểu đồ' : 'Xem bảng'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (points.isEmpty)
            const MarginNotice(
              message: 'Chưa có dữ liệu xu hướng trong kỳ này.',
            )
          else if (_table || !drawable)
            _buildTable(context)
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _labels.length; i++)
                  FilterChip(
                    avatar: Icon(
                      i == 0
                          ? Icons.circle
                          : i == 1
                          ? Icons.square
                          : Icons.change_history,
                      size: 16,
                      color: colors[i],
                    ),
                    label: Text(_labels[i]),
                    selected: _visible[i],
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
            LayoutBuilder(
              builder: (context, constraints) {
                final side =
                    widget.layout == MarginLayout.expanded &&
                    constraints.maxWidth >= 900;
                final chart = _buildChart(context, colors);
                final detail = _buildDetail(context);
                if (!side) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [chart, const SizedBox(height: 12), detail],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: chart),
                    const SizedBox(width: 16),
                    SizedBox(width: 300, child: detail),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Tỷ lệ tổng nằm ở phần Tổng quan; không lấy trung bình tỷ lệ các kỳ.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context, List<Color> colors) {
    final theme = Theme.of(context);
    final points = widget.points;
    final values = points.map(_values).toList();
    var minimum = 0.0, maximum = 0.0;
    for (final row in values) {
      for (var i = 0; i < _visible.length; i++) {
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
    final height = widget.layout == MarginLayout.compact ? 240.0 : 300.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void select(Offset position) {
          final plot = math.max(1.0, width - leftInset - _rightInset);
          final fraction = ((position.dx - leftInset) / plot).clamp(0.0, 1.0);
          final index = points.length == 1
              ? 0
              : (fraction * (points.length - 1)).round();
          if (_selected != index) setState(() => _selected = index);
        }

        return Semantics(
          label:
              'Biểu đồ giá vốn và lãi tham chiếu. Chọn Xem bảng để đọc từng kỳ.',
          child: MouseRegion(
            onHover: (event) => select(event.localPosition),
            child: GestureDetector(
              key: const ValueKey('margin-series-chart'),
              onTapDown: (event) => select(event.localPosition),
              onHorizontalDragUpdate: (event) => select(event.localPosition),
              child: SizedBox(
                height: height,
                width: double.infinity,
                child: CustomPaint(
                  painter: _MarginSeriesPainter(
                    values: values,
                    empty: [
                      for (final point in points)
                        point.metrics.costCoverageStatus ==
                            CostCoverageStatus.noData,
                    ],
                    colors: colors,
                    visible: List.of(_visible),
                    selected: _selected,
                    ticks: ticks,
                    tickLabels: tickLabels,
                    xLabels: [
                      for (final point in points)
                        marginBucketLabel(
                          point.bucketStartDate,
                          widget.granularity,
                        ),
                    ],
                    leftInset: leftInset,
                    rightInset: _rightInset,
                    labelStyle: labelStyle,
                    textScaler: scaler,
                    gridColor: theme.colorScheme.outlineVariant,
                    axisColor: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetail(BuildContext context) {
    final theme = Theme.of(context);
    final points = widget.points;
    final index = _selected;
    final decoration = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
    );
    if (index == null || index >= points.length) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: decoration,
        child: Row(
          children: [
            Icon(Icons.touch_app_outlined, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Chạm hoặc rê chuột lên biểu đồ để xem từng kỳ.'),
            ),
          ],
        ),
      );
    }
    final point = points[index];
    final metrics = point.metrics;
    final currency = widget.currency;
    return Container(
      key: const ValueKey('margin-series-detail'),
      padding: const EdgeInsets.all(12),
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.granularity == ReportGranularity.month
                ? 'Tháng ${marginBucketLabel(point.bucketStartDate, widget.granularity)}'
                : 'Ngày ${point.bucketStartDate.formatDisplay()}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: MarginCoverageChip(status: metrics.costCoverageStatus),
          ),
          const SizedBox(height: 6),
          Text(
            'Hoàn tất: ${metrics.completedOrderCount} đơn · Đủ giá vốn: ${metrics.fullyCostedOrderCount} đơn',
            style: theme.textTheme.bodySmall,
          ),
          const Divider(height: 16),
          for (var i = 0; i < _labels.length; i++)
            MarginAmountRow(
              label: _labels[i],
              value: marginMoney(
                [
                  metrics.coveredNetSalesAmount,
                  metrics.coveredReferenceCostAmount,
                  metrics.coveredReferenceMarginAmount,
                ][i],
                currency,
              ),
              emphasis: i == 2,
              negative:
                  i == 2 && metrics.coveredReferenceMarginAmount.isNegative,
            ),
          MarginAmountRow(
            label: 'Tỷ lệ lãi của kỳ',
            value: marginPercent(metrics.coveredReferenceMarginPercent),
            unknown: metrics.coveredReferenceMarginPercent == null,
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

  Widget _buildTable(BuildContext context) {
    final theme = Theme.of(context);
    final scale = marginTextScale(context);
    final currency = widget.currency;
    DataCell money(ReportMoney value, {bool margin = false}) => DataCell(
      SizedBox(
        width: 150 * scale,
        child: Text(
          marginMoney(value, currency),
          textAlign: TextAlign.right,
          style: TextStyle(
            color: margin && value.isNegative ? theme.colorScheme.error : null,
            fontWeight: margin ? FontWeight.w600 : null,
          ),
        ),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        key: const ValueKey('margin-series-table'),
        dataRowMinHeight: 56,
        dataRowMaxHeight: 140 * scale,
        headingRowHeight: 64 * scale,
        columnSpacing: 20,
        headingTextStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        columns: const [
          DataColumn(label: Text('Kỳ')),
          DataColumn(label: Text('Đủ giá / hoàn tất'), numeric: true),
          DataColumn(label: Text('Doanh số thuần'), numeric: true),
          DataColumn(label: Text('Giá vốn'), numeric: true),
          DataColumn(label: Text('Lãi tham chiếu'), numeric: true),
          DataColumn(label: Text('Tỷ lệ lãi'), numeric: true),
        ],
        rows: [
          for (final point in widget.points)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    widget.granularity == ReportGranularity.month
                        ? marginBucketLabel(
                            point.bucketStartDate,
                            widget.granularity,
                          )
                        : point.bucketStartDate.formatDisplay(),
                  ),
                ),
                DataCell(
                  Text(
                    '${point.metrics.fullyCostedOrderCount}/${point.metrics.completedOrderCount}',
                  ),
                ),
                money(point.metrics.coveredNetSalesAmount),
                money(point.metrics.coveredReferenceCostAmount),
                money(point.metrics.coveredReferenceMarginAmount, margin: true),
                DataCell(
                  Text(
                    marginPercent(point.metrics.coveredReferenceMarginPercent),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MarginSeriesPainter extends CustomPainter {
  const _MarginSeriesPainter({
    required this.values,
    required this.empty,
    required this.colors,
    required this.visible,
    required this.selected,
    required this.ticks,
    required this.tickLabels,
    required this.xLabels,
    required this.leftInset,
    required this.rightInset,
    required this.labelStyle,
    required this.textScaler,
    required this.gridColor,
    required this.axisColor,
  });
  final List<List<double>> values;
  final List<bool> empty;
  final List<Color> colors;
  final List<bool> visible;
  final int? selected;
  final List<double> ticks;
  final List<String> tickLabels, xLabels;
  final double leftInset, rightInset;
  final TextStyle labelStyle;
  final TextScaler textScaler;
  final Color gridColor, axisColor;

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
    final plotWidth = math.max(1.0, size.width - leftInset - rightInset);
    final plotHeight = math.max(1.0, size.height - topInset - bottomInset);
    final minimum = ticks.first, maximum = ticks.last;
    final range = maximum == minimum ? 1.0 : maximum - minimum;
    double x(int index) => values.length == 1
        ? leftInset + plotWidth / 2
        : leftInset + index * plotWidth / (values.length - 1);
    double y(double amount) =>
        topInset + plotHeight - (amount - minimum) / range * plotHeight;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < ticks.length; i++) {
      final lineY = y(ticks[i]);
      canvas.drawLine(
        Offset(leftInset, lineY),
        Offset(size.width - rightInset, lineY),
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

    // First, middle and last bucket labels keep the axis readable on phones.
    final xIndexes = <int>{0, (values.length - 1) ~/ 2, values.length - 1};
    double lastRight = -double.infinity;
    for (final index in xIndexes.toList()..sort()) {
      final label = _text(xLabels[index]);
      final left = (x(index) - label.width / 2)
          .clamp(0.0, math.max(0.0, size.width - label.width))
          .toDouble();
      if (left > lastRight + 8) {
        label.paint(canvas, Offset(left, size.height - label.height));
        lastRight = left + label.width;
      }
      label.dispose();
    }

    if (selected != null && selected! < values.length) {
      canvas.drawLine(
        Offset(x(selected!), topInset),
        Offset(x(selected!), topInset + plotHeight),
        Paint()
          ..color = axisColor
          ..strokeWidth = 1,
      );
    }

    for (var series = 0; series < visible.length; series++) {
      if (!visible[series]) continue;
      final path = Path();
      for (var index = 0; index < values.length; index++) {
        final point = Offset(x(index), y(values[index][series]));
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[series]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
      for (var index = 0; index < values.length; index++) {
        final center = Offset(x(index), y(values[index][series]));
        final highlighted = index == selected;
        if (empty[index] && !highlighted) {
          // A bucket without completed orders is a gap in data, not a result.
          canvas.drawCircle(
            center,
            2.5,
            Paint()
              ..color = colors[series].withValues(alpha: 0.35)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        } else if (highlighted || values.length <= 31) {
          canvas.drawCircle(
            center,
            highlighted ? 5 : 3,
            Paint()..color = colors[series],
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MarginSeriesPainter oldDelegate) => true;
}
