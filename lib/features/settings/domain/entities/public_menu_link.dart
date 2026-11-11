/// The restaurant-wide customer menu link (takeaway / no table).
class PublicMenuLink {
  const PublicMenuLink({
    required this.menuToken,
    required this.menuPath,
    this.menuUrl,
  });

  final String menuToken;
  final String menuPath;

  /// Absolute link encoded in the QR; null on older servers.
  final String? menuUrl;
}
