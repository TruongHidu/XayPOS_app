import '../../../../core/result/result.dart';
import '../entities/entitlement.dart';

abstract interface class EntitlementRepository {
  Future<Result<Entitlement>> getCurrentEntitlements();
}
