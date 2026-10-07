import 'package:flutter/material.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import 'table_area_picker.dart';
import 'table_dialogs.dart';

/// A timed-out create has no resource ID to reload. Let the user inspect a
/// fresh, paginated search without losing the draft or changing list filters.
class TableCreationCheck<T> extends StatefulWidget {
  const TableCreationCheck({
    super.key,
    required this.fetch,
    required this.label,
  });
  final Future<Result<TablePage<T>>> Function(int) fetch;
  final String Function(T) label;
  @override
  State<TableCreationCheck<T>> createState() => _TableCreationCheckState<T>();
}

class _TableCreationCheckState<T> extends State<TableCreationCheck<T>> {
  TablePage<T>? _page;
  Failure? _failure;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load(0);
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    final result = await widget.fetch(page);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Success(value: final p):
          _page = p;
        case Error(failure: final f):
          _failure = f;
      }
    });
  }

  @override
  Widget build(BuildContext context) => TableFormLayout(
    title: 'Kiểm tra kết quả tạo',
    busy: _loading,
    submitLabel: 'Đã kiểm tra, cho phép gửi lại',
    onSubmit: _failure != null || _page == null
        ? null
        : () => Navigator.pop(context, true),
    children: [
      const Text(
        'Nếu mục vừa tạo đã có trong danh sách, hãy đóng form để tránh tạo trùng. Chỉ gửi lại sau khi bạn đã kiểm tra kết quả dưới đây.',
      ),
      TableFailurePanel(
        failure: _failure,
        onReload: () => _load(_page?.page ?? 0),
      ),
      if (_page != null) ...[
        for (final row in _page!.content)
          ListTile(title: Text(widget.label(row))),
        if (_page!.content.isEmpty)
          const Text('Chưa tìm thấy kết quả phù hợp trên máy chủ.'),
        TablePagination(
          page: _page!.page,
          pages: _page!.totalPages,
          total: _page!.totalElements,
          onPage: _load,
        ),
      ],
    ],
  );
}
