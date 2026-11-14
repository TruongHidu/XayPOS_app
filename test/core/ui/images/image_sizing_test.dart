import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/platform/cloudinary_image_url_sizer.dart';
import 'package:pos_saas_app/core/ui/images/image_sizing.dart';

void main() {
  test('decode size follows the screen, in steps of 64, up to a cap', () {
    expect(decodeExtent(72, 3), 256); // 216 → 256
    expect(decodeExtent(48, 2), 128); // 96 → 128
    expect(decodeExtent(64, 1), 64);
    expect(decodeExtent(65, 1), 128);
    expect(decodeExtent(1200, 3), 2048);
    expect(decodeExtent(1200, 3, max: 1024), 1024);
    expect(decodeExtent(0, 3), 64);
    expect(decodeExtent(-5, 3), 64);
    expect(decodeExtent(double.infinity, 3), 64);
    expect(decodeExtent(100, 0), 128);
  });

  group('Cloudinary sizing', () {
    const sizer = CloudinaryImageUrlSizer();
    const original =
        'https://res.cloudinary.com/demo/image/upload/v1731/xaypos/r1/menu/abc.jpg';

    test('asks for a picture no wider than needed', () {
      expect(
        sizer.sized(original, width: 256),
        'https://res.cloudinary.com/demo/image/upload/'
        'c_limit,w_256,q_auto,f_auto/v1731/xaypos/r1/menu/abc.jpg',
      );
    });

    test('a sized address passed back in is resized, not stacked', () {
      final once = sizer.sized(original, width: 256);
      expect(
        sizer.sized(once, width: 1024),
        sizer.sized(original, width: 1024),
      );
    });

    test('other hosts and odd addresses stay as they are', () {
      for (final url in [
        'https://example.com/image/upload/a.jpg',
        'https://res.cloudinary.com/demo/video/upload/v1/a.mp4',
        'https://res.cloudinary.com/demo/raw/upload/v1/a.pdf',
        'not a url',
        '',
      ]) {
        expect(sizer.sized(url, width: 256), url);
      }
      expect(sizer.sized(original, width: 0), original);
    });
  });
}
