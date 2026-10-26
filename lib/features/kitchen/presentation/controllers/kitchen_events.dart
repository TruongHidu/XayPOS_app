import 'package:flutter/foundation.dart';
import '../../../order/presentation/controllers/order_invalidation.dart';

class KitchenEvents extends ChangeNotifier {
  int revision = 0;
  OrderInvalidation? hint;
  void emit(OrderInvalidation value) {
    hint = value;
    revision++;
    notifyListeners();
  }
}
