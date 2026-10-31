import '../errors/failure.dart';
import '../result/result.dart';

/// Rows of every page re-read, with the last response for totals and metadata.
class EndlessRead<T, P> {
  const EndlessRead({
    required this.rows,
    required this.lastPage,
    required this.last,
  });
  final List<T> rows;
  final int lastPage;
  final P last;
}

/// Bookkeeping for a list that grows as the user scrolls.
///
/// Controllers keep their own request lifecycle. They route the normal load
/// through [read] and implement `loadMore` with [begin], [append] and [fail].
class EndlessPages<T> {
  EndlessPages(this._idOf);

  final Object Function(T) _idOf;
  bool _appended = false;
  bool loadingMore = false;

  /// Last failed next page. The rows already shown stay valid.
  Failure? failure;

  /// Reads the current list. Page 0 starts over; after [append], `0..page` are
  /// re-read so realtime or mutation refreshes keep the scrolled rows.
  ///
  /// Stops early once the server has fewer pages or [active] turns false.
  Future<Result<EndlessRead<T, P>>> read<P>({
    required int page,
    required Future<Result<P>> Function(int page) fetch,
    required List<T> Function(P) content,
    required int Function(P) totalPages,
    required bool Function() active,
  }) async {
    loadingMore = false;
    failure = null;
    if (page == 0) _appended = false;
    final rows = <T>[];
    final seen = <Object>{};
    for (var index = _appended ? 0 : page; ; index++) {
      switch (await fetch(index)) {
        case Error(failure: final error):
          return Error(error);
        case Success(value: final value):
          rows.addAll(content(value).where((row) => seen.add(_idOf(row))));
          if (index >= page || index >= totalPages(value) - 1 || !active()) {
            return Success(
              EndlessRead(
                rows: List.unmodifiable(rows),
                lastPage: index,
                last: value,
              ),
            );
          }
      }
    }
  }

  void begin() {
    loadingMore = true;
    failure = null;
  }

  /// Joins the next page, dropping rows that shifted across the page boundary.
  List<T> append(List<T> rows, List<T> next) {
    _appended = true;
    loadingMore = false;
    final known = {for (final row in rows) _idOf(row)};
    return List.unmodifiable([
      ...rows,
      ...next.where((row) => known.add(_idOf(row))),
    ]);
  }

  void fail(Failure error) {
    loadingMore = false;
    failure = error;
  }
}
