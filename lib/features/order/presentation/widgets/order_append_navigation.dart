import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/order_append_screen.dart';

/// Where an order's "Gọi thêm món" lives, under the section it was opened
/// from, so back returns there and the sidebar stays on that section.
String orderAppendLocation(
  String currentPath,
  String orderId, {
  String? tableName,
}) {
  final id = Uri.encodeComponent(orderId);
  final base = currentPath.startsWith('/app/takeaway')
      ? '/app/takeaway/$id'
      : currentPath.startsWith('/app/orders')
      ? '/app/orders/$id'
      : '/app/order-create/bill/$id';
  final query = tableName == null
      ? ''
      : '?tableName=${Uri.encodeQueryComponent(tableName)}';
  return '$base/add-items$query';
}

/// Opens the one full-screen "Gọi thêm món" for [orderId], wherever the order
/// is shown: Gọi món, Đơn hàng or the takeaway board.
Future<void> openOrderAppend(
  BuildContext context,
  String orderId, {
  String? tableName,
}) async {
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    // Hosts without the app router (embedded previews, tests).
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OrderAppendScreen(orderId: orderId, tableName: tableName),
      ),
    );
    return;
  }
  final here = router.routerDelegate.currentConfiguration.uri.path;
  await router.push(orderAppendLocation(here, orderId, tableName: tableName));
}
