import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/platform/network_image_providers.dart';
import 'package:pos_saas_app/core/ui/images/network_image_source.dart';
import 'package:pos_saas_app/core/ui/widgets/app_network_image.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_details.dart';

/// 1×1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class _FakeSource implements NetworkImageSource {
  _FakeSource({this.broken = false});
  final bool broken;
  final requested = <String>[];

  @override
  ImageProvider<Object> provider(String url) {
    requested.add(url);
    return MemoryImage(broken ? Uint8List.fromList([1, 2, 3]) : _png);
  }
}

const _cloudinary =
    'https://res.cloudinary.com/demo/image/upload/v1/xaypos/r1/menu/abc.jpg';

Future<void> _pump(
  WidgetTester tester,
  _FakeSource source,
  Widget child, {
  double ratio = 3,
}) async {
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [networkImageSourceProvider.overrideWithValue(source)],
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  // Real image decoding happens outside the fake clock.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}

ResizeImage _shown(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image)).image as ResizeImage;

void main() {
  testWidgets('a thumbnail asks for and decodes a small picture', (
    tester,
  ) async {
    final source = _FakeSource();
    await _pump(
      tester,
      source,
      const SizedBox.square(
        dimension: 72,
        child: AppNetworkImage(url: _cloudinary, placeholder: Text('chờ')),
      ),
    );
    // 72px box, cropped to fill (×1.5), on a 3× screen → 324 → 384.
    expect(source.requested, [
      'https://res.cloudinary.com/demo/image/upload/'
          'c_limit,w_384,q_auto,f_auto/v1/xaypos/r1/menu/abc.jpg',
    ]);
    expect(_shown(tester).width, 384);
    expect(find.text('chờ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fitted picture uses the box width only', (tester) async {
    final source = _FakeSource();
    await _pump(
      tester,
      source,
      const SizedBox(
        width: 100,
        height: 300,
        child: AppNetworkImage(
          url: 'https://cdn.example.com/a.jpg',
          fit: BoxFit.contain,
          placeholder: SizedBox.shrink(),
        ),
      ),
      ratio: 2,
    );
    expect(source.requested, ['https://cdn.example.com/a.jpg']);
    expect(_shown(tester).width, 256); // 200 → 256
  });

  testWidgets('no address means no request', (tester) async {
    final source = _FakeSource();
    for (final url in [null, '', '   ']) {
      await _pump(
        tester,
        source,
        SizedBox.square(
          dimension: 72,
          child: AppNetworkImage(url: url, placeholder: const Text('trống')),
        ),
      );
      expect(find.text('trống'), findsOneWidget);
    }
    expect(source.requested, isEmpty);
  });

  testWidgets('a picture that fails to load shows the fallback', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeSource(broken: true),
      const SizedBox.square(
        dimension: 72,
        child: AppNetworkImage(
          url: _cloudinary,
          placeholder: Text('chờ'),
          error: Text('lỗi'),
        ),
      ),
    );
    expect(find.text('lỗi'), findsOneWidget);
  });

  testWidgets('menu images go through the shared, sized loader', (
    tester,
  ) async {
    final source = _FakeSource();
    await _pump(
      tester,
      source,
      const SizedBox(
        width: 240,
        child: MenuImage(url: _cloudinary, aspectRatio: 4 / 3),
      ),
      ratio: 2,
    );
    // 240×180 box cropped to fill: 240 × 1.5 × 2 = 720 → 768.
    expect(source.requested.single, contains('c_limit,w_768,'));
    expect(tester.takeException(), isNull);
  });
}
