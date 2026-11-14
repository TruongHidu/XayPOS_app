/// Turns a stored image address into one for a picture about [width] pixels
/// wide, when the image host can resize on its side. Hosts that cannot get
/// the address back unchanged.
abstract interface class ImageUrlSizer {
  String sized(String url, {required int width});
}
