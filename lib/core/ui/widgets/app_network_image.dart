import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/network_image_providers.dart';
import '../images/image_sizing.dart';

/// The one way screens show a remote picture: sized for the box it sits in,
/// fetched pre-sized from the image host, decoded at that size and kept on
/// disk. Features never touch a network image or caching library directly.
class AppNetworkImage extends ConsumerWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.error,
    this.fit = BoxFit.cover,
    this.maxExtent = 2048,
    this.oversample = 1,
  });

  /// Null or empty shows [placeholder] without any request.
  final String? url;

  /// Shown while loading, and on failure unless [error] is given.
  final Widget placeholder;
  final Widget? error;
  final BoxFit fit;

  /// Largest pixel width ever requested or decoded, for full-screen views.
  final int maxExtent;

  /// More pixels than the box needs, for views the user can zoom into.
  final double oversample;

  /// Cropping to fill a box needs the short side of a wide photo to cover
  /// it: asking 1.5× the box keeps a 16:9 photo sharp in a square.
  static const _coverHeadroom = 1.5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = url?.trim();
    if (address == null || address.isEmpty) return placeholder;
    final source = ref.watch(networkImageSourceProvider);
    final sizer = ref.watch(imageUrlSizerProvider);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context);
        final boxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : screen.width;
        final boxHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : boxWidth;
        final logical =
            (fit == BoxFit.cover
                ? (boxWidth > boxHeight ? boxWidth : boxHeight) * _coverHeadroom
                : boxWidth) *
            oversample;
        final width = decodeExtent(logical, ratio, max: maxExtent);
        final image = ResizeImage.resizeIfNeeded(
          width,
          null,
          source.provider(sizer.sized(address, width: width)),
        );
        return Image(
          image: image,
          fit: fit,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, synchronous) =>
              frame == null && !synchronous ? placeholder : child,
          errorBuilder: (_, _, _) => error ?? placeholder,
        );
      },
    );
  }
}
