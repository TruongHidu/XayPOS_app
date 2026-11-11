import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/realtime_providers.dart';
import 'package:pos_saas_app/core/realtime/realtime_config.dart';
import 'package:pos_saas_app/core/realtime/realtime_connection_service.dart';
import 'package:pos_saas_app/core/ui/widgets/realtime_connection_banner.dart';
import '../../helpers/realtime_fakes.dart';

class _Connection extends RealtimeConnectionService {
  _Connection()
    : super(
        factory: FakeRealtimeTransport.new,
        endpoint: () => Uri.parse('ws://localhost/ws'),
        refresh: (_) async {},
        recoverAccess: (_) async {},
      );
  bool wants = true, blocked = false;
  int retries = 0;

  @override
  bool get wantsConnection => wants;
  @override
  bool get halted => blocked;
  @override
  void retry() => retries++;

  /// Builds right away, as a real state change would, so timers start now.
  Future<void> move(WidgetTester tester, RealtimeConnectionState next) async {
    state = next;
    notifyListeners();
    await tester.pump();
  }
}

const _offline = ValueKey('realtime-banner-offline');
const _recovered = ValueKey('realtime-banner-recovered');

Future<_Connection> _pump(
  WidgetTester tester, {
  RealtimeTransportMode mode = RealtimeTransportMode.websocket,
}) async {
  final connection = _Connection()..state = RealtimeConnectionState.connected;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        realtimeConnectionProvider.overrideWith((ref) => connection),
        realtimeConfigProvider.overrideWithValue(RealtimeConfig(mode: mode)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: Column(children: [RealtimeConnectionBanner()])),
      ),
    ),
  );
  return connection;
}

void main() {
  testWidgets('short drops stay hidden', (tester) async {
    final connection = await _pump(tester);
    await connection.move(tester, RealtimeConnectionState.reconnecting);
    await tester.pump(const Duration(seconds: 3));
    await connection.move(tester, RealtimeConnectionState.connected);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(_offline), findsNothing);
    expect(find.byKey(_recovered), findsNothing);
  });

  testWidgets('a lasting drop shows, retries, then confirms recovery', (
    tester,
  ) async {
    final connection = await _pump(tester);
    await connection.move(tester, RealtimeConnectionState.reconnecting);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byKey(_offline), findsOneWidget);
    expect(find.textContaining('Mất kết nối'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    expect(connection.retries, 1);

    await connection.move(tester, RealtimeConnectionState.connected);
    await tester.pumpAndSettle();
    expect(find.byKey(_offline), findsNothing);
    expect(find.byKey(_recovered), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byKey(_recovered), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a halted connection explains itself without a retry', (
    tester,
  ) async {
    final connection = await _pump(tester);
    connection
      ..wants = false
      ..blocked = true;
    await connection.move(tester, RealtimeConnectionState.disconnected);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cập nhật tự động đang dừng'), findsOneWidget);
    expect(find.text('Thử lại'), findsNothing);
  });

  testWidgets('nothing shows when updates are off or polled', (tester) async {
    final connection = await _pump(tester);
    connection.wants = false;
    await connection.move(tester, RealtimeConnectionState.disabled);
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(_offline), findsNothing);

    final polled = await _pump(tester, mode: RealtimeTransportMode.polling);
    await polled.move(tester, RealtimeConnectionState.disconnected);
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(_offline), findsNothing);
  });
}
