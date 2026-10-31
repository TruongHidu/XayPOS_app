import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/ui/widgets/endless_list_footer.dart';

Widget _list({
  required VoidCallback onLoadMore,
  double rowsHeight = 0,
  bool hasMore = true,
  String? failure,
}) => MaterialApp(
  home: Scaffold(
    body: ListView(
      children: [
        SizedBox(height: rowsHeight),
        EndlessListFooter(
          hasMore: hasMore,
          failureMessage: failure,
          endLabel: 'Hết',
          onLoadMore: onLoadMore,
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('rows shorter than the screen ask for more at once', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(_list(onLoadMore: () => calls++));
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('a long list waits until the user nears the end', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_list(onLoadMore: () => calls++, rowsHeight: 3000));
    await tester.pump();
    expect(calls, 0);
    await tester.drag(find.byType(ListView), const Offset(0, -2500));
    await tester.pump(); // The spinner never settles while rows remain.
    await tester.pump();
    expect(calls, greaterThan(0));
  });

  testWidgets('the end of the list shows its label and stops asking', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(_list(onLoadMore: () => calls++, hasMore: false));
    await tester.pump();
    expect(calls, 0);
    expect(find.text('Hết'), findsOneWidget);
  });

  testWidgets('a failed page waits for an explicit retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _list(onLoadMore: () => calls++, failure: 'Mất kết nối'),
    );
    await tester.pump();
    expect(calls, 0);
    expect(find.text('Mất kết nối'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    expect(calls, 1);
  });

  testWidgets('without a scroll view it falls back to a button', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EndlessListFooter(
            hasMore: true,
            endLabel: 'Hết',
            onLoadMore: () => calls++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(calls, 0);
    await tester.tap(find.text('Tải thêm'));
    expect(calls, 1);
  });
}
