import 'dart:convert';

class RealtimeEnvelope {
  const RealtimeEnvelope({
    required this.eventId,
    required this.type,
    required this.schemaVersion,
    required this.resourceType,
    required this.resourceId,
    required this.resourceVersion,
    required this.occurredAt,
    required this.payload,
  });
  final String eventId, type, resourceType, resourceId;
  final int schemaVersion, resourceVersion;
  final DateTime occurredAt;
  final Map<String, dynamic> payload;

  static RealtimeEnvelope? parse(String body) {
    if (body.length > 256 * 1024) return null;
    try {
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return null;
      String text(String key) {
        final value = data[key];
        if (value is! String || value.trim().isEmpty || value.length > 200) {
          throw const FormatException('Invalid event field');
        }
        return value;
      }

      final schema = data['schemaVersion'], version = data['resourceVersion'];
      if (schema is! int ||
          schema < 1 ||
          version is! int ||
          version < 0 ||
          data['payload'] is! Map<String, dynamic>) {
        return null;
      }
      final time = DateTime.tryParse(text('occurredAt'));
      if (time == null || !time.isUtc) return null;
      return RealtimeEnvelope(
        eventId: text('eventId'),
        type: text('type'),
        schemaVersion: schema,
        resourceType: text('resourceType'),
        resourceId: text('resourceId'),
        resourceVersion: version,
        occurredAt: time,
        payload: Map.unmodifiable(data['payload'] as Map<String, dynamic>),
      );
    } catch (_) {
      return null;
    }
  }
}
