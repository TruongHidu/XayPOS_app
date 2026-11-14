import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Number of columns that fit [width] at [minColumnWidth] each.
int responsiveColumnCount(
  double width, {
  required double minColumnWidth,
  required int maxColumns,
  required double spacing,
}) => ((width + spacing) / (minColumnWidth + spacing)).floor().clamp(
  1,
  maxColumns,
);

/// The lazy sliver form of `ResponsiveColumns`: cards in as many columns as
/// fit, each row as tall as its tallest card, built only as rows scroll into
/// view. Use it for lists that grow page by page (menu, orders, stock).
class ResponsiveSliverColumns extends StatelessWidget {
  const ResponsiveSliverColumns({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.minColumnWidth = 280,
    this.maxColumns = 3,
    this.spacing = 16,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minColumnWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final columns = responsiveColumnCount(
        constraints.crossAxisExtent,
        minColumnWidth: minColumnWidth,
        maxColumns: maxColumns,
        spacing: spacing,
      );
      final rows = (itemCount / columns).ceil();
      return SliverList.builder(
        itemCount: rows,
        itemBuilder: (context, row) {
          final start = row * columns;
          final end = math.min(start + columns, itemCount);
          return Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : spacing),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = start; i < start + columns; i++) ...[
                  if (i > start) SizedBox(width: spacing),
                  Expanded(
                    child: i < end
                        ? itemBuilder(context, i)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        },
      );
    },
  );
}
