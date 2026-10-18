import '../../domain/entities/order_inputs.dart';
import '../../domain/entities/order_payment.dart';
import '../../domain/entities/order_submission.dart';

abstract final class OrderRequests {
  static Map<String, dynamic> payment(RecordOrderPaymentInput input) => {
    'expectedOrderVersion': input.expectedOrderVersion,
    'paymentMethod': input.paymentMethod.code,
    'amount': input.amount.toNumber(),
    if (input.normalizedReferenceNo != null)
      'referenceNo': input.normalizedReferenceNo,
  };
  static Map<String, dynamic> line(CreateOrderLine input) => {
    'itemId': input.itemId,
    'quantity': input.quantity.toNumber(),
    if (input.note != null) 'note': input.note,
  };
  static Map<String, dynamic> create(CreateOrderInput input) => {
    'serviceType': input.context.serviceType.code,
    'sourceChannel': 'WAITER',
    if (input.context.fromTable)
      'tableId': input.context.tableId
    else
      'tableSessionId': input.context.tableSessionId,
    if (input.guestCount != null) 'guestCount': input.guestCount,
    if (input.customerName != null) 'customerName': input.customerName,
    if (input.customerPhone != null) 'customerPhone': input.customerPhone,
    if (input.note != null) 'note': input.note,
    'items': input.items.map(line).toList(),
    if (input.submissionMode != OrderSubmissionMode.draft)
      'submissionMode': input.submissionMode.code,
  };
  static Map<String, dynamic> addition(AddOrderItemsInput input) => {
    'expectedVersion': input.expectedVersion,
    'items': input.items.map(line).toList(),
    if (input.submissionMode != OrderSubmissionMode.draft)
      'submissionMode': input.submissionMode.code,
  };
  static Map<String, dynamic> update(UpdateOrderInput input) => {
    'expectedVersion': input.expectedVersion,
    if (input.guestCount != null) 'guestCount': input.guestCount,
    if (input.customerName != null) 'customerName': input.customerName,
    if (input.customerPhone != null) 'customerPhone': input.customerPhone,
    if (input.note != null) 'note': input.note,
  };
  static Map<String, dynamic> updateLine(UpdateOrderLineInput input) => {
    'expectedVersion': input.expectedVersion,
    if (input.quantity != null) 'quantity': input.quantity!.toNumber(),
    if (input.note != null) 'note': input.note,
  };
}
