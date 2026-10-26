import '../../../../core/realtime/realtime_envelope.dart';
import '../../../order/data/dto/order_realtime_payload.dart';

class QrRealtimePayload {
  const QrRealtimePayload._(
    this.status,
    this.changeKind,
    this.entryType,
    this.tableId,
    this.observedSessionId,
    this.approvedOrderId,
    this.approvedSessionId,
  );
  final String status, changeKind, entryType;
  final String? tableId, observedSessionId, approvedOrderId, approvedSessionId;
  static const _states = {
    'CREATED': 'PENDING',
    'APPROVED': 'APPROVED',
    'REJECTED': 'REJECTED',
    'CANCELLED': 'CANCELLED',
  };
  static QrRealtimePayload? parse(RealtimeEnvelope event) {
    if (event.schemaVersion != 1 ||
        event.type != 'QR_ORDER_REQUEST_CHANGED' ||
        event.resourceType != 'QR_ORDER_REQUEST' ||
        !OrderRealtimePayload.validId(event.resourceId) ||
        !OrderRealtimePayload.validId(event.eventId)) {
      return null;
    }
    final p = event.payload;
    if (!_states.containsKey(p['changeKind']) ||
        _states[p['changeKind']] != p['status'] ||
        !const {'TABLE', 'RESTAURANT'}.contains(p['entryType'])) {
      return null;
    }
    for (final key in [
      'tableId',
      'observedSessionId',
      'approvedOrderId',
      'approvedSessionId',
    ]) {
      if (!p.containsKey(key) ||
          p[key] != null && !OrderRealtimePayload.validId(p[key])) {
        return null;
      }
    }
    return QrRealtimePayload._(
      p['status'] as String,
      p['changeKind'] as String,
      p['entryType'] as String,
      p['tableId'] as String?,
      p['observedSessionId'] as String?,
      p['approvedOrderId'] as String?,
      p['approvedSessionId'] as String?,
    );
  }
}
