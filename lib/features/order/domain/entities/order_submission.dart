import 'order_entities.dart';

enum OrderSubmissionMode {
  draft('DRAFT'),
  submit('SUBMIT');

  const OrderSubmissionMode(this.code);
  final String code;
}

/// Transport-neutral metadata. Null means the response omitted the header.
class OrderSubmission {
  const OrderSubmission(this.order, {this.replayed});
  final OrderDetail order;
  final bool? replayed;
}
