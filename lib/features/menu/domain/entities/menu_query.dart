import 'menu_item.dart';

/// Optional item filters are rejected when this query is used for groups.
class MenuQuery {
  const MenuQuery({
    this.q = '',
    this.active,
    this.page = 0,
    this.size = 20,
    this.sortBy = 'createdAt',
    this.direction = 'desc',
    this.groupId,
    this.availabilityStatus,
    this.sellable,
  });
  final String q;
  final bool? active;
  final int page;
  final int size;
  final String sortBy;
  final String direction;
  final String? groupId;
  final AvailabilityStatus? availabilityStatus;
  final bool? sellable;

  bool get hasFilters =>
      q.trim().isNotEmpty ||
      active != null ||
      groupId != null ||
      availabilityStatus != null ||
      sellable != null;

  bool isValid({required bool items}) =>
      q.trim().length <= 100 &&
      page >= 0 &&
      size >= 1 &&
      size <= 100 &&
      const {'asc', 'desc'}.contains(direction) &&
      (items
              ? const {'createdAt', 'updatedAt', 'name', 'salePrice'}
              : const {'createdAt', 'updatedAt', 'name', 'displayOrder'})
          .contains(sortBy) &&
      (groupId == null || groupId!.trim().isNotEmpty) &&
      (items ||
          groupId == null && availabilityStatus == null && sellable == null);

  MenuQuery copyWith({
    String? q,
    bool? Function()? active,
    int? page,
    int? size,
    String? sortBy,
    String? direction,
    String? Function()? groupId,
    AvailabilityStatus? Function()? availabilityStatus,
    bool? Function()? sellable,
  }) => MenuQuery(
    q: q ?? this.q,
    active: active != null ? active() : this.active,
    page: page ?? this.page,
    size: size ?? this.size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
    groupId: groupId != null ? groupId() : this.groupId,
    availabilityStatus: availabilityStatus != null
        ? availabilityStatus()
        : this.availabilityStatus,
    sellable: sellable != null ? sellable() : this.sellable,
  );
}
