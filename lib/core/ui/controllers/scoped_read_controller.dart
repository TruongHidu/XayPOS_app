import 'package:flutter/foundation.dart';
import '../../errors/failure.dart';
import '../../result/result.dart';

/// A short-lived read panel. Late results never cross a scope or invalidation.
class ScopedReadController<T> extends ChangeNotifier {
  ScopedReadController({
    required this.scope,
    required this.allowed,
    required this.read,
  }) : _scope = scope();
  final Object? Function() scope;
  final Object? _scope;
  final bool Function() allowed;
  final Future<Result<T>> Function() read;
  T? _value;
  T? get value => current ? _value : null;
  Failure? failure;
  bool loading = false, stale = false, _disposed = false, requested = false;
  int _generation = 0;
  bool get current => !_disposed && _scope == scope() && allowed();
  void markStale() {
    if (!current || !requested) return;
    ++_generation;
    stale = true;
    loading = false;
    notifyListeners();
  }

  Future<void> load() async {
    if (!current || loading) return;
    requested = true;
    final generation = ++_generation;
    loading = true;
    failure = null;
    notifyListeners();
    Result<T> result;
    try {
      result = await read();
    } catch (_) {
      result = const Error(
        Failure(
          type: FailureType.internal,
          message: 'Không thể tải dữ liệu nguyên liệu. Vui lòng thử lại.',
        ),
      );
    }
    if (!current || generation != _generation) return;
    switch (result) {
      case Success(value: final value):
        _value = value;
        stale = false;
      case Error(failure: final error):
        failure = error;
        stale = _value != null;
    }
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _value = null;
    super.dispose();
  }
}
