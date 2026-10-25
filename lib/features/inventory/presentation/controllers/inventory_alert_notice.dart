/// A short-lived display hint, never a substitute for an alert REST response.
class InventoryAlertNotice {
  InventoryAlertNotice({required Set<String> alertIds, this.hasMore = false})
    : alertIds = Set.unmodifiable(alertIds);

  final Set<String> alertIds;
  final bool hasMore;

  String? get singleAlertId =>
      !hasMore && alertIds.length == 1 ? alertIds.single : null;

  String get message {
    if (hasMore) return 'Có nhiều cảnh báo tồn thấp mới.';
    if (alertIds.length == 1) return 'Có cảnh báo tồn thấp mới.';
    return 'Có ${alertIds.length} cảnh báo tồn thấp mới.';
  }
}
