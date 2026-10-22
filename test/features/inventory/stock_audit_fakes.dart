import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_audit_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_audit_requests.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_quantity.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_audit.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_audit_inputs.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_audit_queries.dart';
import 'package:pos_saas_app/features/inventory/domain/repositories/stock_audit_repository.dart';

const stockAuditPermissions = {
  'INVENTORY_VIEW',
  'STOCK_AUDIT_MANAGE',
  'STOCK_AUDIT_CONFIRM',
};
const stockAuditFeatures = {'INVENTORY_MANAGEMENT', 'STOCK_AUDIT'};

Map<String, dynamic> stockAuditJson({
  String id = 'a1',
  String warehouse = 'w1',
  String status = 'COUNTING',
  int version = 2,
  int itemCount = 2,
  int counted = 1,
  int changed = 1,
  String? note = 'Kiểm kê cuối ca',
  bool detail = true,
  bool started = true,
}) {
  final draft = status == 'DRAFT';
  final confirmed = status == 'CONFIRMED';
  final cancelled = status == 'CANCELLED';
  return {
    'id': id,
    'auditCode': 'AUD-20261021-$id',
    'warehouseId': warehouse,
    'warehouseCode': 'MAIN',
    'warehouseName': 'Kho chính',
    'status': status,
    'note': note,
    'itemCount': draft ? 0 : itemCount,
    'countedItemCount': draft
        ? 0
        : confirmed
        ? itemCount
        : counted,
    'changedItemCount': draft ? 0 : changed,
    'adjustmentDocumentId': confirmed && changed > 0 ? 'adjustment-$id' : null,
    'adjustmentDocumentCode': confirmed && changed > 0 ? 'ADJ-$id' : null,
    'version': version,
    'createdAt': '2026-10-21T08:00:00Z',
    'startedAt': !draft && started ? '2026-10-21T08:05:00Z' : null,
    'updatedAt': '2026-10-21T08:06:00Z',
    if (detail) ...{
      'createdBy': 'user-1',
      'startedBy': !draft && started ? 'user-1' : null,
      'confirmedBy': confirmed ? 'user-1' : null,
      'cancelledBy': cancelled ? 'user-1' : null,
      'confirmedAt': confirmed ? '2026-10-21T08:06:00Z' : null,
      'cancelledAt': cancelled ? '2026-10-21T08:06:00Z' : null,
    },
  };
}

Map<String, dynamic> stockAuditItemJson({
  String id = 'ai1',
  String ingredient = 'i1',
  num system = 10,
  num? counted = 8,
  String? name,
  num cost = 10000,
  String? note = 'Đếm thực tế',
}) => {
  'id': id,
  'ingredientId': ingredient,
  'sku': 'NL-$ingredient',
  'name': name ?? 'Nguyên liệu $ingredient',
  'unit': 'g',
  'systemQuantity': system,
  'countedQuantity': counted,
  'differenceQuantity': counted == null
      ? null
      : num.parse(
          StockAuditDifference.between(
            InventoryQuantity.parse(counted.toString()),
            InventoryQuantity.parse(system.toString()),
          ).toString(),
        ),
  'referenceUnitCostSnapshot': cost,
  'note': note,
};

StockAuditDetail stockAudit({
  String id = 'a1',
  String status = 'COUNTING',
  int version = 2,
  int itemCount = 2,
  int counted = 1,
  int changed = 1,
}) => StockAuditDto.detail(
  stockAuditJson(
    id: id,
    status: status,
    version: version,
    itemCount: itemCount,
    counted: counted,
    changed: changed,
  ),
);

class FakeStockAudits implements StockAuditRepository {
  Map<String, dynamic> value = stockAuditJson();
  List<Map<String, dynamic>> rows = [
    stockAuditItemJson(),
    stockAuditItemJson(id: 'ai2', ingredient: 'i2', counted: null, system: 0),
  ];
  final queries = <StockAuditQuery>[];
  final itemQueries = <StockAuditItemQuery>[];
  final sentKeys = <String>[];
  final sentInputs = <CreateStockAuditInput>[];
  final savedBatches = <StockAuditCountsInput>[];
  final versions = <int>[];
  int details = 0, notes = 0, starts = 0, confirms = 0, cancels = 0;
  Future<Result<InventoryPage<StockAuditSummary>>> Function(StockAuditQuery)?
  onList;
  Future<Result<StockAuditDetail>> Function(String)? onGet;
  Future<Result<InventoryPage<StockAuditItem>>> Function(
    String,
    StockAuditItemQuery,
  )?
  onItems;
  Future<Result<StockAuditDetail>> Function(String, CreateStockAuditInput)?
  onCreate;
  Future<Result<StockAuditDetail>> Function(String, UpdateStockAuditNoteInput)?
  onUpdateNote;
  Future<Result<StockAuditDetail>> Function(String, StockAuditTransitionInput)?
  onStart;
  Future<Result<StockAuditDetail>> Function(String, StockAuditCountsInput)?
  onUpdateCounts;
  Future<Result<StockAuditDetail>> Function(String, StockAuditTransitionInput)?
  onConfirm;
  Future<Result<StockAuditDetail>> Function(String, CancelStockAuditInput)?
  onCancel;
  InventoryPage<T> _page<T>(List<T> all, int page, int size) => InventoryPage(
    content: all.skip(page * size).take(size).toList(),
    page: page,
    size: size,
    totalElements: all.length,
    totalPages: (all.length + size - 1) ~/ size,
  );
  @override
  Future<Result<InventoryPage<StockAuditSummary>>> list(
    StockAuditQuery query,
  ) async {
    queries.add(query);
    if (onList != null) return onList!(query);
    final row = StockAuditDto.summary(value);
    return Success(
      _page(
        [
          if ((query.status == null || query.status == row.status) &&
              (query.warehouseId == null ||
                  query.warehouseId == row.warehouseId))
            row,
        ],
        query.page,
        query.size,
      ),
    );
  }

  @override
  Future<Result<StockAuditDetail>> get(String id) async {
    details++;
    return onGet != null
        ? onGet!(id)
        : Success(StockAuditDto.detail({...value, 'id': id}));
  }

  @override
  Future<Result<InventoryPage<StockAuditItem>>> items(
    String id,
    StockAuditItemQuery query,
  ) async {
    itemQueries.add(query);
    if (onItems != null) return onItems!(id, query);
    final text = query.q.trim().toLowerCase();
    final all = rows
        .map(StockAuditDto.item)
        .where(
          (row) =>
              (query.counted == null ||
                  (row.countedQuantity != null) == query.counted) &&
              (!query.differenceOnly ||
                  row.differenceQuantity != null &&
                      !row.differenceQuantity!.isZero) &&
              (text.isEmpty ||
                  row.name.toLowerCase().contains(text) ||
                  (row.sku ?? '').toLowerCase().contains(text)),
        )
        .toList();
    return Success(_page(all, query.page, query.size));
  }

  @override
  Future<Result<StockAuditDetail>> create(
    String key,
    CreateStockAuditInput input,
  ) async {
    sentKeys.add(key);
    sentInputs.add(input);
    if (onCreate != null) return onCreate!(key, input);
    value = stockAuditJson(
      id: 'created-audit',
      warehouse: input.warehouseId,
      status: 'DRAFT',
      version: 0,
      note: input.note,
    );
    return Success(StockAuditDto.detail(value));
  }

  @override
  Future<Result<StockAuditDetail>> updateNote(
    String id,
    UpdateStockAuditNoteInput input,
  ) async {
    notes++;
    versions.add(input.expectedVersion);
    if (onUpdateNote != null) return onUpdateNote!(id, input);
    value = {
      ...value,
      ...StockAuditRequests.note(input),
      'version': input.expectedVersion + 1,
    };
    return Success(StockAuditDto.detail(value));
  }

  @override
  Future<Result<StockAuditDetail>> start(
    String id,
    StockAuditTransitionInput input,
  ) async {
    starts++;
    versions.add(input.expectedVersion);
    if (onStart != null) return onStart!(id, input);
    value = stockAuditJson(
      id: id,
      status: 'COUNTING',
      version: input.expectedVersion + 1,
      itemCount: rows.length,
      counted: rows.where((r) => r['countedQuantity'] != null).length,
      changed: rows
          .where(
            (r) =>
                r['differenceQuantity'] != null && r['differenceQuantity'] != 0,
          )
          .length,
    );
    return Success(StockAuditDto.detail(value));
  }

  @override
  Future<Result<StockAuditDetail>> updateCounts(
    String id,
    StockAuditCountsInput input,
  ) async {
    savedBatches.add(input);
    versions.add(input.expectedVersion);
    if (onUpdateCounts != null) return onUpdateCounts!(id, input);
    for (final item in input.items) {
      final index = rows.indexWhere((r) => r['id'] == item.auditItemId);
      if (index < 0) continue;
      final row = rows[index], old = StockAuditDto.item(row);
      rows[index] = {
        ...row,
        'countedQuantity': item.countedQuantity.toNumber(),
        'differenceQuantity': num.parse(
          StockAuditDifference.between(
            item.countedQuantity,
            old.systemQuantity,
          ).toString(),
        ),
        if (item.note != null)
          'note': item.note!.trim().isEmpty ? null : item.note!.trim(),
      };
    }
    value = {
      ...value,
      'version': input.expectedVersion + 1,
      'itemCount': rows.length,
      'countedItemCount': rows
          .where((r) => r['countedQuantity'] != null)
          .length,
      'changedItemCount': rows
          .where(
            (r) =>
                r['differenceQuantity'] != null && r['differenceQuantity'] != 0,
          )
          .length,
    };
    return Success(StockAuditDto.detail(value));
  }

  @override
  Future<Result<StockAuditDetail>> confirm(
    String id,
    StockAuditTransitionInput input,
  ) async {
    confirms++;
    versions.add(input.expectedVersion);
    if (onConfirm != null) return onConfirm!(id, input);
    value = {
      ...value,
      'status': 'CONFIRMED',
      'version': input.expectedVersion + 1,
      'countedItemCount': value['itemCount'],
      'confirmedBy': 'user-1',
      'confirmedAt': '2026-10-21T08:06:00Z',
      'adjustmentDocumentId': value['changedItemCount'] == 0
          ? null
          : 'adjustment-$id',
      'adjustmentDocumentCode': value['changedItemCount'] == 0
          ? null
          : 'ADJ-$id',
    };
    return Success(StockAuditDto.detail(value));
  }

  @override
  Future<Result<StockAuditDetail>> cancel(
    String id,
    CancelStockAuditInput input,
  ) async {
    cancels++;
    versions.add(input.expectedVersion);
    if (onCancel != null) return onCancel!(id, input);
    value = {
      ...value,
      'status': 'CANCELLED',
      'version': input.expectedVersion + 1,
      'cancelledBy': 'user-1',
      'cancelledAt': '2026-10-21T08:06:00Z',
      if ((input.note?.trim() ?? '').isNotEmpty) 'note': input.note!.trim(),
    };
    return Success(StockAuditDto.detail(value));
  }
}
