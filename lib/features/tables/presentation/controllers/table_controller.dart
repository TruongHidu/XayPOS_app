import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/validation/table_validation.dart';
import 'table_events.dart';

/// Request lifetime and shared resource locks, without CRUD/business rules.
class TableController extends ChangeNotifier {
  TableController({
    required AppSession? Function() session,
    required this.events,
    this.onAccessDenied,
  }) : _session = session,
       _scope = AccessPolicy.tableScope(session());
  final AppSession? Function() _session;
  final Object? _scope;
  final TableEvents events;
  final Future<void> Function(Failure)? onAccessDenied;
  bool _disposed = false;
  final Map<String, int> _reads = {};
  bool get isCurrent =>
      !_disposed && _scope == AccessPolicy.tableScope(_session());
  bool can(String permission) =>
      isCurrent &&
      AccessPolicy.canTables(_session(), 'TABLE_VIEW') &&
      AccessPolicy.canTables(_session(), permission);
  bool pending(String key) => events.pending(key);
  static const expired = Failure(
    type: FailureType.forbidden,
    code: 'TABLE_SCOPE_CHANGED',
    message: 'Phiên làm việc hoặc quyền quản lý bàn đã thay đổi.',
  );
  static const empty = Failure(
    type: FailureType.validation,
    code: 'EMPTY_UPDATE_REQUEST',
    message: 'Chưa có thay đổi để lưu.',
  );
  static const occupied = Failure(
    type: FailureType.conflict,
    code: 'TABLE_HAS_OPEN_SESSION',
    message: 'Bàn đang có khách, không thể thực hiện thao tác này.',
  );
  static const terminal = Failure(
    type: FailureType.conflict,
    code: 'INVALID_TABLE_SESSION_TRANSITION',
    message: 'Chỉ phiên đang mở mới được thay đổi.',
  );
  static Failure? validate(Object input) {
    final errors = TableValidation.input(input);
    return errors.isEmpty ? null : validation(errors);
  }

  static Failure? snapshotVersion(int expected, int baseline) =>
      expected == baseline
      ? null
      : validation({
          'expectedVersion':
              'Version không khớp bản đang sửa. Hãy tải lại dữ liệu.',
        });

  static Failure validation(Map<String, String> errors) => Failure(
    type: FailureType.validation,
    code: 'VALIDATION_ERROR',
    message: 'Vui lòng kiểm tra thông tin đã nhập.',
    fieldErrors: errors,
  );
  void changed() {
    if (isCurrent) notifyListeners();
  }

  Future<void> report(Failure f) async {
    if (isCurrent &&
        const {
          FailureType.forbidden,
          FailureType.unauthorized,
          FailureType.featureNotEntitled,
          FailureType.subscriptionNotActive,
          FailureType.restaurantInactive,
        }.contains(f.type)) {
      await onAccessDenied?.call(f);
    }
  }

  Future<Result<T>> read<T>(
    String key,
    Future<Result<T>> Function() operation, {
    String permission = 'TABLE_VIEW',
  }) async {
    if (!can(permission)) return const Error(expired);
    final generation = (_reads[key] ?? 0) + 1;
    _reads[key] = generation;
    final result = await operation();
    if (!can(permission) || _reads[key] != generation) {
      return const Error(expired);
    }
    if (result case Error(failure: final f)) await report(f);
    return can(permission) ? result : const Error(expired);
  }

  Future<Result<T>> mutate<T>(
    String key,
    String permission,
    Future<Result<T>> Function() operation, {
    Failure? invalid,
    required TableChange Function(T) change,
  }) async {
    if (!can(permission)) return const Error(expired);
    if (invalid != null) return Error(invalid);
    if (!events.lock(key)) {
      return const Error(
        Failure(
          type: FailureType.conflict,
          code: 'TABLE_BUSY',
          message: 'Thao tác đang xử lý. Vui lòng chờ.',
        ),
      );
    }
    changed();
    try {
      final result = await operation();
      if (!can(permission)) return const Error(expired);
      if (result case Success(value: final value)) {
        events.emit(change(value));
      }
      if (result case Error(failure: final f)) {
        await report(f);
        if (f.type == FailureType.notFound && isCurrent) onMissing();
        if (f.isNetwork) {
          return Error(
            Failure(
              type: f.type,
              code: f.code,
              fieldErrors: f.fieldErrors,
              message:
                  'Chưa xác định thao tác đã được lưu hay chưa. Hãy tải lại xác minh trước khi gửi lại.',
            ),
          );
        }
      }
      return can(permission) ? result : const Error(expired);
    } finally {
      events.unlock(key);
      changed();
    }
  }

  void onMissing() {}
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
