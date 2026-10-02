class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool isExpiringSoon({
    DateTime? now,
    Duration threshold = const Duration(minutes: 1),
  }) {
    return expiresAt.isBefore((now ?? DateTime.now()).add(threshold));
  }
}
