import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/ui/formatters/elapsed.dart';
import '../tables/table_fakes.dart';
import 'order_widget_test.dart' show pumpOrder;

Finder _count(String filter, String value) => find.descendant(
  of: find.byKey(ValueKey('table-filter-$filter')),
  matching: find.text(value),
);

void main() {
  testWidgets('filters show how many tables each one holds', (tester) async {
    await pumpOrder(
      tester,
      tables: TableServer()..table = tableJson(occupied: true),
    );
    expect(find.byKey(const ValueKey('order-table-grid')), findsOneWidget);
    expect(_count('null', '1'), findsOneWidget);
    expect(_count('true', '1'), findsOneWidget);
    expect(_count('false', '0'), findsOneWidget);
    expect(find.byKey(const ValueKey('table-seated-info')), findsOneWidget);
    expect(find.textContaining('6 khách · '), findsOneWidget);

    await tester.tap(find.text('Sử dụng'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('table-filter-true'))),
      containsSemantics(isSelected: true, isButton: true),
    );
    expect(tester.takeException(), isNull);
  });

  test('elapsed time reads the way staff say it', () {
    expect(formatElapsed(const Duration(seconds: 30)), 'Vừa vào');
    expect(formatElapsed(const Duration(minutes: 45)), '45 phút');
    expect(formatElapsed(const Duration(minutes: 65)), '1 giờ 5 phút');
    expect(formatElapsed(const Duration(hours: 2)), '2 giờ');
    expect(formatElapsed(const Duration(hours: 51)), '2 ngày 3 giờ');
  });
}
