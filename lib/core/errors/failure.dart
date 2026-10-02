enum FailureType {
  validation,
  unauthorized,
  notFound,
  conflict,
  invalidCredentials,
  restaurantInactive,
  invalidRefreshToken,
  subscriptionNotActive,
  featureNotEntitled,
  forbidden,
  network,
  internal,
}

class Failure {
  const Failure({
    required this.type,
    required this.message,
    this.code,
    this.fieldErrors = const {},
  });

  final FailureType type;
  final String message;
  final String? code;
  final Map<String, String> fieldErrors;

  bool get isNetwork => type == FailureType.network;
}
