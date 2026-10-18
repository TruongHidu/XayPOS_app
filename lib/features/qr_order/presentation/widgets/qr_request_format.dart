String shortQrId(String? id) =>
    id == null ? '—' : id.substring(0, id.length.clamp(0, 8));
String qrRequestTime(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
