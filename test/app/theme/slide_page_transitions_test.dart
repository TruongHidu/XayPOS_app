import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/app/theme/slide_page_transitions.dart';

void main() {
  Future<GoRouter> pump(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget page(String text) => Scaffold(body: Center(child: Text(text)));
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        GoRoute(path: '/a', builder: (_, _) => page('A')),
        GoRoute(path: '/b', builder: (_, _) => page('B')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  double centerX(WidgetTester tester, String text) =>
      tester.getCenter(find.text(text)).dx;

  test('every platform but iOS uses the slide', () {
    final builders = AppTheme.light.pageTransitionsTheme.builders;
    for (final platform in TargetPlatform.values) {
      expect(
        builders[platform],
        platform == TargetPlatform.iOS
            ? isA<CupertinoPageTransitionsBuilder>()
            : isA<SlidePageTransitionsBuilder>(),
        reason: platform.name,
      );
    }
  });

  testWidgets('push slides in from the right over the moving old page', (
    tester,
  ) async {
    final router = await pump(tester);
    router.push('/b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(centerX(tester, 'B'), greaterThan(400));
    expect(centerX(tester, 'A'), lessThan(400));
    await tester.pumpAndSettle();
    expect(centerX(tester, 'B'), 400);
    expect(find.text('A', skipOffstage: true), findsNothing);
    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(centerX(tester, 'B'), greaterThan(400));
    await tester.pumpAndSettle();
    expect(centerX(tester, 'A'), 400);
  });

  testWidgets('go keeps the old page under the slide instead of a blank gap', (
    tester,
  ) async {
    final router = await pump(tester);
    router.go('/b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('A'), findsOneWidget);
    expect(centerX(tester, 'B'), greaterThan(400));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);
  });

  testWidgets('reduced motion switches at once', (tester) async {
    final router = await pump(tester, reduceMotion: true);
    router.push('/b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(centerX(tester, 'B'), 400);
  });
}
