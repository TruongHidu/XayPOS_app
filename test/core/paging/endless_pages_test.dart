import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/paging/endless_pages.dart';
import 'package:pos_saas_app/core/result/result.dart';

typedef _Page = ({List<int> rows, int pages});

const _failure = Failure(type: FailureType.network, message: 'offline');

void main() {
  late EndlessPages<int> pages;
  late List<int> calls;

  Future<Result<EndlessRead<int, _Page>>> read(
    int page, {
    int total = 3,
    bool Function()? active,
    Failure? failAt,
  }) => pages.read<_Page>(
    page: page,
    fetch: (index) async {
      calls.add(index);
      if (failAt != null) return Error(failAt);
      return Success((rows: [index * 10, index * 10 + 1], pages: total));
    },
    content: (value) => value.rows,
    totalPages: (value) => value.pages,
    active: active ?? () => true,
  );

  setUp(() {
    pages = EndlessPages<int>((row) => row);
    calls = [];
  });

  test('a list that never appended reads only the requested page', () async {
    final result = await read(1);
    expect(calls, [1]);
    expect((result as Success<EndlessRead<int, _Page>>).value.rows, [10, 11]);
  });

  test('append drops rows that shifted across the page boundary', () {
    expect(pages.append([1, 2], [2, 3]), [1, 2, 3]);
  });

  test('after appending, a refresh re-reads every scrolled page', () async {
    pages.append([0, 1], [10, 11]);
    final result = await read(1);
    expect(calls, [0, 1]);
    final value = (result as Success<EndlessRead<int, _Page>>).value;
    expect(value.rows, [0, 1, 10, 11]);
    expect(value.lastPage, 1);
  });

  test('a refresh stops at the last page the server still has', () async {
    pages.append([0, 1], [10, 11]);
    final result = await read(2, total: 1);
    expect(calls, [0]);
    expect((result as Success<EndlessRead<int, _Page>>).value.lastPage, 0);
  });

  test('a stale refresh stops reading', () async {
    pages.append([0, 1], [10, 11]);
    await read(2, active: () => false);
    expect(calls, [0]);
  });

  test('page 0 starts over after new criteria', () async {
    pages.append([0, 1], [10, 11]);
    await read(0);
    await read(1);
    expect(calls, [0, 1]);
    expect(pages.loadingMore, false);
  });

  test('a failed next page is cleared by the next read', () async {
    pages.begin();
    expect(pages.loadingMore, true);
    pages.fail(_failure);
    expect(pages.loadingMore, false);
    expect(pages.failure, _failure);
    await read(0);
    expect(pages.failure, isNull);
  });

  test('a failed refresh returns the failure', () async {
    pages.append([0, 1], [10, 11]);
    expect(await read(1, failAt: _failure), isA<Error<Object?>>());
    expect(calls, [0]);
  });
}
