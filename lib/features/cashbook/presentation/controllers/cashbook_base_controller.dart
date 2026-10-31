import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/cashbook_filters.dart';

/// The last response of one panel. A failed refresh keeps the previous value
/// only when it was read for the same query.
class CashbookPanel<T> {
  const CashbookPanel({this.value, this.loading = false, this.failure});
  final T? value;
  final bool loading;
  final Failure? failure;

  CashbookPanel<T> start({required bool keepValue}) =>
      CashbookPanel(value: keepValue ? value : null, loading: true);
  CashbookPanel<T> failed(Failure error, {required bool keepValue}) =>
      CashbookPanel(value: keepValue ? value : null, failure: error);
}

/// Shared plumbing of every cashbook tab: tenant scope, the applied range,
/// stale-response fencing and a single access re-check on server denial.
abstract class CashbookBaseController extends ChangeNotifier {
  CashbookBaseController({
    required this.session,
    required CashbookRangeFilter range,
    this.onAccessDenied,
    Listenable? changes,
  }) : _range = range,
       _changes = changes,
       _scope = AccessPolicy.cashbookScope(session()) {
    _changes?.addListener(_externalChange);
  }

  final AppSession? Function() session;
  final Future<void> Function(Failure)? onAccessDenied;
  final Listenable? _changes;
  final Object? _scope;
  CashbookRangeFilter _range;
  bool _disposed = false, _initialized = false, _reportedDenial = false;
  bool _checkingAccess = false;
  Failure? _accessFailure;
  Timer? _searchTimer;

  CashbookRangeFilter get range => _range;
  bool get initialized => _initialized;
  bool get checkingAccess => _checkingAccess;
  Failure? get accessFailure => _accessFailure;
  bool get current =>
      !_disposed && _scope == AccessPolicy.cashbookScope(session());
  bool canRead(AppSession? session);
  bool get allowed => current && canRead(session()) && _accessFailure == null;

  static const accessTypes = {
    FailureType.unauthorized,
    FailureType.invalidRefreshToken,
    FailureType.forbidden,
    FailureType.featureNotEntitled,
    FailureType.subscriptionNotActive,
    FailureType.restaurantInactive,
  };

  static const _invalid = Failure(
    type: FailureType.internal,
    code: 'INVALID_CASHBOOK_RESPONSE',
    message: 'Chưa tải được sổ thu chi. Vui lòng thử lại.',
  );

  @protected
  void changed() {
    if (current) notifyListeners();
  }

  /// Loads the tab the first time it is shown; later calls are no-ops.
  Future<void> initialize() async {
    if (_initialized || !allowed) return;
    _initialized = true;
    await refresh();
  }

  Future<void> refresh();

  /// Applies a new range from the shared filter. Unopened tabs stay lazy.
  Future<void> setRange(CashbookRangeFilter value) async {
    if (_range == value) return;
    _range = value;
    onRangeChanged();
    if (_initialized) await refresh();
  }

  @protected
  void onRangeChanged() {}

  /// Waits for typing to settle so each keystroke is not a request.
  @protected
  void debounceSearch(VoidCallback action) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), action);
  }

  /// Runs [fetch] and writes its result unless a newer request or another
  /// tenant scope has since taken over. Returns false when access was denied.
  @protected
  Future<bool> run<T>({
    required Future<Result<T>> Function() fetch,
    required bool Function() valid,
    required void Function(Result<T>) write,
  }) async {
    Result<T> result;
    try {
      result = await fetch();
    } catch (_) {
      result = const Error(_invalid);
    }
    if (!current) return false;
    if (result case Error(
      failure: final failure,
    ) when accessTypes.contains(failure.type)) {
      await _deny(failure);
      return false;
    }
    if (!allowed || !valid()) return true;
    write(result);
    changed();
    return true;
  }

  Future<void> _deny(Failure failure) async {
    _accessFailure = failure;
    onAccessLost();
    changed();
    if (_reportedDenial) return;
    _reportedDenial = true;
    try {
      await onAccessDenied?.call(failure);
    } catch (_) {
      // A failed access check cannot grant access to a server-denied scope.
    }
  }

  @protected
  void onAccessLost() {}

  /// A voucher was created or voided elsewhere: every opened tab rereads.
  void _externalChange() {
    if (_initialized && allowed) unawaited(refresh());
  }

  Future<void> retryAccess() async {
    if (!current || _checkingAccess || _accessFailure == null) return;
    _checkingAccess = true;
    changed();
    try {
      await onAccessDenied?.call(_accessFailure!);
    } catch (_) {
      // Keep the denial; the user may try again.
    }
    if (!current) return;
    _checkingAccess = false;
    if (canRead(session())) {
      _accessFailure = null;
      changed();
      await refresh();
    } else {
      changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    _changes?.removeListener(_externalChange);
    super.dispose();
  }
}

String? normalizedQuery(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
