import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../domain/entities/report_enums.dart';
import '../../domain/entities/revenue_series_point.dart';

class RevenueSeriesChart extends StatefulWidget {
  final List<RevenueSeriesPoint> points;
  final String currencyCode;
  final ReportGranularity granularity;
  final ValueChanged<ReportGranularity> onGranularityChanged;
  final bool showCollected;
  final bool showCompleted;
  final VoidCallback onToggleCollected;
  final VoidCallback onToggleCompleted;
  final bool isTableView;
  final VoidCallback onToggleTableView;

  const RevenueSeriesChart({
    super.key,
    required this.points,
    required this.currencyCode,
    required this.granularity,
    required this.onGranularityChanged,
    required this.showCollected,
    required this.showCompleted,
    required this.onToggleCollected,
    required this.onToggleCompleted,
    required this.isTableView,
    required this.onToggleTableView,
  });

  @override
  State<RevenueSeriesChart> createState() => _RevenueSeriesChartState();
}

class _RevenueSeriesChartState extends State<RevenueSeriesChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Title and Controls
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.show_chart,
                      size: 22,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Xu hướng doanh thu (${widget.currencyCode})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Granularity Segmented Button
                    SegmentedButton<ReportGranularity>(
                      segments: const [
                        ButtonSegment(
                          value: ReportGranularity.day,
                          label: Text('Theo ngày'),
                        ),
                        ButtonSegment(
                          value: ReportGranularity.month,
                          label: Text('Theo tháng'),
                        ),
                      ],
                      selected: {widget.granularity},
                      onSelectionChanged: (selected) {
                        widget.onGranularityChanged(selected.first);
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    // Table / Chart View Switch
                    IconButton(
                      tooltip: widget.isTableView
                          ? 'Xem biểu đồ'
                          : 'Xem dạng bảng',
                      icon: Icon(
                        widget.isTableView
                            ? Icons.bar_chart
                            : Icons.table_chart_outlined,
                      ),
                      onPressed: widget.onToggleTableView,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Legend chips
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                FilterChip(
                  avatar: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0284C7), // Blue
                      shape: BoxShape.circle,
                    ),
                  ),
                  label: const Text('Tiền đã thu'),
                  selected: widget.showCollected,
                  onSelected: (_) => widget.onToggleCollected(),
                ),
                FilterChip(
                  avatar: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEA580C), // Orange
                      shape: BoxShape.circle,
                    ),
                  ),
                  label: const Text('Doanh số hoàn tất'),
                  selected: widget.showCompleted,
                  onSelected: (_) => widget.onToggleCompleted(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Chart or Table View
            if (widget.isTableView)
              _buildTableView(theme)
            else
              _buildChartArea(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildChartArea(ThemeData theme) {
    if (widget.points.isEmpty) {
      return Container(
        height: 280,
        alignment: Alignment.center,
        child: Text(
          'Không có dữ liệu trong khoảng thời gian này.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const height = 300.0;

        return MouseRegion(
          onHover: (event) {
            final idx = _calcIndexAt(event.localPosition.dx, width);
            if (idx != _hoveredIndex) {
              setState(() => _hoveredIndex = idx);
            }
          },
          onExit: (_) {
            if (_hoveredIndex != null) {
              setState(() => _hoveredIndex = null);
            }
          },
          child: GestureDetector(
            onTapDown: (details) {
              final idx = _calcIndexAt(details.localPosition.dx, width);
              setState(() => _hoveredIndex = idx);
            },
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(width, height),
                  painter: _SeriesChartPainter(
                    points: widget.points,
                    showCollected: widget.showCollected,
                    showCompleted: widget.showCompleted,
                    hoveredIndex: _hoveredIndex,
                    theme: theme,
                    granularity: widget.granularity,
                    currencyCode: widget.currencyCode,
                  ),
                ),
                if (_hoveredIndex != null &&
                    _hoveredIndex! >= 0 &&
                    _hoveredIndex! < widget.points.length)
                  _buildTooltipOverlay(
                    widget.points[_hoveredIndex!],
                    width,
                    height,
                    theme,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  int? _calcIndexAt(double x, double totalWidth) {
    if (widget.points.isEmpty) return null;
    const leftPad = 65.0;
    const rightPad = 24.0;
    final chartWidth = totalWidth - leftPad - rightPad;
    if (chartWidth <= 0) return null;

    if (x < leftPad || x > totalWidth - rightPad) return null;

    final n = widget.points.length;
    if (n == 1) return 0;

    final step = chartWidth / (n - 1);
    final relativeX = x - leftPad;
    final idx = (relativeX / step).round();
    return idx.clamp(0, n - 1);
  }

  Widget _buildTooltipOverlay(
    RevenueSeriesPoint point,
    double totalWidth,
    double totalHeight,
    ThemeData theme,
  ) {
    const leftPad = 65.0;
    const rightPad = 24.0;
    final chartWidth = totalWidth - leftPad - rightPad;
    final n = widget.points.length;
    final step = n > 1 ? chartWidth / (n - 1) : chartWidth / 2;
    final xPos = n > 1 ? leftPad + _hoveredIndex! * step : leftPad + step;

    final isRightSide = xPos > totalWidth * 0.55;

    return Positioned(
      left: isRightSide ? math.max(8.0, xPos - 250) : xPos + 12,
      top: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: Colors.grey.shade900.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              point.bucketStartDate.formatDisplay(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const Divider(color: Colors.white24, height: 12),
            if (widget.showCollected) ...[
              Row(
                children: [
                  const Icon(Icons.circle, size: 8, color: Color(0xFF0284C7)),
                  const SizedBox(width: 6),
                  const Text(
                    'Tiền đã thu: ',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Expanded(
                    child: Text(
                      point.collectedAmount.formatted,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 2),
                child: Text(
                  '${point.successfulPaymentCount} giao dịch thành công',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (widget.showCompleted) ...[
              Row(
                children: [
                  const Icon(Icons.circle, size: 8, color: Color(0xFFEA580C)),
                  const SizedBox(width: 6),
                  const Text(
                    'Doanh số hoàn tất: ',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Expanded(
                    child: Text(
                      point.completedOrderSalesAmount.formatted,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 2),
                child: Text(
                  '${point.completedOrderCount} đơn hoàn tất',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTableView(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Mốc thời gian')),
          DataColumn(label: Text('Tiền đã thu'), numeric: true),
          DataColumn(label: Text('Giao dịch'), numeric: true),
          DataColumn(label: Text('Doanh số hoàn tất'), numeric: true),
          DataColumn(label: Text('Đơn hoàn tất'), numeric: true),
        ],
        rows: widget.points.map((p) {
          return DataRow(
            cells: [
              DataCell(Text(p.bucketStartDate.formatDisplay())),
              DataCell(
                Text(
                  p.collectedAmount.formatted,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              DataCell(Text('${p.successfulPaymentCount}')),
              DataCell(
                Text(
                  p.completedOrderSalesAmount.formatted,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              DataCell(Text('${p.completedOrderCount}')),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _SeriesChartPainter extends CustomPainter {
  final List<RevenueSeriesPoint> points;
  final bool showCollected;
  final bool showCompleted;
  final int? hoveredIndex;
  final ThemeData theme;
  final ReportGranularity granularity;
  final String currencyCode;

  _SeriesChartPainter({
    required this.points,
    required this.showCollected,
    required this.showCompleted,
    required this.hoveredIndex,
    required this.theme,
    required this.granularity,
    required this.currencyCode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 65.0;
    const rightPad = 24.0;
    const topPad = 24.0;
    const bottomPad = 36.0;

    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = size.height - topPad - bottomPad;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    // Calculate maximum value for Y-axis scale
    double maxVal = 0.0;
    for (final p in points) {
      if (showCollected) {
        maxVal = math.max(maxVal, p.collectedAmount.toDouble());
      }
      if (showCompleted) {
        maxVal = math.max(maxVal, p.completedOrderSalesAmount.toDouble());
      }
    }

    // Zero-safe guard: if all amounts are 0, use a baseline scale
    if (maxVal <= 0.0) {
      maxVal = 1000000.0; // 1M baseline scale
    } else {
      // Add 10% head room
      maxVal *= 1.1;
    }

    // Grid lines and Y labels
    final gridPaint = Paint()
      ..color = theme.colorScheme.outlineVariant.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;

    final textStyle = TextStyle(color: theme.colorScheme.outline, fontSize: 11);

    const numYTicks = 4;
    for (int i = 0; i <= numYTicks; i++) {
      final yRatio = i / numYTicks;
      final y = topPad + chartHeight * (1.0 - yRatio);
      final tickVal = maxVal * yRatio;

      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        gridPaint,
      );

      final label = _formatCompactY(tickVal);
      final textSpan = TextSpan(text: label, style: textStyle);
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
      )..layout(maxWidth: leftPad - 8);

      tp.paint(canvas, Offset(leftPad - tp.width - 8, y - tp.height / 2));
    }

    final n = points.length;
    final step = n > 1 ? chartWidth / (n - 1) : chartWidth / 2;

    // X axis labels
    final int labelStep = math.max(1, (n / 7).ceil());
    for (int i = 0; i < n; i++) {
      if (i % labelStep != 0 && i != n - 1) continue;

      final x = n > 1 ? leftPad + i * step : leftPad + step;
      final p = points[i];
      final label = granularity == ReportGranularity.month
          ? 'T${p.bucketStartDate.month}/${p.bucketStartDate.year % 100}'
          : '${p.bucketStartDate.day.toString().padLeft(2, '0')}/${p.bucketStartDate.month.toString().padLeft(2, '0')}';

      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();

      tp.paint(canvas, Offset(x - tp.width / 2, size.height - bottomPad + 8));
    }

    // Hover vertical guideline
    if (hoveredIndex != null && hoveredIndex! >= 0 && hoveredIndex! < n) {
      final hx = n > 1 ? leftPad + hoveredIndex! * step : leftPad + step;
      final guidePaint = Paint()
        ..color = theme.colorScheme.primary.withValues(alpha: 0.5)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(hx, topPad),
        Offset(hx, size.height - bottomPad),
        guidePaint,
      );
    }

    // Series 1: Collected Amount (Blue)
    if (showCollected) {
      _drawSeries(
        canvas: canvas,
        points: points.map((p) => p.collectedAmount.toDouble()).toList(),
        maxVal: maxVal,
        color: const Color(0xFF0284C7),
        leftPad: leftPad,
        topPad: topPad,
        chartHeight: chartHeight,
        step: step,
        n: n,
        hoveredIndex: hoveredIndex,
      );
    }

    // Series 2: Completed Order Sales Amount (Orange)
    if (showCompleted) {
      _drawSeries(
        canvas: canvas,
        points: points
            .map((p) => p.completedOrderSalesAmount.toDouble())
            .toList(),
        maxVal: maxVal,
        color: const Color(0xFFEA580C),
        leftPad: leftPad,
        topPad: topPad,
        chartHeight: chartHeight,
        step: step,
        n: n,
        hoveredIndex: hoveredIndex,
      );
    }
  }

  void _drawSeries({
    required Canvas canvas,
    required List<double> points,
    required double maxVal,
    required Color color,
    required double leftPad,
    required double topPad,
    required double chartHeight,
    required double step,
    required int n,
    required int? hoveredIndex,
  }) {
    if (points.isEmpty) return;

    final linePath = Path();
    final fillPath = Path();

    final coords = <Offset>[];
    for (int i = 0; i < n; i++) {
      final x = n > 1 ? leftPad + i * step : leftPad + step;
      final val = points[i];
      final yRatio = (val / maxVal).clamp(0.0, 1.0);
      final y = topPad + chartHeight * (1.0 - yRatio);
      coords.add(Offset(x, y));
    }

    linePath.moveTo(coords[0].dx, coords[0].dy);
    fillPath.moveTo(coords[0].dx, topPad + chartHeight);
    fillPath.lineTo(coords[0].dx, coords[0].dy);

    for (int i = 1; i < coords.length; i++) {
      linePath.lineTo(coords[i].dx, coords[i].dy);
      fillPath.lineTo(coords[i].dx, coords[i].dy);
    }

    fillPath.lineTo(coords.last.dx, topPad + chartHeight);
    fillPath.close();

    // Area fill gradient
    final fillPaint = Paint()
      ..shader =
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromLTWH(leftPad, topPad, step * (n - 1), chartHeight),
          );

    canvas.drawPath(fillPath, fillPaint);

    // Stroke line
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(linePath, strokePaint);

    // Data points dots
    final dotPaint = Paint()..color = Colors.white;
    final dotBorderPaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < coords.length; i++) {
      final isHovered = (hoveredIndex == i);
      final radius = isHovered ? 5.5 : 3.5;

      canvas.drawCircle(coords[i], radius, dotPaint);
      canvas.drawCircle(coords[i], radius, dotBorderPaint);
    }
  }

  String _formatCompactY(double value) {
    if (value <= 0) return '0';
    if (value >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(1)}B';
    }
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}k';
    }
    return value.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _SeriesChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.showCollected != showCollected ||
        oldDelegate.showCompleted != showCompleted ||
        oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.granularity != granularity;
  }
}
