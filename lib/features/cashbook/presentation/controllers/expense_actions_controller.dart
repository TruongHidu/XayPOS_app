import 'package:flutter/foundation.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/cashbook_inputs.dart';
import '../../domain/entities/cashbook_records.dart';
import '../../domain/use_cases/cashbook_use_cases.dart';

/// Submits a voucher exactly once per intent. A retry of the same payload
/// (after a timeout, say) reuses its Idempotency-Key so the server can answer
/// with the original voucher; any edit to the payload is a new voucher.
class ExpenseSubmitController extends ChangeNotifier {
  ExpenseSubmitController({
    required CreateCashbookExpense create,
    required CashbookKeyGenerator keys,
  }) : _create = create,
       _keys = keys;

  final CreateCashbookExpense _create;
  final CashbookKeyGenerator _keys;
  CreateExpenseInput? _pendingInput;
  String? _pendingKey;
  bool _submitting = false, _disposed = false;
  Failure? failure;

  bool get submitting => _submitting;

  /// The key the next submit of [input] will carry. Exposed for tests.
  String? get pendingKey => _pendingKey;

  Future<ExpenseCreateResult?> submit(CreateExpenseInput input) async {
    if (_submitting) return null;
    if (_pendingInput != input) {
      _pendingInput = input;
      _pendingKey = _keys.next();
    }
    final key = _pendingKey!;
    _submitting = true;
    failure = null;
    _notify();
    final result = await _create(input, idempotencyKey: key);
    if (_disposed) return null;
    _submitting = false;
    switch (result) {
      case Success(:final value):
        _pendingInput = null;
        _pendingKey = null;
        _notify();
        return value;
      case Error(failure: final error):
        // The server already bound this key to another payload: a fresh
        // attempt must not collide with it again.
        if (error.code == 'CASHBOOK_IDEMPOTENCY_KEY_REUSED') {
          _pendingInput = null;
          _pendingKey = null;
        }
        failure = error;
        _notify();
        return null;
    }
  }

  void clearFailure() {
    if (failure == null) return;
    failure = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// One voucher shown in the detail dialog, plus its void action.
class ExpenseDetailController extends ChangeNotifier {
  ExpenseDetailController({
    required this.expenseId,
    required GetCashbookExpense getExpense,
    required VoidCashbookExpense voidExpense,
    CashbookExpense? initial,
  }) : _getExpense = getExpense,
       _voidExpense = voidExpense,
       _expense = initial;

  final String expenseId;
  final GetCashbookExpense _getExpense;
  final VoidCashbookExpense _voidExpense;
  CashbookExpense? _expense;
  bool _loading = false, _voiding = false, _disposed = false;
  Failure? loadFailure, voidFailure;
  int _generation = 0;

  CashbookExpense? get expense => _expense;
  bool get loading => _loading;
  bool get voiding => _voiding;

  Future<void> load() async {
    final generation = ++_generation;
    _loading = true;
    loadFailure = null;
    _notify();
    final result = await _getExpense(expenseId);
    if (_disposed || generation != _generation) return;
    _loading = false;
    switch (result) {
      case Success(:final value):
        _expense = value;
      case Error(:final failure):
        loadFailure = failure;
    }
    _notify();
  }

  /// Voids against the latest known version. On a version conflict the newer
  /// state is reloaded; the caller keeps the typed reason for a second look.
  Future<bool> voidExpense(String reason) async {
    final current = _expense;
    if (current == null || current.isVoided || _voiding) return false;
    _voiding = true;
    voidFailure = null;
    _notify();
    final result = await _voidExpense(
      expenseId,
      VoidExpenseInput(expectedVersion: current.version, reason: reason),
    );
    if (_disposed) return false;
    _voiding = false;
    switch (result) {
      case Success(:final value):
        ++_generation;
        _expense = value;
        _notify();
        return true;
      case Error(:final failure):
        voidFailure = failure;
        _notify();
        if (failure.type == FailureType.conflict ||
            failure.type == FailureType.notFound) {
          await load();
        }
        return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
