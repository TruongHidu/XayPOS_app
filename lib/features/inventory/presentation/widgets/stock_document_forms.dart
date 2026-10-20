import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_quantity.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_inputs.dart';
import '../../domain/entities/stock_numbers.dart';
import '../../domain/policies/stock_document_validation.dart';
import '../controllers/inventory_controller.dart';
import 'inventory_widgets.dart';
import 'stock_widgets.dart';

class StockLineEditor extends ConsumerStatefulWidget {
  const StockLineEditor({
    super.key,
    required this.type,
    required this.ingredientId,
    required this.name,
    required this.unit,
    this.sku,
    this.initial,
    this.baseline,
    this.itemId,
    this.onSave,
  });
  final StockDocumentType type;
  final String ingredientId, name, unit;
  final String? sku, itemId;
  final StockLineInput? initial;
  final StockDocumentDetail? baseline;
  final Future<Result<void>> Function(StockLineInput)? onSave;
  @override
  ConsumerState<StockLineEditor> createState() => _StockLineEditorState();
}

class _StockLineEditorState extends ConsumerState<StockLineEditor> {
  final quantity = TextEditingController(),
      cost = TextEditingController(),
      note = TextEditingController();
  AdjustmentDirection? direction;
  StockDocumentDetail? baseline;
  Failure? failure;
  Map<String, String> errors = {};
  bool saving = false, available = true;
  @override
  void initState() {
    super.initState();
    baseline = widget.baseline;
    _fill(widget.initial);
  }

  void _fill(StockLineInput? input) {
    quantity.text = input?.quantity.toString() ?? '';
    cost.text = input?.unitCost.toString() ?? '0';
    note.text = input?.note ?? '';
    direction =
        input?.direction ??
        (widget.type == StockDocumentType.adjustment
            ? AdjustmentDirection.increase
            : null);
  }

  Future<void> _save() async {
    StockLineInput input;
    try {
      input = StockLineInput(
        ingredientId: widget.ingredientId,
        quantity: InventoryQuantity.parse(quantity.text),
        unitCost: StockMoney.unitCost(cost.text),
        direction: direction,
        note: note.text,
      );
    } on FormatException catch (e) {
      setState(
        () => failure = InventoryController.invalid({'number': e.message}),
      );
      return;
    }
    final validation = StockDocumentValidation.line(widget.type, input);
    if (validation.isNotEmpty) {
      setState(() => errors = validation);
      return;
    }
    setState(() {
      saving = true;
      failure = null;
      errors = {};
    });
    final Result response;
    if (baseline != null) {
      response = await ref
          .read(stockDocumentDetailProvider(baseline!.id))
          .saveLine(baseline!, input, itemId: widget.itemId);
    } else {
      response = await widget.onSave!(input);
    }
    if (!mounted) return;
    setState(() => saving = false);
    if (response is Success) {
      Navigator.of(context).pop(true);
    } else if (response case Error(failure: final f)) {
      setState(() {
        failure = f;
        errors = f.fieldErrors;
      });
    }
  }

  Future<void> _reload() async {
    if (!await confirmInventoryDraftReload(context, ref) || !mounted) return;
    final c = ref.read(stockDocumentDetailProvider(baseline!.id));
    await c.load();
    if (!mounted || !c.current || c.failure != null) return;
    setState(() {
      baseline = c.document;
      failure = null;
      errors = {};
      if (widget.itemId != null) {
        final row = baseline?.items
            .where((r) => r.id == widget.itemId)
            .firstOrNull;
        available = row != null;
        if (row != null) {
          _fill(
            StockLineInput(
              ingredientId: row.ingredientId,
              quantity: row.quantity,
              unitCost: row.unitCost,
              direction: row.direction,
              note: row.note,
            ),
          );
        } else {
          failure = const Failure(
            type: FailureType.notFound,
            message: 'Dòng đã bị xóa. Bản đang nhập được giữ để đối chiếu.',
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.baseline == null
        ? null
        : ref.watch(stockDocumentDetailProvider(widget.baseline!.id));
    final enabled = !saving && available && (c?.editable ?? true),
        busy = saving || (c?.busy ?? false) || (c?.loading ?? false);
    String? preview;
    try {
      preview = stockDisplay(
        stockLineCost(
          InventoryQuantity.parse(quantity.text),
          StockMoney.unitCost(cost.text),
        ),
      );
    } on FormatException {
      /* Input may be incomplete. */
    }
    return InventoryDialogFrame(
      title: widget.itemId == null && widget.initial == null
          ? 'Thêm dòng nguyên liệu'
          : 'Sửa dòng nguyên liệu',
      busy: busy,
      canClose:
          c == null ||
          !InventoryController.unknown(c.events.verification(c.key)),
      actions: [
        if (c != null && (c.requiresReview || c.failure != null))
          OutlinedButton(
            onPressed: busy ? null : _reload,
            child: const Text('Tải lại để đối chiếu'),
          ),
        FilledButton(
          onPressed: enabled ? _save : null,
          child: const Text('Lưu dòng'),
        ),
      ],
      children: [
        Text(widget.name, style: Theme.of(context).textTheme.titleMedium),
        Text('${widget.sku ?? 'Chưa có SKU'} · Đơn vị: ${widget.unit}'),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('stock-line-quantity'),
          controller: quantity,
          enabled: enabled,
          decoration: inventoryField(
            'Số lượng',
            error: errors['quantity'],
          ).copyWith(suffixText: widget.unit),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('stock-line-cost'),
          controller: cost,
          enabled: enabled,
          decoration: inventoryField('Đơn giá vốn', error: errors['unitCost']),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text('Thành tiền tạm tính: ${preview ?? '—'}'),
        const Text(
          'Dùng dấu chấm thập phân. Số lượng tối đa 3 chữ số lẻ, đơn giá tối đa 2 chữ số lẻ.',
        ),
        if (widget.type == StockDocumentType.adjustment) ...[
          const SizedBox(height: 12),
          StockSelect(
            label: 'Hướng điều chỉnh',
            value: direction!.code,
            items: {
              for (final d in AdjustmentDirection.values) d.code: d.label,
            },
            enabled: enabled,
            changed: (v) => setState(
              () => direction = AdjustmentDirection.values.firstWhere(
                (d) => d.code == v,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('stock-line-note'),
          controller: note,
          enabled: enabled,
          maxLength: 1000,
          minLines: 2,
          maxLines: 5,
          decoration: inventoryField('Ghi chú dòng', error: errors['note']),
        ),
        InventoryFailurePanel(failure: failure ?? c?.failure),
        if (c?.requiresReview == true)
          const Text(
            'Bản đang nhập được giữ. Tải lại và đối chiếu trước khi lưu tiếp.',
          ),
      ],
    );
  }

  @override
  void dispose() {
    quantity.dispose();
    cost.dispose();
    note.dispose();
    super.dispose();
  }
}

class StockNoteEditor extends ConsumerStatefulWidget {
  const StockNoteEditor({super.key, required this.baseline});
  final StockDocumentDetail baseline;
  @override
  ConsumerState<StockNoteEditor> createState() => _StockNoteEditorState();
}

class _StockNoteEditorState extends ConsumerState<StockNoteEditor> {
  late StockDocumentDetail baseline = widget.baseline;
  late final TextEditingController note = TextEditingController(
    text: baseline.note ?? '',
  );
  Failure? failure;
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(stockDocumentDetailProvider(widget.baseline.id));
    return InventoryDialogFrame(
      title: 'Sửa ghi chú chứng từ',
      busy: c.loading || c.busy,
      canClose: !InventoryController.unknown(c.events.verification(c.key)),
      actions: [
        if (c.requiresReview || c.failure != null)
          OutlinedButton(
            onPressed: c.busy || c.loading
                ? null
                : () async {
                    if (!await confirmInventoryDraftReload(context, ref) ||
                        !context.mounted) {
                      return;
                    }
                    await c.load();
                    if (!context.mounted ||
                        !c.current ||
                        c.failure != null ||
                        c.document == null) {
                      return;
                    }
                    setState(() {
                      baseline = c.document!;
                      note.text = baseline.note ?? '';
                      failure = null;
                    });
                  },
            child: const Text('Tải lại để đối chiếu'),
          ),
        FilledButton(
          onPressed: !c.editable
              ? null
              : () async {
                  final response = await c.saveNote(baseline, note.text);
                  if (!context.mounted || !c.current) return;
                  if (response is Success) {
                    Navigator.of(context).pop(true);
                  } else if (response case Error(failure: final f)) {
                    setState(() => failure = f);
                  }
                },
          child: const Text('Lưu ghi chú'),
        ),
      ],
      children: [
        Text(baseline.documentCode),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('stock-document-note'),
          controller: note,
          enabled: c.editable,
          maxLength: 2000,
          minLines: 3,
          maxLines: 8,
          decoration: inventoryField(
            'Ghi chú chứng từ',
            error: failure?.fieldErrors['note'],
          ),
        ),
        InventoryFailurePanel(failure: failure ?? c.failure),
      ],
    );
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }
}
