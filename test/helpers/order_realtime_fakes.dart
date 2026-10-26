import 'dart:convert';

const realtimeOrderId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const realtimeRequestId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const realtimeSessionId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const realtimeItemId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const realtimeTableId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
String realtimeEventId(int n) =>
    'aaaaaaaa-aaaa-4aaa-8aaa-${n.toRadixString(16).padLeft(12, '0')}';
Map<String, dynamic> orderEventJson({
  int n = 1,
  int version = 4,
  String id = realtimeOrderId,
  String status = 'CONFIRMED',
  String? session = realtimeSessionId,
  bool fresh = false,
  List<String> changes = const ['ITEMS_ADDED'],
}) => {
  'eventId': realtimeEventId(n),
  'type': 'ORDER_CHANGED',
  'schemaVersion': 1,
  'resourceType': 'ORDER',
  'resourceId': id,
  'resourceVersion': version,
  'occurredAt': '2026-10-25T08:01:00Z',
  'payload': {
    'orderStatus': status,
    'tableSessionId': session,
    'changes': changes,
    'changedOrderItemIds': [realtimeItemId],
    'newKitchenItemIds': fresh ? [realtimeItemId] : <String>[],
  },
};
String orderEvent({int n = 1, int version = 4, bool fresh = false}) =>
    jsonEncode(orderEventJson(n: n, version: version, fresh: fresh));
Map<String, dynamic> qrEventJson({
  int n = 1,
  String kind = 'CREATED',
  bool takeaway = false,
}) => {
  'eventId': realtimeEventId(n),
  'type': 'QR_ORDER_REQUEST_CHANGED',
  'schemaVersion': 1,
  'resourceType': 'QR_ORDER_REQUEST',
  'resourceId': realtimeRequestId,
  'resourceVersion': n,
  'occurredAt': '2026-10-25T08:00:00Z',
  'payload': {
    'status': kind == 'CREATED' ? 'PENDING' : kind,
    'changeKind': kind,
    'entryType': takeaway ? 'RESTAURANT' : 'TABLE',
    'tableId': takeaway ? null : realtimeTableId,
    'observedSessionId': null,
    'approvedOrderId': null,
    'approvedSessionId': null,
  },
};
