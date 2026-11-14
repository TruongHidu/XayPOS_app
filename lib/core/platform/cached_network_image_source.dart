import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../ui/images/network_image_source.dart';

/// Remote pictures kept on disk, so menu photos load once rather than on
/// every launch. The only place in the app that knows the caching library.
class CachedNetworkImageSource implements NetworkImageSource {
  CachedNetworkImageSource({BaseCacheManager Function()? createManager})
    : _createManager = createManager ?? _defaultManager;

  static const cacheKey = 'xaypos_images';

  final BaseCacheManager Function() _createManager;

  /// Opened on first use: building the source touches no plugin, so start-up
  /// and tests that never show a photo pay nothing.
  late final BaseCacheManager _manager = _createManager();

  /// Pictures arrive pre-sized (see the image URL sizer), so a few hundred
  /// stay small on disk; unused ones expire after a month.
  static BaseCacheManager _defaultManager() => CacheManager(
    Config(
      cacheKey,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 500,
    ),
  );

  @override
  ImageProvider<Object> provider(String url) =>
      CachedNetworkImageProvider(url, cacheManager: _manager);
}
