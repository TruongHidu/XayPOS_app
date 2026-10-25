import 'dart:convert';

enum RealtimeFailureKind {
  handshake,
  stomp,
  closed,
  network,
  heartbeat,
  protocol,
}

/// Only stable, documented codes escape the transport; never raw frames/reasons.
class RealtimeProblem {
  const RealtimeProblem(this.kind, {this.code, this.closeCode, this.channelId});
  final RealtimeFailureKind kind;
  final String? code, channelId;
  final int? closeCode;
  static const codes = {
    'UNAUTHORIZED',
    'TOKEN_EXPIRED',
    'FORBIDDEN',
    'FEATURE_NOT_ENTITLED',
    'SUBSCRIPTION_NOT_ACTIVE',
    'ACCOUNT_INACTIVE',
    'RESTAURANT_INACTIVE',
    'REALTIME_PROTOCOL_VIOLATION',
    'REALTIME_CONNECTION_LIMIT',
  };
  static String? stableCode(String? candidate) =>
      codes.contains(candidate) ? candidate : null;
  static String? errorCode(Map<String, String> headers, String body) {
    final header = stableCode(headers['code']);
    if (header != null) return header;
    try {
      final value = jsonDecode(body);
      return value is Map ? stableCode(value['code'] as String?) : null;
    } catch (_) {
      return null;
    }
  }
}

class RealtimeCallbacks {
  const RealtimeCallbacks({required this.connected, required this.failed});
  final void Function() connected;
  final void Function(RealtimeProblem) failed;
}

/// Read-only transport. Deliberately has no SEND/ACK or business-command API.
abstract interface class RealtimeTransport {
  void open(Uri url, String accessToken, RealtimeCallbacks callbacks);
  void subscribe(String id, String destination, void Function(String) message);
  void unsubscribe(String id);
  Future<void> close();
}

typedef RealtimeTransportFactory = RealtimeTransport Function();
