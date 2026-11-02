import 'dart:async';
import 'package:flutter/material.dart';

/// Asks before leaving the app. A second back press soon after the first
/// answers yes; a later one just closes the dialog, as back normally does.
class ExitConfirmDialog extends StatefulWidget {
  const ExitConfirmDialog({super.key});

  static const doubleBackWindow = Duration(seconds: 2);

  @override
  State<ExitConfirmDialog> createState() => _ExitConfirmDialogState();
}

class _ExitConfirmDialogState extends State<ExitConfirmDialog> {
  bool _withinWindow = true;
  late final Timer _window;

  @override
  void initState() {
    super.initState();
    _window = Timer(
      ExitConfirmDialog.doubleBackWindow,
      () => _withinWindow = false,
    );
  }

  @override
  void dispose() {
    _window.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) Navigator.of(context).pop(_withinWindow);
    },
    child: AlertDialog(
      title: const Text('Thoát ứng dụng?'),
      content: const Text('Bạn có chắc muốn thoát không?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Ở lại'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Thoát'),
        ),
      ],
    ),
  );
}
