/// How long something has been going on, in the words staff use at a glance:
/// "Vừa vào", "45 phút", "1 giờ 5 phút", "2 ngày 3 giờ".
String formatElapsed(Duration elapsed) {
  final minutes = elapsed.inMinutes;
  if (minutes < 1) return 'Vừa vào';
  if (minutes < 60) return '$minutes phút';
  final hours = minutes ~/ 60;
  if (hours < 24) {
    final rest = minutes % 60;
    return '$hours giờ${rest == 0 ? '' : ' $rest phút'}';
  }
  final rest = hours % 24;
  return '${hours ~/ 24} ngày${rest == 0 ? '' : ' $rest giờ'}';
}
