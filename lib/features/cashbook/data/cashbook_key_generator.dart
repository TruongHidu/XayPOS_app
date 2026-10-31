import 'dart:math';
import '../domain/entities/cashbook_inputs.dart';

class SecureCashbookKeyGenerator implements CashbookKeyGenerator {
  final Random _random = Random.secure();
  @override
  String next() =>
      'cashbook-${List.generate(24, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}
