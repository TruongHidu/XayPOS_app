import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Remote pictures go through AppNetworkImage, which sizes, caches and asks
/// the host for small copies. Using Flutter's network image directly would
/// bring back full-size downloads and decodes; only the platform adapter may
/// touch the caching library.
void main() {
  test('screens show remote pictures only through AppNetworkImage', () {
    final direct = RegExp(r'Image\.network\(|(?<![A-Za-z_])NetworkImage\(');
    final library = RegExp(
      r'''import\s+['"]package:(cached_network_image|flutter_cache_manager)/''',
    );
    // The patterns themselves: catch the real thing, never our widget.
    expect(direct.hasMatch('Image.network(url)'), isTrue);
    expect(direct.hasMatch('child: NetworkImage(url)'), isTrue);
    expect(direct.hasMatch('AppNetworkImage(url: url)'), isFalse);
    expect(
      library.hasMatch(
        "import 'package:cached_network_image/cached_network_image.dart';",
      ),
      isTrue,
    );
    const adapter = 'lib/core/platform/cached_network_image_source.dart';
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll('\\', '/');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (direct.hasMatch(line) ||
            (library.hasMatch(line) && !path.endsWith(adapter))) {
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use AppNetworkImage (lib/core/ui/widgets/app_network_image.dart):\n'
          '${offenders.join('\n')}',
    );
  });
}
