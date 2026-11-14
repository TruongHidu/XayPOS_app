/// Pixel size to decode (and request) an image shown [logicalPx] wide on a
/// screen with [devicePixelRatio], so a 72px thumbnail never costs the memory
/// of a full camera photo.
///
/// Rounded up to a multiple of 64 so the same photo shown at slightly
/// different sizes shares one cached copy; capped at [max].
int decodeExtent(double logicalPx, double devicePixelRatio, {int max = 2048}) {
  if (!logicalPx.isFinite || logicalPx <= 0) return 64;
  final ratio = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  final physical = (logicalPx * ratio).ceil();
  final bucketed = ((physical + 63) ~/ 64) * 64;
  return bucketed > max ? max : bucketed;
}
