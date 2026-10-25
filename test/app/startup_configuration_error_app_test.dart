import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/startup_configuration_error_app.dart';

void main() {
  testWidgets(
    'configuration error fits large text and prevents concurrent retry',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final retry = Completer<void>();
      var attempts = 0;
      await tester.pumpWidget(
        StartupConfigurationErrorApp(
          onRetry: () {
            attempts++;
            return retry.future;
          },
        ),
      );
      await tester.ensureVisible(find.text('Thử lại'));
      await tester.tap(find.text('Thử lại'));
      await tester.pump();
      expect(attempts, 1);
      final retryButton = find.byWidgetPredicate(
        (widget) => widget is FilledButton,
      );
      expect(tester.widget<FilledButton>(retryButton).onPressed, isNull);
      await tester.tap(find.text('Thử lại'));
      expect(attempts, 1);
      expect(tester.takeException(), isNull);

      retry.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(retryButton).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}
