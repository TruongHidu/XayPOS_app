import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/ui/widgets/filter_panel_button.dart';

void main() {
  late ValueNotifier<int> filter;

  Widget app() => MaterialApp(
    home: Scaffold(
      body: SearchFilterRow(
        search: const TextField(),
        filter: FilterPanelButton(
          listenable: filter,
          title: 'Bộ lọc thử',
          activeCount: () => filter.value,
          onClear: () => filter.value = 0,
          filters: () => [
            Text('Giá trị ${filter.value}'),
            TextButton(
              onPressed: () => filter.value++,
              child: const Text('Tăng'),
            ),
          ],
        ),
      ),
    ),
  );

  setUp(() => filter = ValueNotifier(0));
  tearDown(() => filter.dispose());

  testWidgets('the open panel follows live values', (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('Xóa bộ lọc'), findsNothing);

    await tester.tap(find.byTooltip('Bộ lọc'));
    await tester.pumpAndSettle();
    expect(find.text('Bộ lọc thử'), findsOneWidget);
    expect(find.text('Giá trị 0'), findsOneWidget);
    expect(find.text('Xóa bộ lọc'), findsNothing);

    await tester.tap(find.text('Tăng'));
    await tester.pump();
    expect(find.text('Giá trị 1'), findsOneWidget);

    await tester.tap(find.text('Xóa bộ lọc'));
    await tester.pump();
    expect(filter.value, 0);
    expect(find.text('Giá trị 0'), findsOneWidget);
    expect(find.text('Xóa bộ lọc'), findsNothing);
  });

  testWidgets('the button counts active filters', (tester) async {
    filter.value = 2;
    await tester.pumpWidget(app());
    expect(find.text('2'), findsOneWidget);
  });
}
