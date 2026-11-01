import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/ui/widgets/list_states.dart';
import 'package:pos_saas_app/core/ui/widgets/responsive_dialog.dart';

Widget _app(Widget child, {double width = 800}) => MediaQuery(
  data: MediaQueryData(size: Size(width, 800)),
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('the loading strip keeps its height either way', (tester) async {
    await tester.pumpWidget(_app(const LoadingStrip(loading: true)));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final loading = tester.getSize(find.byType(LoadingStrip)).height;

    await tester.pumpWidget(_app(const LoadingStrip(loading: false)));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.getSize(find.byType(LoadingStrip)).height, loading);
  });

  testWidgets('the skeleton does not animate, so screens can settle', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const ListSkeleton(count: 3)));
    expect(await tester.pumpAndSettle(), 1);
  });

  testWidgets('an empty state shows its message and hint', (tester) async {
    await tester.pumpWidget(
      _app(
        const EmptyState(
          icon: Icons.inbox_outlined,
          message: 'Chưa có dữ liệu',
          hint: 'Bấm nút + để thêm',
        ),
      ),
    );
    expect(find.text('Chưa có dữ liệu'), findsOneWidget);
    expect(find.text('Bấm nút + để thêm'), findsOneWidget);
  });

  testWidgets('dialogs sit at the bottom on phones only', (tester) async {
    Widget dialog(double width) => MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: const MaterialApp(
        home: Scaffold(body: ResponsiveDialog(child: Text('Nội dung'))),
      ),
    );
    await tester.pumpWidget(dialog(390));
    expect(
      tester.widget<Dialog>(find.byType(Dialog)).alignment,
      Alignment.bottomCenter,
    );
    await tester.pumpWidget(dialog(800));
    expect(tester.widget<Dialog>(find.byType(Dialog)).alignment, isNull);
  });
}
