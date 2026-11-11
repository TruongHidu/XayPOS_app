import 'stock_shortage.dart';

export 'stock_shortage.dart';

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
    this.stockShortage,
  });

  final FailureType type;
  final String message;
  final String? code;
  final Map<String, String> fieldErrors;

  /// Which dishes ran short, when the server explained an
  /// INSUFFICIENT_AVAILABLE_STOCK refusal.
  final StockShortage? stockShortage;

  bool get isNetwork => type == FailureType.network;
}
