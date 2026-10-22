/// Half-open instants [from, to). Day selection follows the local calendar.
class InventoryInstantRange {
  const InventoryInstantRange({this.from, this.to});
  factory InventoryInstantRange.days(DateTime first, DateTime last) =>
      InventoryInstantRange(
        from: DateTime(first.year, first.month, first.day).toUtc(),
        to: DateTime(last.year, last.month, last.day + 1).toUtc(),
      );
  final DateTime? from, to;
  bool get valid => from == null || to == null || from!.isBefore(to!);
  bool get isValid => valid;
  bool get isEmpty => from == null && to == null;
}
