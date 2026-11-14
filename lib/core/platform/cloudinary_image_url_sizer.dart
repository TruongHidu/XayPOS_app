import '../ui/images/image_url_sizer.dart';

/// Asks Cloudinary for a picture no wider than needed, in the best format and
/// quality for the device (`f_auto,q_auto`), instead of the original upload
/// of up to 5 MB. Only the address used for display changes; the stored one
/// stays the original.
class CloudinaryImageUrlSizer implements ImageUrlSizer {
  const CloudinaryImageUrlSizer();

  static const _host = 'res.cloudinary.com';
  static const _upload = '/image/upload/';

  @override
  String sized(String url, {required int width}) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != _host || width < 1) return url;
    final at = url.indexOf(_upload);
    if (at < 0) return url;
    final head = url.substring(0, at + _upload.length);
    var tail = url.substring(at + _upload.length);
    // Already sized by us (e.g. a sized address passed back in): replace it.
    final ours = RegExp(r'^c_limit,w_\d+,q_auto,f_auto/');
    tail = tail.replaceFirst(ours, '');
    return '${head}c_limit,w_$width,q_auto,f_auto/$tail';
  }
}
