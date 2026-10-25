import '../config/environment.dart';

enum RealtimeTransportMode { polling, websocket }

class RealtimeConfig {
  const RealtimeConfig({
    this.enabled = false,
    String? apiBaseUrl,
    this.urlOverride = '',
    this.requireSecure = false,
    this.debounce = const Duration(milliseconds: 400),
    this.mode = RealtimeTransportMode.websocket,
    this.pollingInterval = const Duration(seconds: 20),
  }) : _apiBaseUrl = apiBaseUrl;
  static RealtimeConfig get environment => RealtimeConfig(
    enabled: Environment.realtimeEnabled,
    apiBaseUrl: Environment.apiBaseUrl,
    urlOverride: Environment.realtimeUrl,
    requireSecure: const bool.fromEnvironment('dart.vm.product'),
    mode: Environment.realtimeTransport == 'polling'
        ? RealtimeTransportMode.polling
        : RealtimeTransportMode.websocket,
  );
  final bool enabled, requireSecure;
  final String? _apiBaseUrl;
  String get apiBaseUrl => _apiBaseUrl ?? Environment.apiBaseUrl;
  final String urlOverride;
  final Duration debounce;
  final RealtimeTransportMode mode;
  final Duration pollingInterval;

  Uri get endpoint {
    final override = urlOverride.trim();
    final source = Uri.parse(override.isEmpty ? apiBaseUrl : override);
    if (source.host.isEmpty ||
        source.userInfo.isNotEmpty ||
        source.hasQuery ||
        source.hasFragment) {
      throw const FormatException('Invalid realtime URL');
    }
    final scheme = override.isEmpty
        ? switch (source.scheme) {
            'http' => 'ws',
            'https' => 'wss',
            _ => throw const FormatException('Invalid REST URL scheme'),
          }
        : source.scheme;
    if (!{'ws', 'wss'}.contains(scheme) || requireSecure && scheme != 'wss') {
      throw const FormatException('Secure realtime URL required');
    }
    var path = source.path.replaceFirst(RegExp(r'/+$'), '');
    if (override.isEmpty) {
      path = path.replaceFirst(RegExp(r'/api/v1$'), '');
      path = '$path/ws';
    }
    return Uri(
      scheme: scheme,
      host: source.host,
      port: source.hasPort ? source.port : null,
      path: path,
    );
  }
}
