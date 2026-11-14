import 'package:flutter/widgets.dart';

/// Where remote pictures come from. Screens never pick a loading or caching
/// library themselves; they show pictures through `AppNetworkImage`, which
/// asks this for the bytes.
abstract interface class NetworkImageSource {
  /// The picture at [url], full size; the caller decides the decode size.
  ImageProvider<Object> provider(String url);
}
