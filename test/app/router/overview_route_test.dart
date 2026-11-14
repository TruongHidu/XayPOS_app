import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/features/overview/presentation/screens/overview_screen.dart';
import '../../features/order/order_fakes.dart';
import '../../features/order/order_widget_test.dart' show pumpOrder;

void main() {
  testWidgets('the real router opens Tổng quan', (tester) async {
    final container = await pumpOrder(
      tester,
      useRouter: true,
      permissions: {...orderPermissions, 'REPORT_DAILY_VIEW'},
      features: {...orderFeatures, 'DAILY_REVENUE'},
    );
    container.read(appRouterProvider).go('/app/overview');
    await tester.pumpAndSettle();
    expect(find.byType(OverviewScreen), findsOneWidget);
    expect(find.textContaining('no routes for location'), findsNothing);
  });
}
