import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../../domain/entities/table_query.dart';
import 'table_controller.dart';

abstract class TableListController<T> extends TableController {
  TableListController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.kind,
    required Future<Result<TablePage<T>>> Function(TableQuery) list,
    this.query = const TableQuery(),
  }) : _list = list;
  final TableQueryKind kind;
  final Future<Result<TablePage<T>>> Function(TableQuery) _list;
  TableQuery query;
  List<T> rows = [];
  int totalElements = 0, totalPages = 0;
  bool loading = false, hasLoaded = false;
  Failure? failure;
  int _generation = 0;
  Timer? _timer;
  void setQuery(TableQuery value, {bool debounce = false}) {
    if (!can('TABLE_VIEW')) return;
    _timer?.cancel();
    ++_generation;
    if (!value.valid(kind)) {
      loading = false;
      failure = TableController.validation({
        'q': 'Bộ lọc không hợp lệ; từ khóa tối đa 100 ký tự.',
      });
      changed();
      return;
    }
    query = value.copyWith(page: 0);
    failure = null;
    changed();
    if (debounce) {
      _timer = Timer(const Duration(milliseconds: 350), load);
    } else {
      unawaited(load());
    }
  }

  void search(String value) =>
      setQuery(query.copyWith(q: value.trim()), debounce: true);
  void setPage(int value) {
    if (value < 0 || value >= totalPages && value != 0 || !can('TABLE_VIEW')) {
      return;
    }
    query = query.copyWith(page: value);
    unawaited(load());
  }

  Future<void> load() async {
    if (!can('TABLE_VIEW')) return;
    _timer?.cancel();
    final generation = ++_generation;
    loading = true;
    failure = null;
    changed();
    final result = await _list(query);
    if (!can('TABLE_VIEW') || generation != _generation) return;
    switch (result) {
      case Success(value: final page):
        if (query.page > 0 &&
            page.content.isEmpty &&
            page.totalPages <= query.page) {
          query = query.copyWith(
            page: page.totalPages > 0 ? page.totalPages - 1 : 0,
          );
          await load();
          return;
        }
        rows = page.content;
        totalElements = page.totalElements;
        totalPages = page.totalPages;
        hasLoaded = true;
      case Error(failure: final f):
        await report(f);
        if (!isCurrent || generation != _generation) return;
        failure = f;
    }
    loading = false;
    changed();
  }

  Future<Result<T>> detail(String id, Future<Result<T>> Function() get) async {
    final result = await read('detail:$id', get);
    if (result case Error(
      failure: final f,
    ) when f.type == FailureType.notFound) {
      unawaited(load());
    }
    return result;
  }

  Future<Result<TablePage<T>>> verifyCreation(TableQuery filter) =>
      read('verify-creation', () => _list(filter));

  @override
  void onMissing() {
    unawaited(load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    ++_generation;
    rows = [];
    failure = null;
    totalElements = 0;
    totalPages = 0;
    super.dispose();
  }
}
