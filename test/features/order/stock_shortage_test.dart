import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/order_widgets.dart';

Map<String, dynamic> _line({
  String name = 'Phở bò',
  Object requested = 3.000,
  Object max = 1.000,
  bool shared = true,
  bool withIngredients = true,
}) => {
  'orderItemId': '8c1e',
  'menuItemId': '4f2a',
  'itemName': name,
  'requestedQuantity': requested,
  'maxAvailableQuantity': max,
  'unit': 'tô',
  'sharesIngredientWithOtherLines': shared,
  if (withIngredients)
    'shortIngredients': [
      {
        'ingredientId': 'a91d',
        'name': 'Thịt bò',
        'unit': 'g',
        'availableQuantity': 500.000,
        'requiredQuantity': '630.000',
      },
    ],
};

Failure _map(
  Map<String, dynamic> body, {
  String code = 'INSUFFICIENT_AVAILABLE_STOCK',
}) {
  final options = RequestOptions(path: '/api/v1/orders');
  return ApiErrorMapper.fromException(
    DioException(
      requestOptions: options,
      response: Response(
        requestOptions: options,
        statusCode: 409,
        data: {
          'success': false,
          'code': code,
          'message': 'Insufficient available inventory',
          'fieldErrors': <String, String>{},
          ...body,
        },
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Failure failure) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: OrderFailurePanel(failure: failure)),
  ),
);

void main() {
  group('parsing', () {
    test('keeps every line and ingredient for inventory viewers', () {
      final failure = _map({
        'details': {
          'lines': [_line(), _line(name: 'Bò xào', max: 0, shared: false)],
        },
      });
      expect(failure.type, FailureType.conflict);
      final lines = failure.stockShortage!.lines;
      expect(lines.map((l) => l.itemName), ['Phở bò', 'Bò xào']);
      expect(lines.first.requestedQuantity.toString(), '3');
      expect(lines.first.maxAvailableQuantity.toString(), '1');
      expect(lines.first.soldOut, false);
      expect(lines.last.soldOut, true);
      final beef = lines.first.shortIngredients!.single;
      expect(beef.availableQuantity.toString(), '500');
      expect(beef.requiredQuantity.toString(), '630');
    });

    test('missing shortIngredients stays null for staff without inventory', () {
      final failure = _map({
        'details': {
          'lines': [_line(withIngredients: false, requested: 0.33)],
        },
      });
      final line = failure.stockShortage!.lines.single;
      expect(line.shortIngredients, isNull);
      expect(line.requestedQuantity.toString(), '0.33');
    });

    test('no or malformed details fall back to the plain message', () {
      expect(_map({}).stockShortage, isNull);
      expect(_map({}).message, contains('Tồn khả dụng'));
      final broken = _map({
        'details': {
          'lines': [
            {'itemName': 'Phở bò'},
          ],
        },
      });
      expect(broken.stockShortage, isNull);
      expect(broken.type, FailureType.conflict);
      expect(
        _map({
          'details': {
            'lines': [_line()],
          },
        }, code: 'CONCURRENT_ORDER_UPDATE').stockShortage,
        isNull,
      );
    });
  });

  testWidgets('shortage opens a dialog once and can be reopened', (
    tester,
  ) async {
    final failure = _map({
      'details': {
        'lines': [_line(), _line(name: 'Bò xào', max: 0, shared: false)],
      },
    });
    await _pump(tester, failure);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.text('Không đủ nguyên liệu'), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('Phở bò')),
      findsOneWidget,
    );
    expect(find.text('Còn 1 tô'), findsOneWidget);
    expect(find.text('Hết'), findsOneWidget);
    expect(find.text('Đã gọi 3 tô'), findsNWidgets(2));
    expect(find.textContaining('Dùng chung nguyên liệu'), findsOneWidget);
    expect(
      find.textContaining('còn 500 g · cả đơn cần 630 g', findRichText: true),
      findsNWidgets(2),
    );
    await tester.tap(find.text('Đã hiểu'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);

    // Rebuilding with the same refusal must not pop it up again.
    await _pump(tester, failure);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);

    await tester.tap(find.text('Xem 2 món thiếu nguyên liệu'));
    await tester.pumpAndSettle();
    expect(dialog, findsOneWidget);
  });

  for (final width in [320.0, 800.0]) {
    testWidgets('dialog fits $width px at 200% text without ingredients', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final failure = _map({
        'details': {
          'lines': [
            _line(
              name:
                  'Món có tên rất dài để kiểm tra bố cục khi phóng chữ hệ thống',
              max: 12345.5,
              withIngredients: false,
            ),
          ],
        },
      });
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(
            home: Scaffold(body: OrderFailurePanel(failure: failure)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('cả đơn cần'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
