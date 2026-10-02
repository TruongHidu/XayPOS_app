abstract final class Environment {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.13:8080',
  );

  static const cashierWebUrl = String.fromEnvironment('CASHIER_WEB_URL');
}
