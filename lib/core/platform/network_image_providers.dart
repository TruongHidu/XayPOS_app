import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/images/image_url_sizer.dart';
import '../ui/images/network_image_source.dart';
import 'cached_network_image_source.dart';
import 'cloudinary_image_url_sizer.dart';

/// One disk-backed source for the whole app; tests override it with a fake.
final networkImageSourceProvider = Provider<NetworkImageSource>(
  (ref) => CachedNetworkImageSource(),
);

/// Menu photos are stored on Cloudinary; another host would plug in here.
final imageUrlSizerProvider = Provider<ImageUrlSizer>(
  (ref) => const CloudinaryImageUrlSizer(),
);
