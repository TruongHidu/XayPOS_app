class PackageFeature {
  const PackageFeature({required this.code, this.limits = const {}});

  final String code;
  final Map<String, dynamic> limits;
}
