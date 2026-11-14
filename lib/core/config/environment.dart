import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart' show rootBundle;

final class EnvironmentLoadException implements Exception {
  const EnvironmentLoadException();

  @override
  String toString() => 'Application configuration could not be loaded.';
}

/// Client configuration loaded before the application's providers are created.
abstract final class Environment {
  static const _overrides = {
    if (bool.hasEnvironment('API_BASE_URL'))
      'API_BASE_URL': String.fromEnvironment('API_BASE_URL'),
    if (bool.hasEnvironment('CASHIER_WEB_URL'))
      'CASHIER_WEB_URL': String.fromEnvironment('CASHIER_WEB_URL'),
    if (bool.hasEnvironment('REALTIME_ENABLED'))
      'REALTIME_ENABLED': String.fromEnvironment('REALTIME_ENABLED'),
    if (bool.hasEnvironment('REALTIME_TRANSPORT'))
      'REALTIME_TRANSPORT': String.fromEnvironment('REALTIME_TRANSPORT'),
    if (bool.hasEnvironment('REALTIME_URL'))
      'REALTIME_URL': String.fromEnvironment('REALTIME_URL'),
    if (bool.hasEnvironment('PRIVACY_POLICY_URL'))
      'PRIVACY_POLICY_URL': String.fromEnvironment('PRIVACY_POLICY_URL'),
    if (bool.hasEnvironment('TERMS_URL'))
      'TERMS_URL': String.fromEnvironment('TERMS_URL'),
    if (bool.hasEnvironment('SUPPORT_WEB_URL'))
      'SUPPORT_WEB_URL': String.fromEnvironment('SUPPORT_WEB_URL'),
    if (bool.hasEnvironment('SUPPORT_PHONE'))
      'SUPPORT_PHONE': String.fromEnvironment('SUPPORT_PHONE'),
    if (bool.hasEnvironment('REGISTER_URL'))
      'REGISTER_URL': String.fromEnvironment('REGISTER_URL'),
    if (bool.hasEnvironment('SUBSCRIBE_URL'))
      'SUBSCRIBE_URL': String.fromEnvironment('SUBSCRIBE_URL'),
  };

  static Future<void> load() async {
    rootBundle.evict('.env');
    try {
      await dotenv.load(fileName: '.env');
    } on FileNotFoundError {
      throw const EnvironmentLoadException();
    } on EmptyEnvFileError {
      throw const EnvironmentLoadException();
    }
  }

  static String get apiBaseUrl =>
      _nonEmpty('API_BASE_URL', 'http://localhost:8080');

  static String get cashierWebUrl => _value('CASHIER_WEB_URL');

  static bool get realtimeEnabled {
    final value = _value('REALTIME_ENABLED').toLowerCase();
    return switch (value) {
      '' || 'false' || '0' => false,
      'true' || '1' => true,
      _ => throw const FormatException(
        'REALTIME_ENABLED must be true or false',
      ),
    };
  }

  static String get realtimeTransport =>
      _nonEmpty('REALTIME_TRANSPORT', 'websocket');

  static String get realtimeUrl => _value('REALTIME_URL');

  /// Public pages linked from Cài đặt; a link is hidden while its URL is empty.
  static String get privacyPolicyUrl => _value('PRIVACY_POLICY_URL');

  static String get termsUrl => _value('TERMS_URL');

  /// Website linked from the login screen; hidden while empty.
  static String get supportWebUrl => _value('SUPPORT_WEB_URL');

  /// Hotline shown on the login screen and dialled when tapped.
  static String get supportPhone => _nonEmpty('SUPPORT_PHONE', '1900 6522');

  /// Restaurant sign-up happens on the web; the login screen links here.
  static String get registerUrl =>
      _nonEmpty('REGISTER_URL', 'https://xaypos.hiducourse.click/register');

  /// Where an owner buys or renews a package (the web onboarding page).
  static String get subscribeUrl =>
      _nonEmpty('SUBSCRIBE_URL', 'https://xaypos.hiducourse.click/onboarding');

  static String _nonEmpty(String key, String fallback) {
    final value = _value(key);
    return value.isEmpty ? fallback : value;
  }

  static String _value(String key) =>
      (_overrides[key] ?? (dotenv.isInitialized ? dotenv.env[key] : null) ?? '')
          .trim();
}
