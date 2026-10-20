import 'dart:math';
import '../domain/entities/stock_inputs.dart';

class SecureStockKeyGenerator implements StockKeyGenerator {
  final Random _random = Random.secure();
  @override
  String next() =>
      'stock-${List.generate(24, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}
