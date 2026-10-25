import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/config/environment.dart';
import 'package:pos_saas_app/core/network/api_client.dart';
import 'package:pos_saas_app/core/realtime/realtime_config.dart';

import '../../helpers/auth_fakes.dart';

void main() {
  setUp(() => dotenv = DotEnv());
  tearDown(() => dotenv = DotEnv());

  ApiClients clients({String? baseUrl}) {
    final events = SessionEvents();
    final clients = ApiClients(
      tokenStorage: FakeTokenStorage(),
      sessionEvents: events,
      baseUrl: baseUrl,
    );
    addTearDown(() {
      clients.raw.close(force: true);
      clients.authenticated.close(force: true);
      events.dispose();
    });
    return clients;
  }

  test(
    'runtime file drives REST and WebSocket without frozen startup defaults',
    () {
      final beforeLoad = RealtimeConfig.environment;
      dotenv.loadFromString(
        envString: '''
API_BASE_URL=https://runtime.example.test/restaurant/api/v1
REALTIME_ENABLED=true
REALTIME_TRANSPORT=websocket
REALTIME_URL=
''',
      );

      final api = clients();
      final realtime = RealtimeConfig.environment;
      expect(
        api.raw.options.baseUrl,
        'https://runtime.example.test/restaurant/api/v1',
      );
      expect(api.authenticated.options.baseUrl, api.raw.options.baseUrl);
      expect(realtime.apiBaseUrl, api.raw.options.baseUrl);
      expect(
        realtime.endpoint.toString(),
        'wss://runtime.example.test/restaurant/ws',
      );
      expect(realtime.enabled, isTrue);
      expect(realtime.mode, RealtimeTransportMode.websocket);
      expect(beforeLoad.apiBaseUrl, 'http://localhost:8080');
      expect(
        clients(baseUrl: 'https://injected.example.test').raw.options.baseUrl,
        'https://injected.example.test',
      );
    },
  );

  test('explicit dart-define overrides retain false and empty values', () {
    dotenv.loadFromString(
      envString: '''
API_BASE_URL=https://file.example.test/api/v1
CASHIER_WEB_URL=https://cashier.file.example.test
REALTIME_ENABLED=true
REALTIME_TRANSPORT=polling
REALTIME_URL=wss://socket.file.example.test/custom
''',
    );

    const apiUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://file.example.test/api/v1',
    );
    const cashierUrl = String.fromEnvironment(
      'CASHIER_WEB_URL',
      defaultValue: 'https://cashier.file.example.test',
    );
    const enabled = bool.fromEnvironment(
      'REALTIME_ENABLED',
      defaultValue: true,
    );
    const transport = String.fromEnvironment(
      'REALTIME_TRANSPORT',
      defaultValue: 'polling',
    );
    const socketUrl = String.fromEnvironment(
      'REALTIME_URL',
      defaultValue: 'wss://socket.file.example.test/custom',
    );

    final api = clients();
    final realtime = RealtimeConfig.environment;
    expect(api.authenticated.options.baseUrl, apiUrl);
    expect(Environment.cashierWebUrl, cashierUrl);
    expect(realtime.apiBaseUrl, apiUrl);
    expect(realtime.enabled, enabled);
    expect(
      realtime.mode,
      transport == 'polling'
          ? RealtimeTransportMode.polling
          : RealtimeTransportMode.websocket,
    );
    expect(realtime.urlOverride, socketUrl);
    expect(
      realtime.endpoint.toString(),
      socketUrl.isEmpty ? 'wss://override.example.test/tenant/ws' : socketUrl,
    );
  });
}
