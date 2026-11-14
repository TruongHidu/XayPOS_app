import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/theme/app_colors.dart';
import 'package:pos_saas_app/app/theme/app_status_colors.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/ui/controllers/minute_clock.dart';
import 'package:pos_saas_app/core/ui/widgets/app_search_field.dart';
import 'package:pos_saas_app/core/ui/widgets/app_section_card.dart';
import 'package:pos_saas_app/core/ui/widgets/confirm_dialog.dart';
import 'package:pos_saas_app/core/ui/widgets/elapsed_text.dart';
import 'package:pos_saas_app/core/ui/widgets/list_states.dart';
import 'package:pos_saas_app/core/ui/widgets/money_text.dart';
import 'package:pos_saas_app/core/ui/widgets/responsive_sliver_columns.dart';
import 'package:pos_saas_app/core/ui/widgets/section_header.dart';
import 'package:pos_saas_app/core/ui/widgets/stat_tile.dart';
import 'package:pos_saas_app/core/ui/widgets/status_badge.dart';

Widget _app(Widget child, {double width = 400}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  testWidgets('StatusBadge paints the tone colours', (tester) async {
    await tester.pumpWidget(
      _app(
        const Align(
          child: StatusBadge(
            label: 'Hết hàng',
            tone: AppTone.danger,
            icon: Icons.block,
          ),
        ),
      ),
    );
    expect(find.text('Hết hàng'), findsOneWidget);
    final box = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.text('Hết hàng'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).color, AppColors.dangerSoft);
    final text = tester.widget<Text>(find.text('Hết hàng'));
    expect(text.style?.color, AppColors.dangerStrong);
  });

  testWidgets('a long StatusBadge ellipsizes instead of overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const StatusBadge(label: 'Một trạng thái rất dài không vừa chỗ'),
        width: 80,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('section header and card show title, subtitle and action', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      _app(
        AppSectionCard(
          title: 'Thông tin nhà hàng',
          subtitle: 'Tên, địa chỉ',
          trailing: const Text('Sửa'),
          onTap: () => tapped++,
          child: const Text('Nội dung'),
        ),
      ),
    );
    expect(find.byType(SectionHeader), findsOneWidget);
    expect(find.text('Tên, địa chỉ'), findsOneWidget);
    await tester.tap(find.text('Nội dung'));
    expect(tapped, 1);
  });

  testWidgets('StatTile fits a 320 px phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _app(
          const StatTile(
            label: 'Doanh thu hôm nay',
            value: '12.500.000 đ',
            hint: 'Tăng 12% so với hôm qua',
            icon: Icons.payments_outlined,
          ),
          width: 320,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('12.500.000 đ'), findsOneWidget);
  });

  testWidgets('MoneyText formats the API decimal', (tester) async {
    await tester.pumpWidget(_app(const MoneyText('1250000.00', currency: 'đ')));
    expect(find.text('1.250.000 đ'), findsOneWidget);
  });

  testWidgets('ErrorBanner and ErrorState offer a retry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            ErrorBanner(
              message: 'Mất kết nối',
              details: 'Kiểm tra mạng',
              actions: [RetryButton(onPressed: () => retries++)],
            ),
            ErrorState(message: 'Không tải được', onRetry: () => retries++),
          ],
        ),
      ),
    );
    expect(find.text('Kiểm tra mạng'), findsOneWidget);
    await tester.tap(find.text('Thử lại').first);
    await tester.tap(find.text('Thử lại').last);
    expect(retries, 2);
  });

  testWidgets('AppSearchField debounces and clears', (tester) async {
    final values = <String>[];
    await tester.pumpWidget(
      _app(
        AppSearchField(
          debounce: const Duration(milliseconds: 300),
          onChanged: values.add,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'phở');
    expect(values, isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    expect(values, ['phở']);
    await tester.pump();
    await tester.tap(find.byTooltip('Xoá tìm kiếm'));
    await tester.pump();
    expect(values, ['phở', '']);
    expect(find.byTooltip('Xoá tìm kiếm'), findsNothing);
  });

  testWidgets('showAppConfirmDialog returns the choice', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showAppConfirmDialog(
              context,
              title: 'Huỷ đơn?',
              message: 'Không thể hoàn tác.',
              confirmLabel: 'Huỷ đơn',
              destructive: true,
            ),
            child: const Text('Mở'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Huỷ đơn'));
    await tester.pumpAndSettle();
    expect(result, isTrue);

    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('ResponsiveSliverColumns builds rows lazily', (tester) async {
    final built = <int>{};
    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 600,
          child: CustomScrollView(
            slivers: [
              ResponsiveSliverColumns(
                itemCount: 200,
                minColumnWidth: 180,
                maxColumns: 2,
                itemBuilder: (context, i) {
                  built.add(i);
                  return SizedBox(height: 100, child: Text('Món $i'));
                },
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Món 0'), findsOneWidget);
    expect(find.text('Món 1'), findsOneWidget);
    expect(built.length, lessThan(40));
  });

  test('MinuteClock ticks on the minute only while listened to', () {
    fakeAsync((async) {
      final start = DateTime(2026, 11, 14, 10, 0, 30);
      final clock = MinuteClock(now: () => start.add(async.elapsed));
      var ticks = 0;
      void listener() => ticks++;
      clock.addListener(listener);
      async.elapse(const Duration(seconds: 29));
      expect(ticks, 0);
      async.elapse(const Duration(seconds: 1));
      expect(ticks, 1);
      async.elapse(const Duration(minutes: 2));
      expect(ticks, 3);
      clock.removeListener(listener);
      expect(async.pendingTimers, isEmpty);
      clock.dispose();
    });
  });

  testWidgets('ElapsedText turns red past the warning time', (tester) async {
    final now = DateTime(2026, 11, 14, 10);
    final clock = MinuteClock(now: () => now);
    addTearDown(clock.dispose);
    await tester.pumpWidget(
      _app(
        ElapsedText(
          since: now.subtract(const Duration(minutes: 25)),
          warnAfter: const Duration(minutes: 20),
          clock: clock,
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('25 phút'));
    expect(text.style?.color, AppTheme.light.colorScheme.error);
  });
}
