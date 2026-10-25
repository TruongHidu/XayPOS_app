import 'package:pos_saas_app/core/realtime/realtime_transport.dart';
import 'package:pos_saas_app/core/realtime/realtime_connection_service.dart';
import 'package:pos_saas_app/core/realtime/realtime_preference_storage.dart';

class MemoryRealtimePreferenceStorage implements RealtimePreferenceStorage {
  MemoryRealtimePreferenceStorage([this.value]);
  bool? value;
  int reads = 0;
  final writes = <bool>[];
  Future<bool?> Function()? onRead;
  Future<void> Function(bool)? onWrite;
  @override
  Future<bool?> read() async {
    reads++;
    return onRead == null ? value : onRead!();
  }

  @override
  Future<void> write(bool enabled) async {
    writes.add(enabled);
    await onWrite?.call(enabled);
    value = enabled;
  }
}

class FakeRealtimeTransport implements RealtimeTransport {
  Uri? url;
  String? token;
  RealtimeCallbacks? callbacks;
  final Map<String, void Function(String)> handlers = {};
  final destinations = <String>[];
  int opens = 0, closes = 0;
  bool closed = false;
  @override
  void open(Uri url, String accessToken, RealtimeCallbacks callbacks) {
    opens++;
    this.url = url;
    token = accessToken;
    this.callbacks = callbacks;
  }

  @override
  void subscribe(String id, String destination, void Function(String) message) {
    destinations.add(destination);
    handlers[id] = message;
  }

  @override
  void unsubscribe(String id) => handlers.remove(id);
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    closes++;
    handlers.clear();
  }

  void connected() => callbacks!.connected();
  void fail(RealtimeProblem problem) => callbacks!.failed(problem);
}

class FakeRealtimeFactory {
  final transports = <FakeRealtimeTransport>[];
  FakeRealtimeTransport call() {
    final transport = FakeRealtimeTransport();
    transports.add(transport);
    return transport;
  }

  FakeRealtimeTransport get last => transports.last;
}

const realtimeTestSession = RealtimeSession(
  'user/tenant',
  'grants-v1',
  'access-1',
);
RealtimeChannel testRealtimeChannel({
  void Function()? resync,
  void Function(String)? message,
  String id = 'inventory-alerts',
}) => RealtimeChannel(
  id: id,
  destination: '/user/queue/$id',
  message: message ?? (_) {},
  resync: resync ?? () {},
);
