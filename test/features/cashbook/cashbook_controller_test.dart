import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/cashbook/domain/entities/cashbook_enums.dart';
import 'package:pos_saas_app/features/cashbook/domain/entities/cashbook_filters.dart';
import 'package:pos_saas_app/features/cashbook/domain/entities/cashbook_inputs.dart';
import 'package:pos_saas_app/features/cashbook/domain/use_cases/cashbook_use_cases.dart';
import 'package:pos_saas_app/features/cashbook/presentation/controllers/cashbook_flow_controller.dart';
import 'package:pos_saas_app/features/cashbook/presentation/controllers/cashbook_range_controller.dart';
import 'package:pos_saas_app/features/cashbook/presentation/controllers/expense_actions_controller.dart';
import 'package:pos_saas_app/features/cashbook/presentation/providers/cashbook_providers.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_date.dart';

import '../../helpers/auth_fakes.dart';
import 'cashbook_fakes.dart';

void main() {
  final session = makeAppSession(
    permissions: cashbookPermissions,
    features: cashbookFeatures,
  );
  final october = CashbookRangeFilter(
    range: ReportDateRange(
      fromDate: const ReportDate(2026, 10, 1),
      toDate: const ReportDate(2026, 10, 29),
    ),
  );

  CashbookFlowController flow(
    FakeCashbookRepository repo, {
    CashbookRangeFilter? range,
    CashbookChanges? changes,
  }) => CashbookFlowController(
    session: () => session,
    range: range ?? october,
    getSummary: GetCashbookSummary(repo),
    getSeries: GetCashbookSeries(repo),
    getEntries: GetCashbookEntries(repo),
    changes: changes,
  );

  test('summary, series and entries are read with the same criteria', () async {
    final repo = FakeCashbookRepository();
    final c = flow(repo);
    await c.initialize();
    await c.setType(CashbookEntryType.expense);
    expect(repo.summaryCalls.last.$2.type, CashbookEntryType.expense);
    expect(repo.seriesCalls.last.$2, repo.summaryCalls.last.$2);
    expect(repo.entryCalls.last.$2, repo.summaryCalls.last.$2);
  });

  test(
    'a new range resets the page and picks month buckets for long ranges',
    () async {
      final repo = FakeCashbookRepository();
      final c = flow(repo);
      await c.initialize();
      await c.setPage(1);
      expect(repo.entryCalls.last.$2.page, 1);
      expect(c.granularity, CashbookGranularity.day);
      await c.setRange(
        CashbookRangeFilter(
          range: ReportDateRange(
            fromDate: const ReportDate(2026, 1, 1),
            toDate: const ReportDate(2026, 10, 29),
          ),
        ),
      );
      expect(repo.entryCalls.last.$2.page, 0);
      expect(c.granularity, CashbookGranularity.month);
    },
  );

  test('uninitialized tabs stay lazy and changes reload opened tabs', () async {
    final repo = FakeCashbookRepository();
    final changes = CashbookChanges();
    final c = flow(repo, changes: changes);
    changes.notifyChanged();
    await Future<void>.delayed(Duration.zero);
    expect(repo.summaryCalls, isEmpty);
    await c.initialize();
    final before = repo.summaryCalls.length;
    changes.notifyChanged();
    await Future<void>.delayed(Duration.zero);
    expect(repo.summaryCalls.length, before + 1);
  });

  test('server denial clears panels and is reported once', () async {
    final repo = FakeCashbookRepository()
      ..summaryResult = const Error(
        Failure(type: FailureType.forbidden, message: 'Không có quyền'),
      );
    var reported = 0;
    final c = CashbookFlowController(
      session: () => session,
      range: october,
      getSummary: GetCashbookSummary(repo),
      getSeries: GetCashbookSeries(repo),
      getEntries: GetCashbookEntries(repo),
      onAccessDenied: (_) async => reported++,
    );
    await c.initialize();
    expect(c.accessFailure, isNotNull);
    expect(c.entries.value, isNull);
    expect(reported, 1);
  });

  test('range controller keeps drafts until applied', () {
    final c = CashbookRangeController(
      today: () => const ReportDate(2026, 10, 29),
    );
    expect(c.applied.range.fromDate, const ReportDate(2026, 10, 1));
    c.setDraftCurrency('usd');
    expect(c.applied.currencyCode, isNull);
    expect(c.apply(), isTrue);
    expect(c.applied.currencyCode, 'USD');
    expect(c.isFiltered, isTrue);
    c.setDraftRange(
      ReportDateRange(
        fromDate: const ReportDate(2024, 1, 1),
        toDate: const ReportDate(2026, 10, 29),
      ),
    );
    expect(c.apply(), isFalse);
    expect(c.validationError, isNotNull);
  });

  group('ExpenseSubmitController', () {
    CreateExpenseInput input(int amount) => CreateExpenseInput(
      categoryCode: 'UTILITIES',
      amount: money(amount),
      paymentMethod: CashbookPaymentMethod.cash,
      expenseAt: DateTime.utc(2026, 10, 29, 3),
    );

    test(
      'retrying the same payload reuses its key; an edit gets a new one',
      () async {
        final repo = FakeCashbookRepository()
          ..createResult = const Error(
            Failure(type: FailureType.network, message: 'Mất kết nối'),
          );
        final c = ExpenseSubmitController(
          create: CreateCashbookExpense(repo),
          keys: SequenceKeys(),
        );
        await c.submit(input(100000));
        await c.submit(input(100000));
        expect(repo.createKeys, ['key-1', 'key-1']);
        await c.submit(input(120000));
        expect(repo.createKeys.last, 'key-2');
        repo.createResult = null;
        final created = await c.submit(input(120000));
        expect(created, isNotNull);
        expect(repo.createKeys.last, 'key-2');
        expect(c.pendingKey, isNull);
      },
    );

    test('a key reused for another payload is discarded', () async {
      final repo = FakeCashbookRepository()
        ..createResult = const Error(
          Failure(
            type: FailureType.conflict,
            code: 'CASHBOOK_IDEMPOTENCY_KEY_REUSED',
            message: 'reused',
          ),
        );
      final c = ExpenseSubmitController(
        create: CreateCashbookExpense(repo),
        keys: SequenceKeys(),
      );
      await c.submit(input(100000));
      await c.submit(input(100000));
      expect(repo.createKeys, ['key-1', 'key-2']);
    });
  });

  test('void sends the loaded version and reloads after a conflict', () async {
    final repo = FakeCashbookRepository()
      ..expenses = [testExpense(version: 3)]
      ..voidResult = const Error(
        Failure(
          type: FailureType.conflict,
          code: 'CONCURRENT_CASHBOOK_UPDATE',
          message: 'conflict',
        ),
      );
    final c = ExpenseDetailController(
      expenseId: 'expense-1',
      getExpense: GetCashbookExpense(repo),
      voidExpense: VoidCashbookExpense(repo),
    );
    await c.load();
    final ok = await c.voidExpense('Ghi nhầm số tiền');
    expect(ok, isFalse);
    expect(repo.voidInputs.single.expectedVersion, 3);
    expect(repo.expenseLoads, 2);
    expect(c.voidFailure?.code, 'CONCURRENT_CASHBOOK_UPDATE');
  });
}
