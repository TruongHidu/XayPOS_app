import 'package:dio/dio.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_item_action.dart';
import '../../domain/entities/order_inputs.dart';
import '../../domain/entities/order_payment.dart';
import '../../domain/entities/order_submission.dart';
import '../dto/order_dto.dart';
import '../dto/order_payment_dto.dart';
import '../dto/order_requests.dart';

class OrderRemoteDataSource {
  const OrderRemoteDataSource(this.dio);
  final Dio dio;
  static const path = '/api/v1/orders';
  Options get jsonOptions => Options(headers: {'Accept': 'application/json'});
  Future<OrderPage> list(OrderQuery query) async => OrderDto.page(
    (await dio.get<Object?>(
      path,
      options: jsonOptions,
      queryParameters: {
        if (query.q.trim().isNotEmpty) 'q': query.q.trim(),
        if (query.status != null) 'status': query.status!.code,
        if (query.serviceType != null) 'serviceType': query.serviceType!.code,
        if (query.tableSessionId != null)
          'tableSessionId': query.tableSessionId,
        'page': query.page,
        'size': query.size,
        'sortBy': query.sortBy,
        'direction': query.direction,
      },
    )).data,
  );
  Future<OrderDetail> detail(String id) async => OrderDto.detail(
    (await dio.get<Object?>('$path/$id', options: jsonOptions)).data,
  );
  Future<OrderDetail?> activeForSession(String sessionId) async {
    final response = await dio.get<Object?>(
      '/api/v1/table-sessions/${Uri.encodeComponent(sessionId)}/active-order',
      options: jsonOptions,
    );
    if (response.statusCode == 204) return null;
    if (response.statusCode != 200) {
      throw const FormatException('Invalid active-order status');
    }
    final order = OrderDto.detail(response.data);
    if (order.summary.serviceType != ServiceType.dineIn ||
        order.summary.tableSessionId != sessionId ||
        !const {
          OrderStatus.open,
          OrderStatus.confirmed,
          OrderStatus.preparing,
          OrderStatus.ready,
          OrderStatus.served,
        }.contains(order.summary.status)) {
      throw const FormatException(
        'Active order does not belong to serving session',
      );
    }
    return order;
  }

  Future<OrderSubmission> create(CreateOrderInput input, String key) async {
    final response = await dio.post<Object?>(
      path,
      data: OrderRequests.create(input),
      options: Options(
        contentType: Headers.jsonContentType,
        headers: {'Accept': 'application/json', 'Idempotency-Key': key},
      ),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw const FormatException('Invalid create response status');
    }
    return submission(response);
  }

  Future<OrderSubmission> submitItems(
    String id,
    AddOrderItemsInput input,
    String key,
  ) async {
    final response = await dio.post<Object?>(
      '$path/$id/items',
      data: OrderRequests.addition(input),
      options: Options(
        contentType: Headers.jsonContentType,
        headers: {'Accept': 'application/json', 'Idempotency-Key': key},
      ),
    );
    if (response.statusCode != 200) {
      throw const FormatException('Invalid append response status');
    }
    final result = submission(response);
    if (result.order.id != id) {
      throw const FormatException('Append response belongs to another order');
    }
    return result;
  }

  OrderSubmission submission(Response<Object?> response) {
    final header = response.headers.value('Idempotency-Replayed');
    if (header != null && header != 'true' && header != 'false') {
      throw const FormatException('Invalid replay metadata');
    }
    return OrderSubmission(
      OrderDto.detail(response.data),
      replayed: header == null ? null : header == 'true',
    );
  }

  Future<OrderPayment> recordPayment(
    String id,
    RecordOrderPaymentInput input,
    String idempotencyKey,
  ) async {
    final response = await dio.post<Object?>(
      '$path/${Uri.encodeComponent(id)}/payments',
      data: OrderRequests.payment(input),
      options: Options(
        contentType: Headers.jsonContentType,
        headers: {
          'Accept': 'application/json',
          'Idempotency-Key': idempotencyKey,
        },
      ),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw const FormatException('Invalid payment response status');
    }
    final payment = OrderPaymentDto.parse(response.data);
    if (!payment.successful ||
        payment.orderId != id ||
        payment.amount != input.amount ||
        payment.paymentMethod != input.paymentMethod ||
        payment.referenceNo != input.normalizedReferenceNo ||
        payment.confirmationSource != PaymentConfirmationSource.staffManual) {
      throw const FormatException('Payment response does not match request');
    }
    return payment;
  }

  Future<OrderDetail> complete(String id, int expectedVersion) async {
    final response = await dio.post<Object?>(
      '$path/${Uri.encodeComponent(id)}/complete',
      data: {'expectedVersion': expectedVersion},
      options: Options(
        contentType: Headers.jsonContentType,
        headers: {'Accept': 'application/json'},
      ),
    );
    if (response.statusCode != 200) {
      throw const FormatException('Invalid completion response status');
    }
    final order = OrderDto.detail(response.data);
    if (order.id != id ||
        order.summary.status != OrderStatus.completed ||
        order.completedAt == null) {
      throw const FormatException('Invalid completed order response');
    }
    return order;
  }

  Future<OrderDetail> transitionItem(
    String id,
    String lineId,
    int version,
    OrderItemAction action,
  ) async {
    final order = await mutation(
      'POST',
      '${Uri.encodeComponent(id)}/items/${Uri.encodeComponent(lineId)}/${action.endpoint}',
      {'expectedOrderVersion': version},
    );
    final line = order.items.where((row) => row.id == lineId).firstOrNull;
    if (order.id != id ||
        order.version < version ||
        line?.status != action.target) {
      throw const FormatException('Invalid item transition response');
    }
    return order;
  }

  Future<OrderDetail> markAllServed(String id, int version) async {
    final order = await mutation(
      'POST',
      '${Uri.encodeComponent(id)}/mark-served',
      {'expectedOrderVersion': version},
    );
    final live = order.items.where(
      (row) => row.status != OrderItemStatus.cancelled,
    );
    if (order.id != id ||
        order.version < version ||
        live.isEmpty ||
        live.any((row) => row.status != OrderItemStatus.served)) {
      throw const FormatException('Invalid served order response');
    }
    return order;
  }

  Future<OrderDetail> mutation(
    String method,
    String suffix,
    Map<String, dynamic> body,
  ) async => OrderDto.detail(
    (await dio.request<Object?>(
      '$path/$suffix',
      data: body,
      options: Options(
        method: method,
        contentType: Headers.jsonContentType,
        headers: {'Accept': 'application/json'},
      ),
    )).data,
  );
}
